# Translation Availability and Fallback Evidence Manifest

- Commit: `c1b318161862f147036f0c92c5351baece141884`
- Branch: `feature/import-document-pipeline`
- Simulator: iPhone Duo Test, UDID `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`, iOS 27.1, booted
- App: `com.zhezhe.wordmem`, version `0.1.0`, build `1`, Debug, installed from current HEAD
- Derived data: `/private/tmp/wordmem-translation-availability-dd`
- Raw 20-minute log: 165,533 lines / 83,442,513 bytes; intentionally not committed. `logs/translation-availability-diagnostics-excerpt.txt` retains the bounded WordMem Translation diagnostics.

## Commands and exits

```sh
# 0; logs/xcodebuild-translation-availability-build.log
xcodebuild -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /private/tmp/wordmem-translation-availability-dd build

# 0
xcrun simctl install 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 /private/tmp/wordmem-translation-availability-dd/Build/Products/Debug-iphonesimulator/WordMem.app

# 0
xcrun simctl launch 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 com.zhezhe.wordmem

# 0 for each t00-t14 screenshot
xcrun simctl io 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 screenshot docs/evidence/import-pipeline-simulator/screenshots/<name>.png

# 0; 165533-line raw capture was reduced before commit
xcrun simctl spawn 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 log show --style compact --last 20m --predicate 'process == "WordMem" OR eventMessage CONTAINS[c] "translation" OR eventMessage CONTAINS[c] "LanguageAvailability" OR eventMessage CONTAINS[c] "TranslationSession"' > /tmp/translation-availability-system-log.txt

# 0; 26 tests / 0 failures; logs/xcodebuild-translation-mapping-tests.log
xcodebuild -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /private/tmp/wordmem-translation-availability-dd -only-testing:WordMemTests/DocumentTranslationEngineTests -only-testing:WordMemTests/DocumentImportReviewModelTests test

# 0
xcrun simctl appinfo 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 com.zhezhe.wordmem

# 0
xcrun simctl list devices | grep '987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0'
```

UI text entry used XcodeBuildMCP `type_text` (US-keyboard-only). One non-English probe used ASCII Polish because AXe rejected CJK and the simulator paste/UI path was not used. Runtime snapshots, taps, drags, the grabber, 重试, 全选, and CTA interactions were driven by XcodeBuildMCP. The unsupported non-English chip-translation path opened a system overlay; the application review underneath was exposed by dragging the overlay downward with the MCP application drag action.

## Focused screenshots

| File | Observation |
|---|---|
| `t01-normal-en-unsupported-availability.png` | Medium sheet after English commit; app card reports unsupported |
| `t02-normal-en-review-unsupported.png` | Large review with fallback card, retry, and English chips |
| `t03-retry-translating.png` | Runtime 正在翻译… immediately after retry |
| `t04-retry-after-translation-failure.png` | System sheet says translation is unsupported on a simulated device |
| `t05-unsupported-nonenglish-system-overlay.png` | System overlay triggered while probing a non-English source |
| `t06-unsupported-nonenglish-app-copy.png` | App copy behind the dismissed overlay |
| `t07-unsupported-nonenglish-review.png` | Non-English review exposes unsupported and retry |
| `t08-very-short-text-unsupported.png` | `Hi.` retains one chip and unsupported fallback |
| `t09-short-text-retry-unsupported.png` | Short-text retry returns to actionable unsupported |
| `t10-rapid-edit-1-sun.png` | First rapid replacement has only its two current chips |
| `t11-rapid-edit-2-rain.png` | Second rapid replacement has only its two current chips |
| `t12-mixed-language-text-unsupported.png` | English/Polish mixed probe shows unsupported |
| `t13-normal-en-selected-ready.png` | 7/7 selected and enabled import CTA |
| `t14-normal-en-import-success-fallback.png` | Alert 已添加 5 个单词，已有 2 个单词。 |

## Diagnostic excerpt

`logs/translation-availability-diagnostics-excerpt.txt` contains:

- `LTLanguageStatus alloc task:8 engineType:0 dedicated:YES`
- `LTLanguageStatus alloc task:8 engineType:2 dedicated:YES`
- `translation_api:AllEngines:no-progress` with every engine marked `🔴...---`
- `Delegate says translation isn't supported on the current device`
- `Preflight checks showed translation isn't supported on the current device`
- `TranslationErrorDomain Code=11` with source/target locales

No `LanguageAvailability` token appeared in the filtered log. The public SDK call itself does not emit that literal label; the Translation framework diagnostics above are the available availability evidence.
