# Import Review Quality QA — 2026-11-09

## Result

**PASS — the branch is safe to proceed to TestFlight review**, subject to the
normal TestFlight device validation of translation and Apple Intelligence
availability that a simulator cannot prove.

The inspected implementation commit is
`463043afe5697279be7641fb12567b05f53efb7e` on `fix/import-review-quality`.
QA added focused regression tests and this evidence document only; no
production code was changed by QA.

## Requirement results

| Requirement | Result | Evidence |
| --- | --- | --- |
| Text review shows structured title, heading, list, code, and table projection | PASS | `CanonicalReviewProjection` uses explicit semantic formatting; `testTextProjectionRendersCanonicalStructureWithoutClaimingStorageFormat` and the table-row regression assert the exact projection and no duplicated cells. |
| Text review can return to editable source | PASS | `testEditingOriginalClearsDerivedReviewAndReturnsToEditableCapture` proves review-derived state clears and the model returns to `capturing`; `TextImportView` then renders its editable source card while retaining the user's draft. |
| Image display, translation, and candidate extraction use the sanitized canonical review projection | PASS | `ImageImportView` derives one projection and passes it to `prepareImageDocument`; the regression checks `reviewDocument`, `documentSession.document`, and candidate source text all equal the sanitized review while `originalImageDocument` keeps the raw canonical document. |
| Obvious image chrome is removed | PASS | Clock-only, percent/status, URL-only, short top-region non-title, and Wi-Fi fixtures are removed while meaningful paragraphs remain. A short top-region title (`Chapter 1`) remains. |
| Function words, pronouns, single letters, and domain fragments cannot become selectable chips or receive chip translation | PASS | `ImportHighValueCandidateFilter` runs before advisor/chip creation and chip translation requests are derived from that filtered model. Regression checks forbidden-only input yields no chips, no translation map, and no translation configuration; meaningful words remain in the mixed-input case. |
| Original canonical evidence and save submission compatibility remain intact | PASS | Sanitization returns a new document without mutating input; deterministic evidence and image payload remain. The existing save payload test asserts unchanged text, normalized key, source order, original word/key, and lemma metadata fields. |

## Commands and exit codes

All commands ran from the repository root with Xcode destination
`platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`.

1. `xcrun swift-format lint --strict <all changed Swift files>` — exit 0.
2. `xcodebuild test -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /tmp/WordMemQA-Derived` — exit 0 on the implementation HEAD; 80 tests, 0 failures.
3. The same `xcodebuild test` command after QA test additions — exit 0; 83 tests, 0 failures. A second consecutive post-addition run also exited 0 with 83 tests and 0 failures.
4. `xcodebuild build -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /tmp/WordMemQA-Debug CODE_SIGNING_ALLOWED=NO` — exit 0.
5. `xcodebuild build -project WordMem.xcodeproj -scheme WordMem -configuration Release -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0' -derivedDataPath /tmp/WordMemQA-Release CODE_SIGNING_ALLOWED=NO` — exit 0.

## Defects found during QA

No blocking defects remain. The simulator build and deterministic tests verify
the review-quality fixes; live translation downloads, installed-device
translation behavior, and Apple Intelligence availability still require the
normal TestFlight device pass.
