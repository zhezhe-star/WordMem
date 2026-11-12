# Import Fallback Matrix

Status: active
Date: 2026-11-12
Related retrospective:
`docs/superpowers/reports/2026-11-12-apple-intelligence-import-retrospective.md`

This document is the release contract for optional enrichment in the import
pipeline. Any new AI, translation, or dictionary capability must add a row here
before it can gate the import flow.

## Core rule

The deterministic import path must remain usable without any optional
capability. Optional capabilities may only remove low-value candidates; they
must never be the only way to produce candidates or save words.

## Matrix

| Capability | Failure mode | User-visible fallback | Must not happen | Evidence |
| --- | --- | --- | --- | --- |
| Foundation Models candidate curation | unavailable, timeout, error, empty result | Use the deterministic candidate set: tokenizer + function-word/short-fragment filter + Apple Dictionary gate | Blank review screen; `.curatorUnavailable` without candidates; model-invented words | `testSimulatorFoundationModelFailureFallsBackToDeterministicChips`, `testCuratorFailureFallsBackToDeterministicFunctionWordFilter` |
| Foundation Models recommendation quality | model recommends function words or out-of-set IDs | Baseline filter removes function words/short fragments; unknown IDs are discarded | Function words become selectable; model introduces new candidates | `testCuratorCannotIntroduceFunctionWordsOutsideDeterministicBaseline`, `testValidatesOnlyRecommendedIDsFromFoundationModels` |
| High-fidelity document translation | strategy unavailable or runtime failure | Retry once with `.lowLatency`; if that fails, show an actionable translation card and keep words usable | Translation failure blocks chips or save | `testRetrySucceedsAfterInternalFailureAndInvalidateResetsLifecycle`, `testRepeatedTranslationFailureStopsAfterLegacyFallback` |
| Translation availability | unsupported pair, language pack missing | Show `当前设备暂不支持这对语言的翻译` or `需要下载翻译资源` with retry; keep chips and import CTA | Full-screen blank state; blocking alert | `testDocumentTranslationFailureKeepsWordsSelectable` |
| Chip translation | unavailable or partial failure | Show `暂无翻译` per chip; selection and save continue | Chip translation blocks selection | `testDocumentTranslationFailureKeepsWordsSelectable` |
| Apple Dictionary | word unavailable | Hide unoffered chips; keep import flow usable | Unavailable word enters submission | `ImportCandidateChip.isImportable` + existing repository tests |
| Vision document reader | invalid image or no text | Show actionable image error; restore capture state | Technical OCR error copy; stuck processing | `testFailedImageProcessingRestoresCapturingState` |
| Candidate preparation | slow or unavailable | Keep the editor usable; show inline progress; never auto-close the sheet | Spinner-only blank page; swipe-to-dismiss during processing | `testTranslationAvailabilityDoesNotBlockCandidateChips` |

## Interaction contract

- Dismissing the keyboard starts preparation. It is a preview, not a save.
- Preparation never closes the sheet and never writes to the wordbook.
- The only save action is the existing `导入 N 个单词` button.
- No new primary button may be added when an existing gesture or CTA can do the
  same job.
- A terminal state must render visible copy, an icon or skeleton where useful,
  and at least one actionable next step.

## Definition of done for a new enrichment

1. Add a row to this matrix.
2. Add a deterministic fallback path.
3. Add a test for success, failure, and fallback.
4. Add a view-level regression test for any new terminal state.
5. Verify the import flow still completes with the enrichment disabled.
6. Verify the Release build for the app and both extensions.
7. Run a real-device check when the capability depends on Apple Intelligence or
   installed language assets.
