# WordMem Local-First Architecture

## Product principles

- **Capture first.** The user enters one word. WordMem resolves the headword and enriches phonetics, meanings, forms, and tags without manual dictionary fields. If the optional dictionary resource cannot be opened, WordMem still captures a user-owned bare word.
- **Offline by default.** Core add-word behavior reads only bundled app resources and stores user data on device.
- **Apple-native.** The app uses SwiftUI, `NavigationStack`, SwiftData, structured concurrency, system accessibility, and iOS 26+ Liquid Glass controls. The minimum deployment target is iOS 27.0.
- **Replaceable dictionary.** Production lookups read a bundled, read-only ECDICT-derived SQLite database through Apple's SQLite3 C API. The old seed catalog remains a test fixture only.

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
- `SQLiteDictionaryLookupService` reads only bundled app resources and validates schema/source metadata at startup. It keeps independent high-frequency words exact (number, meeting), resolves clear inflections (running, teeth), and applies high-confidence close matches. Unknown words remain user-owned bare entries.
- `BareWordDictionaryLookupService` is the startup fallback so a damaged optional dictionary resource never blocks local capture.

## Dictionary pipeline

Run the reproducible generator from an ECDICT checkout:

```bash
python3 scripts/build_dictionary.py /path/to/ECDICT \
  --output WordMem/Resources/Dictionary.sqlite
```

The pipeline keeps words tagged for 中考/高考/CET4/CET6/考研/TOEFL/IELTS/GRE and the top 50,000 frequency rank. The current resource contains 57,838 entries, 49,564 lemma mappings, and 49,832 word forms in 16.6 MiB. Metadata includes the ECDICT revision, source-file SHA-256 hashes, row-selection counts, schema version, and pipeline version. ECDICT is MIT-licensed; its license is bundled as `ECDICT-LICENSE.txt`.
