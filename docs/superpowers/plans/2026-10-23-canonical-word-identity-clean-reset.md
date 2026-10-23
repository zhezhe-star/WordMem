# Canonical Word Identity & Clean Store Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild WordMem around one native canonical word identity, system-dictionary-only content, cleaned OCR input, and a destructive fresh store reset that removes exploration-era compatibility code.

**Architecture:** `locale + canonicalKey` is the only word identity. User records contain user context and learning state; dictionary availability is checked dynamically and Apple's dictionary UI is opened for content. A fresh SwiftData v3 store discards all exploration data and no A0/ECDICT/UserDefaults migration paths remain.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, NaturalLanguage, UIKit `UITextChecker` / `UIReferenceLibraryViewController`, XCTest.

**Spec:** User-approved canonical identity design plus explicit cleanup instruction on 2026-10-23. Exploration-stage data may be destructively discarded.

## Global Constraints

- No bundled dictionary, ECDICT data, SQLite lookup, legacy migrator, A0 schema, or compatibility-only repository APIs.
- No aliases or compatibility keys in this reset; the fresh store starts empty.
- Canonical identity is `locale + normalizedKey`; current product locale is `en`.
- Candidates are only selectable when the final system dictionary check succeeds.
- Restored originals are also system-dictionary gated and unavailable originals cannot be restored.
- Phrase context is metadata/context, never a dictionary-gated word identity.
- OCR source text must be sanitized before display, persistence, splitting, or advisory lookup.
- Detail pages must not imply WordMem owns authoritative dictionary content.
- Existing user words and exploration-era imports may be deleted.
- Keep default candidate selection none.
- Public APIs only.
- Full suite must pass twice and signing-exempt Release must build.

---

### Task 1: Fresh Native SwiftData Store

**Files:**
- Modify: `WordMem/Domain/WordEntry.swift`
- Modify: `WordMem/Domain/WordImportModels.swift`
- Create: `WordMem/Domain/WordMemStore.swift`
- Delete: `WordMem/Domain/WordMemMigrationPlan.swift`
- Modify: `WordMem/WordMemApp.swift`

**Result:**
- `WordEntry` has only: `id`, `localeIdentifier`, `normalizedKey` unique within locale, `headword`, `originalText`, `systemDictionaryAvailable`, `userTranslation`, `userExample`, `userNote`, `createdAt`, `updatedAt`.
- No phonetic, translation, senses, forms, tags, dictionary ID/version, legacy examples, or lookup-content fields.
- `WordImportContext` retains source, cleaned source text, selected candidate, recognized text, image, submission identity, metadata, entry relationship.
- A fresh `WordMemStore` creates a v3 store URL and resets incompatible old files/UserDefaults marker once; no `SchemaMigrationPlan`.
- App uses this store explicitly.

**Tests:**
- Fresh container contains zero entries.
- Saving `en/give` twice creates one entry and one duplicate outcome.
- Different locale keys do not collide, even though current UI creates `en`.
- Legacy model types and migration plan symbols are absent.

### Task 2: Canonical Import and Repository Boundary

**Files:**
- Modify: `WordMem/Domain/WordInputNormalizer.swift`
- Modify: `WordMem/Domain/WordImportSubmission.swift`
- Modify: `WordMem/Domain/DictionaryModels.swift`
- Modify: `WordMem/Services/SystemDictionaryLookupService.swift`
- Modify: `WordMem/Services/WordbookRepository.swift`
- Delete: `WordMem/Services/LegacyWordbookMigrator.swift`
- Delete: `WordMemTests/BundledDictionaryLookupService.swift`
- Delete: `WordMemTests/DevelopmentSeedDictionaryCatalog.swift`

