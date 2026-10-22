# Issue 10 — Unified typed import submission evidence

## Result
- Implementation commit after evidence amendment: recorded in the final completion report.
- Base commit: `139615f merge: integrate default translation import with source-aware wordbook`.
- Final repository status: clean after commit.

## TDD evidence
- Red build command: `xcodebuild build-for-testing -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1'`.
- Red result: exit `65`, `TEST BUILD FAILED`; compiler found the intentionally missing `WordImportSubmission`, `WordImportCandidatePayload`, new `WordImportSource` cases, submission repository API, and submission migrator. Log retained at `/tmp/wordmem-red.log`.
- Focused suite final state: 8/8 `WordImportSubmissionTests` cases pass.

## Final verification
- Final test run 1: exact required command, `** TEST SUCCEEDED **`, `Executed 72 tests, with 0 failures (0 unexpected)`.
- Final test run 2, immediately after run 1: exact required command, `** TEST SUCCEEDED **`, `Executed 72 tests, with 0 failures (0 unexpected)`.
- Final Debug build: `xcodebuild -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1' build`, `** BUILD SUCCEEDED **`, exit 0.
- The Debug build dependency graph built both `WordMemShareExtension` and `WordMemTranslationProvider`; the final app validation embedded both `.appex` products.
- Additional post-format test-build: `build-for-testing` completed with `** TEST BUILD SUCCEEDED **` before the two final full test runs.

## Requirement disposition
1. Source identity: PASS. `default_app` raw value remains unchanged; `share_extension` and `translation_provider` were added; enum moved into `WordMem/Domain/WordImportSubmission.swift`, compiled by app, both extensions, and therefore tests; Chinese labels are 分享导入 and 翻译导入.
2. Submission model: PASS. Versioned schema 1, Codable, Sendable `WordImportSubmission` carries source, full source text, optional recognized text, selected candidate payloads, metadata, payload ID, schema version, and creation date. Candidate payload carries per-candidate translation, phonetic, example, note, metadata, payload ID, and normalized key. Snake-case compatibility fields are covered by decode/encode tests.
3. Extension queue: PASS. Share and translation provider now append complete `WordImportSubmission` batches under `pending_word_import_submissions.v1`; neither writes SwiftData. Existing editable fields and provider chips remain unchanged.
4. App migration: PASS. `WordImportSubmissionMigrator` runs in the existing `.task` lifecycle and on `UIApplication.didBecomeActiveNotification`. It imports one transactional submission at a time, records one `WordImportContext` per candidate, removes only processed IDs, leaves failed batches, and is idempotent. Legacy `saved_words` migration remains intact and tested.
5. Repository import: PASS. `importSubmission(_:using:)` accepts structured candidates, performs dictionary enrichment, applies user translation/phonetic/example without erasing canonical dictionary translation, writes note and payload metadata, preserves duplicate import history, and keeps `WordImportContext` as the sole import-context model.
6. Detail UX: PASS. Detail import history uses source display names/icons and now shows recognized text when distinct plus persisted user note; source and selected-word context remain visible.

## Files modified
- `WordMem.xcodeproj/project.pbxproj`
- `WordMem/ContentView.swift`
- `WordMem/Domain/WordImportModels.swift`
- `WordMem/Domain/WordImportSubmission.swift`
- `WordMem/LocalStorageManager.swift`
- `WordMem/Services/WordbookRepository.swift`
- `WordMemShareExtension/ShareViewController.swift`
- `WordMemTests/WordImportSubmissionTests.swift`
- `WordMemTranslationProvider/WordPickerView.swift`
