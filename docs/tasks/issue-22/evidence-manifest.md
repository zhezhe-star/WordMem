# Issue #22 Evidence Manifest

Date: 2026-11-15
Branch: `zhezhe-star/翻译流程-bug-修复`

## Environment

| Item | Value |
| --- | --- |
| Xcode | 27.1 (27A9275) |
| Primary test simulator | **iPhone 17 Pro**, iOS 27.0, UDID `55DBFA05-48DE-453C-8871-288A22D251F3` |
| Supplementary simulator | iPhone Duo Test, iOS 27.1, UDID `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0` |
| Runtime setup | Independent agent installed iOS 27.0 (24A434) via `xcodebuild -downloadPlatform iOS -buildVersion 27.0` |
| Real device | None connected |

The old iPhone 17 Pro simulator bound to the missing iOS 26.4 runtime was left
untouched; a new iPhone 17 Pro simulator was created on iOS 27.0.

## Automated verification

```text
xcodebuild test -project WordMem.xcodeproj -scheme WordMem \
  -destination 'platform=iOS Simulator,id=55DBFA05-48DE-453C-8871-288A22D251F3'

Executed 126 tests, with 0 failures
** TEST SUCCEEDED **
```

Release builds:

```text
xcodebuild build -scheme WordMem -configuration Release ...            → BUILD SUCCEEDED
xcodebuild build -scheme WordMemShareExtension -configuration Release  → BUILD SUCCEEDED
xcodebuild build -scheme WordMemTranslationProvider -configuration Release → BUILD SUCCEEDED
```

Logs: `docs/tasks/issue-22/logs/` (`tests-iphone17pro.log`).

## Simulator smoke

1. On iPhone 17 Pro (iOS 27.0), text import + dismiss keyboard shows the single
   informational alert “暂不支持翻译 / 知道了”. No inline retry button exists.
2. The fresh iOS 27.0 runtime has no system dictionary assets yet, so it reports
   “没有可保存的单词”; this is an environment limitation, not the import flow.
3. Save-path smoke was therefore completed on iPhone Duo Test (iOS 27.1):
   dismiss alert, select two chips, import; both words save without translation
   because the simulator cannot run Translation.

Screenshots:

- `screenshots/01-unsupported-translation-alert.jpg`
- `screenshots/02-review-no-inline-retry.jpg`
- `screenshots/03-saved-words.jpg`
- `screenshots/04-iphone17pro-unsupported-alert.jpg`

A copy for remote review lives in the untracked `tmp-issue-22-screenshots/`.

## Disclosure

- The simulator can only exercise the unsupported-pair terminal state. The
  retryable failure alert, retry-whole-flow behavior, and cancel paths are
  covered by deterministic unit tests with fake translation sessions.
- Real Translation behavior (first-run download, high-fidelity fallback,
  retryable failure) must be verified on a physical iPhone using
  `real-device-checklist.md`.
