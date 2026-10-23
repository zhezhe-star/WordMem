# WordMem Canonical Local-First Architecture

## Product principles

- **Capture first.** A selected English word is saved as `locale + normalizedKey`, together only with the user's translation, example, note, and import context.
- **No independent dictionary corpus.** WordMem stores no definitions, senses, phonetics, forms, tags, dictionary IDs, dictionary versions, or bundled lookup data.
- **Apple dictionary is authoritative.** `UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)` gates capture. `UIReferenceLibraryViewController(term:)` presents Apple's dictionary UI in a medium sheet; WordMem never copies or synthesizes its content.
- **Destructive v3 reset.** The native SwiftData store starts empty and discards incompatible exploration-era stores, queue defaults, and migration markers once. No schema migration plan or compatibility repository API remains.

## Runtime flow

```text
Manual / text / image / share / translation provider
  → cleaned source context
  → English word candidate splitter
  → ImportWordAdvisor
      • NaturalLanguage lemma
      • UITextChecker spelling suggestion
      • SystemDictionaryAuthorizing final availability
      • SystemDictionaryAuthorizing restored-original availability
  → WordbookRepository
      • preserves advisor normalizedKey
      • revalidates final and restored keys
      • skips unavailable candidates
      • stores phrase context separately from WordEntry
      • deduplicates replay by stable payload IDs
  → WordMemStore v3
```

## Model boundaries

- `WordEntry` is a word identity and user record. It contains `id`, locale, normalized key, headword, original text, system availability, user fields, and timestamps.
- `WordImportContext` stores cleaned source text, selected candidate, recognized text, image bytes, submission/candidate payload IDs, and metadata. Phrase context has `phraseContext: true`, has no `WordEntry`, and is never dictionary gated.
- `SystemDictionaryAuthorizing` is the only dictionary boundary and exposes availability only. `UIKitSystemDictionaryAuthorizer` delegates to the public iOS dictionary API.
- Import metadata records canonical key, original word/key, lemma or spelling advice, and both final/restored availability results. These are provenance fields, not dictionary content.
- `OCRTextSanitizer` removes clocks, carrier/status noise, battery numbers, standalone numerics, and symbol-only lines before display, persistence, candidate splitting, or advisory lookup.
- Calendar challenges receive only entries with nonempty user-provided translation and use only user-provided examples. Dictionary-content hints and fallbacks do not exist.

## Persistence

`WordMemStore` creates `Application Support/WordMem/wordmem-v3.store` with `WordEntry` and `WordImportContext` in one native schema. Its one-time destructive reset removes historical `.store` SQLite files and historical queue/default keys. On later launches the marker is present, so v3 data persists normally. Persistence failures roll back the model context.
