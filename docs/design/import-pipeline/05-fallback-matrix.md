# Import Fallback Matrix

Status: active
Date: 2026-11-15
Related issue: [#22 翻译流程 bug 修复](https://github.com/zhezhe-star/WordMem/issues/22)
Related retrospective:
`docs/superpowers/reports/2026-11-12-apple-intelligence-import-retrospective.md`

This document is the release contract for optional enrichment in the import
pipeline. Any new AI, translation, or dictionary capability must add a row here
before it can gate the import flow.

## Core rule

The deterministic import path must remain usable without any optional
capability. Optional capabilities may only remove low-value candidates; they
must never be the only way to produce candidates or save words.

Translation is the one deliberate exception: a **retryable** translation
failure no longer offers a "save without Chinese" bypass. The user must retry
successfully or cancel the import. An unsupported language pair is the only
non-retryable translation terminal state and still allows saving.

## Matrix

| Capability | Failure mode | User-visible fallback | Must not happen | Evidence |
| --- | --- | --- | --- | --- |
| Foundation Models candidate curation | unavailable, timeout, error, empty result | Use the deterministic candidate set: tokenizer + function-word/short-fragment filter + Apple Dictionary gate | Blank review screen; `.curatorUnavailable` without candidates; model-invented words | `testSimulatorFoundationModelFailureFallsBackToDeterministicChips`, `testCuratorFailureFallsBackToDeterministicFunctionWordFilter` |
| Foundation Models recommendation quality | model recommends function words or out-of-set IDs | Baseline filter removes function words/short fragments; unknown IDs are discarded | Function words become selectable; model introduces new candidates | `testCuratorCannotIntroduceFunctionWordsOutsideDeterministicBaseline`, `testValidatesOnlyRecommendedIDsFromFoundationModels` |
| Translation session preparation | language assets not installed, Apple Intelligence model not ready, transient runtime failure | Call `prepareTranslation()` before every run; auto-start when availability is `.needsLanguageDownload`; retry once with `.lowLatency`; only then present one alert | First attempt fails and requires the user to manually retry; two translation sessions run concurrently | `testHandlePreparesSessionThenTranslatesDocumentAndChipsInOneTask`, `testPrepareFailureMapsToDownloadStateWithoutRetryingTranslation` |
| High-fidelity document translation | strategy unavailable or runtime failure | Retry once with `.lowLatency`; if that fails, present the single failure alert with retry/cancel; chip translation still runs in the same session | Document failure suppresses chip translation; inline retry buttons | `testDocumentFailureStillTranslatesChipsAndPublishesReport`, `testTranslationFailurePresentsSingleRetryableAlert` |
| Translation availability | unsupported pair, language pack missing | Missing pack auto-starts `prepareTranslation()` (system download prompt); unsupported pair shows “需要下载翻译语言” with the Settings path (“设置 > App > 翻译 > 语言”), retry/cancel | Generic “暂不支持翻译” with no actionable path | `testUnsupportedPairPromptsLanguageDownloadAndRetry`, `testPrepareFailureMapsToDownloadStateWithoutRetryingTranslation` |
| Chip translation | unavailable or partial failure | Same session as the document; on final failure show “部分单词释义暂不可用” alert with retry/cancel; retry only requests missing chips | Silent `try?`; saving without meanings; a second translation session | `testChipFailureRetriesWithoutRedoingCompletedDocument`, `testChipOnlyFailurePresentsPartialMeaningAlert`, `testRetryAfterFinalChipFailureOnlyRequestsMissingChips` |
| Apple Dictionary | word unavailable | Hide unoffered chips; keep import flow usable | Unavailable word enters submission | `ImportCandidateChip.isImportable` + existing repository tests |
| Vision document reader | invalid image or no text | Alert with “重新选择 / 取消”; restore capture state | Technical OCR error copy; stuck processing; inline retry button | `testFailedImageProcessingRestoresCapturingState`, `testImageProcessingFailureUsesReselectAlert` |
| Candidate preparation | slow or unavailable | Keep the editor usable; show inline progress; never auto-close the sheet | Spinner-only blank page; swipe-to-dismiss during processing | `testTranslationAvailabilityDoesNotBlockCandidateChips` |
| Saving | persistence failure | Alert with “重试 / 取消”; retry resubmits the same selection | Silent failure; inline retry button | `testSaveFailureUsesRetryableAlert`, `testSavingLifecycleShowsConciseFailureAndRecovers` |

## Interaction contract

- Dismissing the keyboard starts preparation. It is a preview, not a save.
- Preparation never closes the sheet and never writes to the wordbook.
- The only save action is the existing `导入 N 个单词` button.
- No new primary button may be added when an existing gesture or CTA can do the
  same job.
- All terminal errors use one system alert at the review-screen root. Modules
  do not render their own retry buttons.
- The alert's retry action restarts the whole failed step: translation retry
  covers document + all missing chip meanings; save retry resubmits the same
  selection.
- Cancel paths return to the pre-import state: text import → editor with draft;
  image import → selected image + recognized text preview; Translation
  Provider → exit component; Share Extension → close extension.
- A terminal state must render visible copy and at least one actionable next
  step (the alert).

## Definition of done for a new enrichment

1. Add a row to this matrix.
2. Add a deterministic fallback path.
3. Add a test for success, failure, and fallback.
4. Add a view-level regression test for any new terminal state.
5. Verify the import flow still completes with the enrichment disabled.
6. Verify the Release build for the app and both extensions.
7. Run a real-device check when the capability depends on Apple Intelligence or
   installed language assets.
