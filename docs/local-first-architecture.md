# WordMem Local-First Architecture

## Product principles

- **Capture first.** The user enters one word. WordMem resolves the headword and enriches phonetics, meanings, forms, and tags without manual dictionary fields.
- **Offline by default.** Core add-word behavior reads only bundled app resources and stores user data on device.
- **Apple-native.** The app uses SwiftUI, `NavigationStack`, SwiftData, structured concurrency, system accessibility, and iOS 26+ Liquid Glass controls. The minimum deployment target is iOS 27.0.
- **Replaceable dictionary.** The seed catalog is an in-memory development source. The service boundary is designed so the production source can be a bundled read-only ECDICT-derived SQLite database without changing UI or persistence code.

## Runtime layers

```text
AddWordView (single input)
  → WordbookRepository (@MainActor + ModelContext)
    → DictionaryLookupService (bundled, Sendable)
      → WordEntry SwiftData store
ContentView (@Query)
  → list, detail, duplicate feedback, undo
LegacyWordbookMigrator
  → one-time UserDefaults backup + import
```

## Current boundaries

- `DictionaryLookupService` is the only source of dictionary enrichment.
- `WordbookRepository` owns duplicate detection, creation, enrichment of bare legacy entries, undo, and SwiftData saves.
- `LegacyWordbookMigrator` backs up the raw legacy payload before import and records a migration flag only after a successful save. User translations and legacy examples are retained in dedicated fields; dictionary enrichment updates canonical metadata without erasing that history.
- Repository and migration operations roll back pending SwiftData changes when persistence fails, so the reported result and visible context stay aligned.
- `DevelopmentSeedDictionaryCatalog` is explicitly temporary and must be replaced by the trimmed ECDICT SQLite resource before the dictionary MVP ships.

## Next implementation milestone

1. Generate a learner-focused ECDICT-derived SQLite resource (target ≤ 25 MB uncompressed).
2. Implement a read-only SQLite-backed `DictionaryLookupService` actor with exact, lemma, punctuation-normalized, and close-match indexes.
3. Keep the seed implementation as a test fixture and performance baseline.
4. Add lookup benchmarks and offline integration coverage.
