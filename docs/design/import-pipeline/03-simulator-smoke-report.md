# Import Pipeline Simulator Smoke Report

- Date: 2026-11-08
- Repository commit: `274d9bb6f8d7df164632e26a8e4b7dc219c7d703`
- Branch: `feature/import-document-pipeline`
- Simulator: iPhone Duo Test, UDID `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`, iOS 27.1, booted
- App: `com.zhezhe.wordmem`, version `0.1.0`, build `1`, Debug
- Result: overall smoke-complete with one import-display issue and translation/runtime limitations

## Scope and limitations

This was a simulator-only app-level smoke run. Translation assets were unavailable and the system translation sheet explicitly reported that translation is unsupported on the simulated device. Apple Intelligence model availability was not independently exposed by WordMem's UI and was not validated; therefore this evidence does **not** constitute Apple Intelligence hardware validation and does **not** replace the physical-device Apple Intelligence/translation release checklist item.

The text was entered by placing it on the simulator pasteboard with `xcrun simctl pbcopy` and sending Cmd+V through AXe because AXe direct typing does not support multiline input. Photo-library limited access was shown by the system photo picker; the fixture image was visible and selectable without changing permissions.

## Command and exit-code evidence

| Step | Command | Exit |
|---|---:|---:|
| Build | `xcodebuild -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /private/tmp/wordmem-smoke-dd-274d9bb build` | 0 |
| Install | `xcrun simctl install 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 /private/tmp/wordmem-smoke-dd-274d9bb/Build/Products/Debug-iphonesimulator/WordMem.app` | 0 |
| Launch | `xcrun simctl launch 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 com.zhezhe.wordmem` | 0 |
| Paste text | `printf '%s' '<test article>' | xcrun simctl pbcopy 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`; `axe key-combo --modifiers 227 --key 25 --udid 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0` | 0 / 0 |
| Add image | `xcrun simctl addmedia 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 docs/evidence/import-pipeline-simulator/screenshots/deterministic-image-import-fixture.png` | 0 |
| Log capture | `xcrun simctl spawn 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 log show --style compact --last 45m --predicate 'process == "WordMem" OR eventMessage CONTAINS[c] "translation" OR eventMessage CONTAINS[c] "LanguageModel"'` | 0 |
| App info | `xcrun simctl appinfo 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 com.zhezhe.wordmem` | 0 |

UI interactions used XcodeBuildMCP runtime snapshots/taps and its bundled AXe for coordinates, Cmd+V, and manual dismissal of the system translation sheet. The full build log, concise translation fallback excerpt, full 45-minute filtered simulator log, and app info are under `docs/evidence/import-pipeline-simulator/logs/`.

## Text import checks

| Check | Status | Evidence / observation |
|---|---|---|
| Open text import | PASS | Wordbook `+` → 导入单词 → 文本导入. |
| Enter structured article | PASS | Pasted heading, paragraph, two-item list, fenced code block, and normal paragraph. Full text is retained by the runtime text field. |
| Keyboard dismissal with 完成 | PASS | 完成 removed keyboard entry focus. The optional document translation sheet then appeared and was dismissed. |
| One simple import screen | PASS | One review screen contains source, translation card, status, chips, and one CTA; the translation UI is a temporary system overlay during availability check. |
| Semantic status only | PASS | UI shows “当前设备暂不支持这对语言的翻译。” and 重试; no canonical IDs or technical pipeline rows. |
| Translation card state | PASS (fallback) | The expected unsupported fallback card and retry control are shown; translation output is unavailable on simulator. |
| Chips selectable | PASS | `morning` and `study` selected; count changed from 0/28 to 2/28. |
| Sheet medium/large resizing | PASS | Medium: `07-text-sheet-medium.png`; large after grabber drag: `02-text-review-large-unsupported-translation.png`. |
| Selected-count CTA | PASS | CTA became enabled as “导入 2 个单词”. |
| Save success alert | PASS | Alert: “已添加 2 个单词，已有 0 个单词。” |
| Words visible in wordbook | PASS | `study` and `morning` rows visible with EN, phonetics, 待学习, and 暂无本地翻译. |