**Result:**
- Add `WordIdentity(locale:key:)` and a `SystemDictionaryAuthorizing` boundary.
- Candidate payloads preserve advisor-produced `normalizedKey`; repository must not silently recompute it from text.
- Repository revalidates every word candidate against system dictionary before save and skips unavailable candidates.
- Phrase context is stored only if explicitly selected; it is never represented as a word identity.
- Replace lookup-result service with availability authorizer + presentation helper.
- Remove deprecated `add`, batch compatibility API, content-bearing fallback, legacy queue defaults, old migrator, bundled test double, and seed catalog.
- Metadata records canonical key, original word, lemma/correction advice, and both dictionary checks without implying WordMem owns definitions.

**Tests:**
- `give/gave` resolves to canonical `give` when available.
- `recieve/receive` resolves to canonical `receive` when available.
- Unavailable corrected and unavailable restored candidates are skipped at repository boundary.
- Advisor key survives submission normalization.
- Phrase context remains separate from word canonical identity.
- Replay dedupe uses stable candidate IDs without text fallback.

### Task 3: OCR Sanitizer

**Files:**
- Create: `WordMem/Import/OCRTextSanitizer.swift`
- Modify: `WordMem/ImageImportView.swift`
- Test: `WordMemTests/WordImportTests.swift`

**Result:**
- Remove status-bar lines such as `12:32`, `:!... 5GA`, signal/battery-only lines, symbol-only lines, and numeric-only lines.
- Preserve normal English sentences and meaningful single-word lines.
- Sanitized output is used for displayed source, saved context, candidate splitting, and advisor context.
- If no clean text remains, image import reports no recognized text.

**Tests:**
- Given OCR lines from user screenshot, sanitizer returns the prose lines only.
- Sanitized text does not contain `12:32`, `5GA`, or standalone battery number.
- Candidate splitting on raw and sanitized output differs when garbage introduced fake tokens.

### Task 4: Clean Detail and Learning UI

**Files:**
- Modify: `WordMem/ContentView.swift`
- Modify: `WordMem/SystemDictionaryView.swift`
- Modify: `WordMem/CalendarChallengeService.swift`
- Modify: `WordMem/CalendarChallengeViews.swift`
- Modify: `WordMem/AddWordView.swift`
- Modify: `WordMemShareExtension/ShareViewController.swift`

**Result:**
- Detail shows canonical key/headword, user fields, import context, and a prominent system dictionary card.
- Tapping the system dictionary card presents Apple's UI in a medium sheet.
- No fake local definition, phonetic, senses, forms, tags, or legacy section.
- Calendar challenges only use entries with user-provided translation; remove dictionary-content hints and fallbacks.
- Manual/share forms collect only user translation/example/note, not competing dictionary phonetic data.

**Tests / manual checks:**
- Detail has no local-dictionary wording.
- `deliberately` opens Apple's system dictionary sheet.
- Calendar excludes entries without user translation.
- Accessibility labels still describe selected/corrected/unavailable states.

### Task 5: Cleanup and Verification

**Files:**
- Delete obsolete legacy tests and fixtures.
- Modify: `docs/local-first-architecture.md`
- Modify: `docs/superpowers/plans/2026-10-23-canonical-word-identity-clean-reset.md`

**Verification commands:**
```sh
xcodebuild test -project WordMem.xcodeproj -scheme WordMem \
  -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1'

xcodebuild test -project WordMem.xcodeproj -scheme WordMem \
  -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1'

xcodebuild build -project WordMem.xcodeproj -scheme WordMem \
  -destination 'generic/platform=iOS Simulator' -configuration Release \
  -derivedDataPath build/ReleaseVerification \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
```

**Additional acceptance:**
- `rg -n "ECDICT|LegacyA0|legacyExample|LegacyWordbook|WordMemMigrationPlan|BundledDictionaryLookupService|本地词典" WordMem WordMemTests WordMemShareExtension WordMemTranslationProvider` returns no runtime compatibility matches.
- No deprecated repository API remains.
- Fresh launch has an empty wordbook; new imports persist with canonical keys.
