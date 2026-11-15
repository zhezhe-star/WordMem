# Issue #22 Evidence Manifest

Date: 2026-11-15
Branch: `zhezhe-star/翻译流程-bug-修复`

## Environment

| Item | Value |
| --- | --- |
| Xcode | 27.1 (27A9275) |
| Simulator used | iPhone Duo Test, iOS 27.1, UDID `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0` |
| iPhone 17 Pro simulator | Unavailable at test time: bound to iOS 26.4 runtime, which is not installed; iOS 27.1 runtime only supports iPhone Duo |
| Real device | None connected |

Runtime installation for iPhone 17 Pro was delegated to an independent agent and
is still running at the time this manifest was written. Do not treat the
simulator results below as real-device translation evidence.

## Automated verification

```text
xcodebuild test -project WordMem.xcodeproj -scheme WordMem \
  -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0'

Executed 126 tests, with 0 failures
** TEST SUCCEEDED **
```

Release builds:

```text
xcodebuild build -scheme WordMem -configuration Release ...            → BUILD SUCCEEDED
xcodebuild build -scheme WordMemShareExtension -configuration Release  → BUILD SUCCEEDED
xcodebuild build -scheme WordMemTranslationProvider -configuration Release → BUILD SUCCEEDED
```

Logs: `docs/tasks/issue-22/logs/`.

## Simulator smoke

1. Text import: type English, dismiss keyboard.
2. Simulator reports the pair unsupported, so the single informational alert
   “暂不支持翻译 / 知道了” appears. No inline retry button exists.
3. Dismiss alert, select two chips, import. Both words save; translation is
   absent because the simulator cannot run Translation.

Screenshots:

- `screenshots/01-unsupported-translation-alert.jpg`
- `screenshots/02-review-no-inline-retry.jpg`
- `screenshots/03-saved-words.jpg`

A copy for remote review lives in the untracked `tmp-issue-22-screenshots/`.

## Disclosure

- The simulator can only exercise the unsupported-pair terminal state. The
  retryable failure alert, retry-whole-flow behavior, and cancel paths are
  covered by deterministic unit tests with fake translation sessions.
- Real Translation behavior (first-run download, high-fidelity fallback,
  retryable failure) must be verified on a physical iPhone using
  `real-device-checklist.md`.
