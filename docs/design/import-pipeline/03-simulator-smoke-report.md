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


## Extension smoke appendix (Share Extension + Translation Provider)

- Date: 2026-11-08 (same run window as the app smoke above)
- Branch: `feature/import-document-pipeline`
- Simulator: iPhone Duo Test, UDID `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`, iOS 27.1, booted (same device, fresh derivedDataPath `/private/tmp/wordmem-ext-smoke-dd`, so it did not contend with the app-smoke build)
- App: `com.zhezhe.wordmem` Debug build with embedded extensions
  - Share Extension bundle id: `com.zhezhe.wordmem.ShareExtension` (`PlugIns/WordMemShareExtension.appex`, `NSExtensionPointIdentifier=com.apple.share-services`)
  - Translation Provider bundle id: `com.zhezhe.wordmem.TranslationProvider` (ExtensionKit `Extensions/WordMemTranslationProvider.appex`)
- Host: Safari local page `file:///private/tmp/wordmem-ext-smoke-test.html` (English article with "morning" and "study")

### Result summary

| Flow | Status | Notes |
|---|---|---|
| Share Extension end-to-end | PASS | Share sheet → WordMem → source extracted → translation fallback with actionable message → manual meaning saved → word visible in WordMem wordbook. |
| Translation Provider invocation + card | PASS | System 翻译 action launched `com.zhezhe.wordmem.TranslationProvider`; its card rendered with source `morning` and the candidate chip grid. |
| Translation Provider save/queue | BLOCKED | Candidate chip selection could not be driven by the installed automation (AXe HID taps and XcodeBuildMCP taps did not toggle the chip inside the ExtensionKit-hosted scene); `保存 0 个` stayed disabled, so save/queue behavior is unverified. |
| Extension translation output | BLOCKED (platform) | System translation engines unavailable on simulator (`translation_api:AllEngines:no-progress`, all engines 🔴) for both extensions; matches the app-level smoke finding. |

### Share Extension step evidence

| Step | Command / interaction | Exit / result |
|---|---|---|
| Build full Debug app | `xcodebuild -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /private/tmp/wordmem-ext-smoke-dd build` | 0 (`logs/xcodebuild-ext-build.log`) |
| Install | `xcrun simctl install 987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0 /private/tmp/wordmem-ext-smoke-dd/Build/Products/Debug-iphonesimulator/WordMem.app` | 0 |
| Open test page | `xcrun simctl openurl … "file:///private/tmp/wordmem-ext-smoke-test.html"` | 0 |
| Select text | AXe touch down/up long-press at (55, 38) points over "morning" | 0, selection handles visible (`00-context-menu-translate-available.png`) |
| Open share sheet | Tap `共享…` in the Safari context menu | share sheet with WordMem tile (`02-share-sheet-wordmem-visible.png`) |
| Launch extension | AXe tap at WordMem tile (72, 437) points | extension UI opened (`03-share-extension-opened.png`, `04-share-extension-source-translating.png`) |
| Translation fallback | Automatic after system translation fails | “翻译不可用，请手动输入释义。” + 重新翻译 (`05-share-extension-translation-fallback.png`) |
| Enter manual meaning | `printf '%s' '早晨' \| xcrun simctl pbcopy …` + AXe Cmd+V into 中文释义 editor | 0 (`06-share-extension-manual-meaning-entered.png`) |
| Save | AXe tap 保存 (345, 48) points | extension closed back to Safari |
| Verify in WordMem | `xcrun simctl launch … com.zhezhe.wordmem` then screenshot | wordbook shows `morning` / `/mɔːrnɪŋ/` / 待学习 / 早晨 (`07-wordmem-after-share-save.png`) |

Process evidence: `WordMemShareExtension` launched as pid 74684 and the share sheet registered the `UISocialActivity` for `com.zhezhe.wordmem.ShareExtension` (`logs/shareextension-launch-excerpt.txt`, `logs/extension-launch-excerpt.txt`).

### Translation Provider step evidence

| Step | Command / interaction | Exit / result |
|---|---|---|
| Invoke provider | Safari context menu → 翻译 (AXe tap 179, 79 points) | `WordMemTranslationProvider` pid 77260 launched (`08-translation-provider-invoked.png`) |
| Card render | Automatic | `正在准备单词卡片…` startup, then 原句 `morning`, candidate chip `morning`, `保存 0 个` footer (`09-translation-provider-wordmem-card.png`, `10-translation-provider-wordpicker.png`, `11-translation-provider-save-disabled.png`) |
| Chip selection | AXe taps at (128, 379), (72, 379), (131, 403) points on the chip | all exit 0 but `保存 0 个` never changed and the chip stayed unselected — synthetic HID taps are not acted on by this ExtensionKit-hosted scene |
| Save/queue | Not reachable | `保存` stayed disabled at 0 selections; queue/save behavior unverified |

`logs/extension-process-excerpt.txt` shows the ExtensionKit bootstrap of `extension<com.zhezhe.wordmem.TranslationProvider>` pid 77260.

### Simulator coverage conclusion

Simulator coverage can replace the happy-path mechanical coverage of the Share Extension (sheet → extract → fallback → manual save → wordbook) on iOS 27.1, and it can prove that the Translation Provider process launches and renders its card from the system 翻译 action. It cannot replace physical-device smoke for: system translation output (translation engines are unavailable on simulator), Apple Intelligence availability, and ExtensionKit chip interaction fidelity — the TranslationProvider card ignored synthetic taps in this run, so save/queue coverage still needs a physical device or an instrumented UI test host.

Reduced log evidence: `docs/evidence/import-pipeline-simulator/logs/extension-smoke-log-excerpt.txt` (≤256 KB) keeps the timestamped Share Extension / TranslationProvider launch, card-scene, and engine-unavailability lines; the 112 MB raw 30-minute capture was intentionally not committed.
