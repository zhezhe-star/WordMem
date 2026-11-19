#!/bin/bash
# Heartbeat: verify a push to release/testflight actually started an Xcode Cloud
# build within the grace period. Prevents the silent webhook loss that left
# TestFlight 3 days stale (issue #22 release, 2026-11-16..18).
# Usage:
#   bash scripts/xcode-cloud-heartbeat.sh <expected-commit-sha> [--wait <minutes>]
# Exit 0 = build started (and optionally SUCCEEDED); 1 = no build detected.
set -euo pipefail

SHA="${1:?usage: xcode-cloud-heartbeat.sh <expected-commit-sha> [--wait minutes]}"
WAIT_MIN="${3:-10}"
PRODUCT="7514a0e4-0655-4a40-877c-bbba4902deff"
ASC="$HOME/.appstoreconnect/asc-api.swift"

deadline=$(( $(date +%s) + WAIT_MIN * 60 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  RUN=$(swift "$ASC" "/v1/ciProducts/$PRODUCT/buildRuns?limit=200" 2>/dev/null) || { sleep 60; continue; }
  HIT=$(echo "$RUN" | python3 -c "
import json,sys
d=json.load(sys.stdin, strict=False)
rs=sorted(d['data'], key=lambda r: r['attributes'].get('number') or 0)[-5:]
for r in rs:
    a=r['attributes']; sc=(a.get('sourceCommit') or {})
    if sc.get('commitSha','').startswith('$SHA'):
        print(a.get('number'), a.get('executionProgress'), a.get('completionStatus'))
        break
")
  if [ -n "$HIT" ]; then
    echo "Build found for $SHA: number/progress/status = $HIT"
    case "$HIT" in
      *FAILED*|*ERRORED*|*CANCELED*) exit 1;;
      *SUCCEEDED*) exit 0;;
      *) sleep 60;;  # RUNNING — keep waiting
    esac
  else
    echo "$(date +%H:%M) no build for $SHA yet; retrying in 60s"
    sleep 60
  fi
done
echo "ERROR: no Xcode Cloud build for $SHA within ${WAIT_MIN} min — webhook likely lost. Re-trigger with an empty commit (see .claude/skills/xcodecloud-trigger)." >&2
exit 1
