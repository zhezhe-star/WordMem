#!/bin/bash
# Guard: the import review screen must mount exactly ONE .translationTask.
# Regression being prevented: issue #22 root cause R1 — a second parallel
# Translation session caused first-run translation failures.
# Usage: bash scripts/check-single-translation-task.sh   (exit 0 = pass)
set -euo pipefail

EXPECTED_MAIN=1          # main app import flow
EXPECTED_SHARE=1         # share extension
EXPECTED_PROVIDER=2      # translation provider: TranslationCardView + WordPickerView

count() { grep -r "translationTask(" "$1" --include="*.swift" | wc -l | tr -d ' '; }

main_n=$(count WordMem)
share_n=$(count WordMemShareExtension)
provider_n=$(count WordMemTranslationProvider)

status=0
check() { # name actual expected
  if [ "$2" -eq "$3" ]; then
    echo "PASS $1: $2 .translationTask mount(s)"
  else
    echo "FAIL $1: found $2, expected $3 — extra parallel Translation sessions regress issue #22 (R1)"
    status=1
  fi
}
check "WordMem"                "$main_n"     "$EXPECTED_MAIN"
check "WordMemShareExtension"  "$share_n"    "$EXPECTED_SHARE"
check "WordMemTranslationProvider" "$provider_n" "$EXPECTED_PROVIDER"
exit $status
