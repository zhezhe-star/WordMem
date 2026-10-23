# Canonical Word Identity Clean Reset — Verification Report

## Outcome

Implemented the 2026-10-23 canonical clean-reset plan in the dedicated `canonical-clean-reset` worktree. The app now persists `locale + normalizedKey`, repository-captured advisor identities are revalidated against Apple's system dictionary, OCR is cleaned before any downstream use, and content-bearing dictionary or migration paths are absent. All plan tasks are marked complete.

## Key changed / removed files

- Added native reset and boundary: `WordMem/Domain/WordMemStore.swift`, `WordMem/Import/OCRTextSanitizer.swift`, `WordMemTests/CanonicalCleanResetTests.swift`.
- Rebuilt identity/store: `WordEntry.swift`, `WordImportModels.swift`, `DictionaryModels.swift`, `WordImportSubmission.swift`, `WordInputNormalizer.swift`, `WordMemApp.swift`.
- Rebuilt capture/repository: `WordbookRepository.swift`, `SystemDictionaryLookupService.swift`, `ImportCandidateModels.swift`, `LocalStorageManager.swift`.
- Cleaned UI/learning/share: `ContentView.swift`, `SystemDictionaryView.swift`, `AddWordView.swift`, `ImageImportView.swift`, `TextImportView.swift`, Calendar service/views/flow, `ShareViewController.swift`.
- Removed compatibility paths: `WordMemMigrationPlan.swift`, `LegacyWordbookMigrator.swift`, bundled lookup and seed test doubles, all obsolete migration/repository/import test files, and exploration-era `WordData` persistence model (the tokenizer remains).
- Updated architecture/plan: `docs/local-first-architecture.md`, plan checkbox statuses.

## Destructive reset behavior

`WordMemStore` creates `Application Support/WordMem/wordmem-v3.store`. On first v3 launch it deletes incompatible SQLite `.store`, `.store-shm`, and `.store-wal` files in the app-owned store directories and removes historical queue/word defaults and migration/backfill markers. It records one reset-completed marker; later launches preserve v3 records. Nothing is read, migrated, aliased, or backed forward.

## Test and build evidence

- Red-first evidence: `/tmp/canonical-red.log` failed compilation because `WordMemStore`, `WordIdentity`, `SystemDictionaryAuthorizing`, and `OCRTextSanitizer` were absent.
- Final focused suite: `CanonicalCleanResetTests` — 11 tests, 0 failures.
- Full suite run A: `TEST SUCCEEDED`; 11 tests, 0 failures (`/tmp/full-suite-run-A.log`).
- Full suite run B: `TEST SUCCEEDED`; 11 tests, 0 failures (`/tmp/full-suite-run-B.log`).
- Release build: `generic/platform=iOS Simulator`, Release, signing-disabled flags, `BUILD SUCCEEDED` (`/tmp/release-build.log`).
- Acceptance grep returned no `ECDICT|LegacyA0|legacyExample|LegacyWordbook|WordMemMigrationPlan|BundledDictionaryLookupService|本地词典` runtime matches.
- No deprecated repository API or compatibility-only `add`/batch API remains.

## Residual risks

- The repository logic is covered by deterministic authorizer tests, but no simulator UI automation was run; the Apple dictionary sheet and accessibility flow should get one human smoke check.
- Live Apple dictionary availability varies by installed dictionaries and simulator state, so manual acceptance of `deliberately` must use a simulator with English dictionary assets.
- The one-time reset is intentionally destructive; existing exploration-era words and queued imports are unrecoverable by design.