## Image import checks

The deterministic fixture is committed at `screenshots/deterministic-image-import-fixture.png`; its generator is `make-image-fixture.py`. It contains a visible title, paragraph, two-item list, and bordered 2x2 table.

| Check | Status | Evidence / observation |
|---|---|---|
| Create deterministic image | PASS | Generator exit 0; PNG is 1200x1600 and committed. |
| Add to Photos | PASS | `simctl addmedia` exit 0; fixture appears first in picker (`09-image-photo-picker.jpg`). |
| Exercise photo picker | PASS | Fixture selected; OCR began and review appeared. |
| Recognized expected content | PARTIAL | Title, paragraph, list, and table text were recognized, but the visible 图片原文 runtime value duplicates both list entries and both table cells. Exact value: `logs/image-ocr-runtime-value.txt`; screenshot `11-image-review-large-duplicate-source.png`. |
| Candidate selection | PASS | Count changed from 0/23 to 2/23 by selecting `morning` and `study`. |
| Image save | PASS | Save completed with alert “已添加 0 个单词，已有 2 个单词。” because the selected words already existed from text import; no error occurred. |
| No duplicate container/cell translation text | PARTIAL | No translated text was visible because translation is unsupported on simulator, so translated-card duplication cannot be checked. Independently, the raw recognized display already duplicates list/table container and cell text, which should not be considered release-ready. |

## Translation / model fallback

- WordMem UI fallback: **PASS captured** — unsupported language pair on this simulator, with retry shown.
- System translation sheet: **PASS captured** — “翻译”在模拟设备上不受支持。若要测试此功能，请在真实设备上运行代码。
- System log excerpt: `translation_api:AllEngines:no-progress` and `progress` list every language engine with `🔴...---`, and `TranslationAPISupportExtension` is present. This supports “translation assets/model unavailable/unsupported” rather than “installed.”
- Apple Intelligence model availability: **BLOCKED / not determinable from this app flow** — WordMem does not expose an Apple Intelligence availability control, and the smoke evidence covers only the system Translation API. No Apple Intelligence hardware validation is claimed.

## Evidence index

- `00-text-import-initial-unsupported-translation.png`: text import sheet and inline unsupported translation card.
- `01-text-translation-system-sheet-unsupported.png`: system translation sheet fallback.
- `02-text-review-large-unsupported-translation.png`: large text review, structured source, fallback card.
- `03-text-candidate-chips-unselected.png`: 28 candidate chips, selected 0/28.
- `04-text-two-chips-selected-cta-enabled.png`: selected 2/28 and enabled “导入 2 个单词”.
- `05-text-save-success-alert.png`: “已添加 2 个单词，已有 0 个单词。”.
- `06-text-wordbook-visible.png`: saved words in the wordbook.
- `07-text-sheet-medium.png`: medium text sheet.
- `08-image-import-source-medium.png`: image source sheet with album/camera actions.
- `09-image-photo-picker.jpg`: photo picker showing the deterministic fixture.
- `10-image-translation-system-sheet-unsupported.png`: image-flow translation fallback.
- `11-image-review-large-duplicate-source.png`: large image review with duplicated list/table source text.
- `12-image-candidate-chips-unselected.png`: 23 image-derived candidate chips.
- `13-image-two-chips-selected-cta-enabled.png`: selected 2/23 and enabled image-import CTA.
- `14-image-save-success-alert-existing.png`: image save alert with two existing words.
- `deterministic-image-import-fixture.png`: source fixture with title, paragraph, two-item list, and 2x2 table.
- `docs/evidence/import-pipeline-simulator/logs/xcodebuild-build.log`: incremental build log and exit 0.
- `docs/evidence/import-pipeline-simulator/logs/appinfo.txt`: installed bundle/version/build.
- `docs/evidence/import-pipeline-simulator/logs/translation-fallback-excerpt.txt`: concise translation fallback evidence.
- `docs/evidence/import-pipeline-simulator/logs/simulator-log-45m.txt`: full filtered simulator log.
- `docs/evidence/import-pipeline-simulator/logs/image-ocr-runtime-value.txt`: exact OCR display value showing list/table duplication.

