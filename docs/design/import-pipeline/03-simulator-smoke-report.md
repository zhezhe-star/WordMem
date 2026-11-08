# Import Pipeline Simulator Smoke Report

- Consolidation date: 2026-11-08
- Evidence inspected at: commit `eaf54f2` (`test(import): add simulator translation fallback evidence`)
- Branch: `feature/import-document-pipeline`
- Simulator: iPhone Duo Test, UDID `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`, iOS 27.1
- Evidence reviewed: all 63 pre-consolidation files under `docs/evidence/import-pipeline-simulator/`

## Overall simulator smoke decision

**PARTIAL — not a release-ready device substitute.** The app, Share Extension, Translation Provider invocation, and unsupported-translation fallback paths were exercised successfully. Release evidence remains PARTIAL because image OCR duplicated list and table content, Translation Provider save/queue could not be driven, and the simulator cannot provide installed translation assets, completed translation, or Apple Intelligence model validation. Simulator fallback results must not be read as proof that translation works on hardware.

## Consolidation verification gate

```sh
xcodebuild test -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

The test exited `0` with `** TEST SUCCEEDED **`, 71 tests, and 0 failures. A separate signing-exempt Debug build also exited `0`:

```sh
xcodebuild -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /private/tmp/wordmem-consolidation-signing-exempt-dd CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
```

It ended with `** BUILD SUCCEEDED **`. Bounded evidence: [verification excerpt](../../evidence/import-pipeline-simulator/logs/xcodebuild-consolidation-verification-excerpt.txt).

## Simulator flow coverage

| Original release-checklist flow | Simulator status | Evidence | Interpretation |
|---|---|---|---|
| Text import and unsupported-translation fallback | PASS (simulator scope) | [initial fallback](../../evidence/import-pipeline-simulator/screenshots/00-text-import-initial-unsupported-translation.png), [wordbook](../../evidence/import-pipeline-simulator/screenshots/06-text-wordbook-visible.png), [translation log](../../evidence/import-pipeline-simulator/logs/translation-fallback-excerpt.txt) | Structured text review, chips, CTA, save, wordbook, actionable fallback, and retry all worked. Completed translation is not claimed. |
| Image import and unsupported-translation fallback | PARTIAL | [picker and review screenshots](../../evidence/import-pipeline-simulator/screenshots/09-image-photo-picker.jpg), [duplicate OCR runtime value](../../evidence/import-pipeline-simulator/logs/image-ocr-runtime-value.txt) | Picker, OCR, review, chips, CTA, and save worked, but OCR visibly duplicated both list entries and both table cells. This display defect must be addressed and revalidated before release. |
| Share Extension end-to-end | PASS (simulator scope) | [extension opened](../../evidence/import-pipeline-simulator/screenshots/03-share-extension-opened.png), [fallback](../../evidence/import-pipeline-simulator/screenshots/05-share-extension-translation-fallback.png), [saved word](../../evidence/import-pipeline-simulator/screenshots/07-wordmem-after-share-save.png), [extension log](../../evidence/import-pipeline-simulator/logs/extension-smoke-log-excerpt.txt) | Share sheet, extraction, unsupported fallback, manual meaning, save, and WordMem wordbook confirmation worked. |
| Translation Provider invocation and card render | PASS (simulator scope) | [provider invoked](../../evidence/import-pipeline-simulator/screenshots/08-translation-provider-invoked.png), [card/chips](../../evidence/import-pipeline-simulator/screenshots/09-translation-provider-wordmem-card.png), [process log](../../evidence/import-pipeline-simulator/logs/extension-process-excerpt.txt) | ExtensionKit launched the provider and rendered the source card/chips. |
| Translation Provider save/queue | BLOCKED (automation) | [save disabled](../../evidence/import-pipeline-simulator/screenshots/11-translation-provider-save-disabled.png), [extension log](../../evidence/import-pipeline-simulator/logs/extension-smoke-log-excerpt.txt) | AXe and MCP taps did not toggle chips in the hosted scene; save stayed at 0 and disabled. Native save/queue needs hardware or an instrumented host. |
| Translation output and model availability | BLOCKED (platform) | [AI empty / all engines unavailable](../../evidence/import-pipeline-simulator/logs/translation-availability-diagnostics-excerpt.txt), [mapping tests](../../evidence/import-pipeline-simulator/logs/xcodebuild-translation-mapping-tests.log) | Every observed translation engine was unavailable and `translation_api:AI:no-progress` was empty. Unit mappings pass, but runtime translation and Apple Intelligence were not validated. |

## Original physical-device checklist reconciliation

| Original residual checklist item | Consolidated status | Evidence | Why the simulator is insufficient |
|---|---|---:|---|
| Confirm en→zh-Hans is installed or supported-not-installed through real `LanguageAvailability` on an Apple Intelligence-capable iPhone | BLOCKED | [diagnostics](../../evidence/import-pipeline-simulator/logs/translation-availability-diagnostics-excerpt.txt), [mapping tests](../../evidence/import-pipeline-simulator/logs/xcodebuild-translation-mapping-tests.log) | The simulator returned unsupported for the pairing and never exposed `supportedNotInstalled`; mapping code has unit coverage only. |
| Exercise needs-download, start/complete resource download, and verify the system sheet does not block the app card | PARTIAL | [retry](../../evidence/import-pipeline-simulator/screenshots/t03-retry-translating.png), [system unsupported sheet](../../evidence/import-pipeline-simulator/screenshots/t04-retry-after-translation-failure.png), [mapping tests](../../evidence/import-pipeline-simulator/logs/xcodebuild-translation-mapping-tests.log) | Download-state copy has unit coverage, and the simulator exposed an overlay-blocking interaction risk, but no real downloadable/completed resource exists. |
| Verify completed document output, block/span preservation, persisted phrase translation, and completed card | PARTIAL | [import success / fallback](../../evidence/import-pipeline-simulator/screenshots/t14-normal-en-import-success-fallback.png), [71-test gate](../../evidence/import-pipeline-simulator/logs/xcodebuild-consolidation-verification-excerpt.txt) | Unit tests cover translation-unit child selection and span structure, and import remained usable, but actual completed translation output and persistence require hardware assets. |
| Repeat CJK/Chinese/Japanese and true mixed CJK/Latin probes; verify detection and chip behavior | PARTIAL | [non-English overlay](../../evidence/import-pipeline-simulator/screenshots/t05-unsupported-nonenglish-system-overlay.png), [app fallback](../../evidence/import-pipeline-simulator/screenshots/t07-unsupported-nonenglish-review.png), [mixed probe](../../evidence/import-pipeline-simulator/screenshots/t12-mixed-language-text-unsupported.png) | ASCII Polish exercised unsupported copy, but CJK entry was blocked and mixed-language routing was not truly tested. |
| Exercise short text, rapid edits, cancellation/staleness, and retry after real interruption/session failure | PARTIAL | [short text](../../evidence/import-pipeline-simulator/screenshots/t08-very-short-text-unsupported.png), [rapid edits](../../evidence/import-pipeline-simulator/screenshots/t10-rapid-edit-1-sun.png), [diagnostics](../../evidence/import-pipeline-simulator/logs/translation-availability-diagnostics-excerpt.txt) | Short text, edits, and retry were stable, but cancellation and recovery under installed translation assets cannot occur on simulator. |
| Confirm unsupported/failed import stays nonblocking, copy is actionable, retry is not duplicated | PARTIAL | [selection ready](../../evidence/import-pipeline-simulator/screenshots/t13-normal-en-selected-ready.png), [import success](../../evidence/import-pipeline-simulator/screenshots/t14-normal-en-import-success-fallback.png), [overlay risk](../../evidence/import-pipeline-simulator/screenshots/t05-unsupported-nonenglish-system-overlay.png) | Import remained usable and candidates did not visibly duplicate, but the non-English chip path first showed a blocking system sheet and a recoverable session-failure runtime was not available. |
| Capture installed/downloadable/unsupported/failure transitions and confirm no production diagnostics were added | PARTIAL | [initial fallback](../../evidence/import-pipeline-simulator/logs/translation-fallback-excerpt.txt), [focused diagnostics](../../evidence/import-pipeline-simulator/logs/translation-availability-diagnostics-excerpt.txt), [extension log](../../evidence/import-pipeline-simulator/logs/extension-smoke-log-excerpt.txt) | Unsupported and engine-absence transitions were captured; installed, downloadable, completed, and real-failure transitions were not. |

## Physical release requirement

Before production release, run the image/text/Share Extension/Translation Provider matrix on **both** an Apple Intelligence-capable, translation-supported iPhone and a fallback iPhone. The simulator cannot satisfy this because it lacks qualifying Apple Intelligence hardware/model provisioning and installed Translation assets; it explicitly reported translation unsupported and had no AI engines. Hardware coverage must validate real availability/download states, completed translation output and persistence, native extension touch/save behavior, CJK and true mixed-language routing, interruption recovery, and both supported/fallback UI behavior.

## Reconciliation decisions

- App-level and focused-translation duplicate en→zh-Hans observations were collapsed into the two matrices above.
- “Smoke complete” was removed as an overall release claim; OCR display duplication makes the combined result PARTIAL.
- Image save reporting “已添加 0 个” is a result of reusing two words already created by text import, not a save failure.
- Share Extension save success is not generalized to Translation Provider save/queue.
- Apple Intelligence remains unvalidated: WordMem did not expose a model-availability control and the simulator exposed no AI engines.
- Raw oversized logs were intentionally excluded; their bounded excerpts remain the durable evidence.

## Evidence index

- Primary manifests: [evidence manifest](../../evidence/import-pipeline-simulator/evidence-manifest.md) and [translation-availability manifest](../../evidence/import-pipeline-simulator/translation-availability-manifest.md)
- App smoke screenshots: `screenshots/00-text-import-initial-unsupported-translation.png` through `14-image-save-success-alert-existing.png`
- Focused fallback screenshots: `screenshots/t00-app-launch.png` through `t14-normal-en-import-success-fallback.png`
- Extension screenshots: `screenshots/00-context-menu-translate-available.png` through `11-translation-provider-save-disabled.png`
- Consolidation verification excerpt: [xcodebuild-consolidation-verification-excerpt.txt](../../evidence/import-pipeline-simulator/logs/xcodebuild-consolidation-verification-excerpt.txt)
- Translation diagnostics: `logs/translation-fallback-excerpt.txt`, `logs/translation-availability-diagnostics-excerpt.txt`
- Extension process and smoke logs: `logs/extension-process-excerpt.txt`, `logs/extension-smoke-log-excerpt.txt`
- OCR defect value: `logs/image-ocr-runtime-value.txt`
