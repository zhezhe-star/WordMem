# WordMem Local-First Architecture

## Product principles

- **Capture first.** The user enters or selects a word. WordMem stores the normalized word key and the user-created/imported context immediately. Authoritative definitions are delegated to iOS at read time instead of requiring local dictionary enrichment.
- **No independent dictionary corpus.** WordMem keeps a word-key list. Definitions and pronunciations come from the iOS system dictionary through public UIKit APIs; data the system does not provide is intentionally not synthesized or bundled.
- **Apple-native.** The app uses SwiftUI, `NavigationStack`, SwiftData, structured concurrency, system accessibility, and iOS 26+ Liquid Glass controls. The minimum deployment target is iOS 27.0.
- **System-dictionary-backed details.** `UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)` checks availability, and `UIReferenceLibraryViewController(term:)` presents Apple's dictionary UI. There is no public iOS API that programmatically extracts definition content, so WordMem does not persist authoritative meanings for new entries.

## Runtime layers

```text
AddWordView / TextImportView / ImageImportView
  / ShareViewController / Translation provider picker
  → ImportCandidatePipeline
    → ImportWordAdvisor
      → NaturalLanguage lemma lookup
      → UITextChecker spelling suggestion
      → UIKit system dictionary availability check
  → WordbookRepository (@MainActor + ModelContext)
    → DictionaryLookupService (Sendable)
      → SystemDictionaryLookupService
        → UIKit system dictionary availability check
      → WordEntry SwiftData store
ContentView (@Query)
  → list, detail, duplicate feedback, undo
WordEntryDetailView
  → live system-dictionary availability check
  → SystemDictionaryView sheet for Apple dictionary presentation
LegacyWordbookMigrator
  → one-time UserDefaults backup + import
```

## Current boundaries

- `ImportCandidatePipeline` is the shared sentence-splitting boundary. After a sentence is split into unique source words, every word passes through `ImportWordAdvisor`; manual, text, image, share, and translation-provider imports use the same candidate model and payload metadata.
- The advisor applies NaturalLanguage lemma normalization and UITextChecker spelling correction automatically. The corrected key is the default, while immutable advice retains the original word for an explicit restore action.
- Both corrected and restored keys are gated independently by system-dictionary availability. The restore control is offered only when the original key is also present; otherwise the candidate remains non-selectable.
- `ImportCandidateChip` uses indigo for lemma normalization, orange for spelling correction, and red for system-dictionary unavailability. A candidate that the system dictionary cannot resolve is not selectable by default; the explicit restore control is the only override.
- Candidate selection remains default-none. Advice changes identity, availability, and display only; it never automatically selects a word for import.
- Translation-provider phrase context remains available as non-dictionary-gated context, while individual source words continue through the same advisor.
- `DictionaryLookupService` is the only capture-time dictionary boundary. New runtime lookups return key-only entries; an available system word is reported as enriched, otherwise as not found.
- `WordbookRepository` owns duplicate detection, creation, enrichment of bare legacy entries, undo, and SwiftData saves.
- `LegacyWordbookMigrator` backs up the raw legacy payload before import and records a migration flag only after a successful save. User translations and legacy examples are retained in dedicated fields; dictionary enrichment updates canonical metadata without erasing that history.
- Repository and migration operations roll back pending SwiftData changes when persistence fails, so the reported result and visible context stay aligned.
- Existing SwiftData records keep their legacy senses, phonetics, forms, tags, and user fields. They are preserved for backward compatibility; new records do not receive an independent local copy of that content.
- The detail view rechecks system availability on appearance and offers Apple's dictionary sheet when available. If unavailable, it directs the user to Settings › General › Dictionary. This avoids a false “local dictionary missing” state.
