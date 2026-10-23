# System dictionary migration — ECDICT/SQLite audit and UIReferenceLibraryViewController findings

Date: 2026-10-23 · Branch: `zhezhe-star/issue-10-claude-dictionary`

## 1. Audit of the bundled ECDICT/SQLite dictionary

| Fact | Value |
| --- | --- |
| Resource | `WordMem/Resources/Dictionary.sqlite` (removed in this change) |
| On-disk size | 17,383,424 bytes (~16.6 MiB) shipped inside the app bundle |
| Tables | `entries`, `lemma_lookup`, `forms`, `dictionary_meta` |
| Source | ECDICT, MIT license, revision `bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b` |
| Selection | `learner tags or frequency <= 50000` → 57,838 entries, 49,564 lemmas, 49,832 word forms (from 770,611 source rows) |
| Pipeline | `scripts/build_dictionary.py`, pipelineVersion 3, schemaVersion 1, SHA-256 provenance for source CSV/lemma/license |
| Runtime consumers (before) | `ContentView` (service init, legacy-wordbook enrichment), `WordbookRepository` via injected `DictionaryLookupService`, `WordImportSubmissionMigrator` queue processing |
| Non-runtime references | `scripts/build_dictionary.py` (kept as provenance), `docs/superpowers/plans/2026-10-20-local-dictionary-sqlite.md` (historical), `docs/local-first-architecture.md` (now stale — needs coordinator-side refresh) |

The database was well-formed and license-compliant (MIT, attribution bundled as
`ECDICT-LICENSE.txt`). Its cost: ~16.6 MiB of bundle size and a copy of
"authoritative" definitions/pronunciations that duplicated what iOS already
ships in the system dictionary.

## 2. API / platform findings

- `UIReferenceLibraryViewController` is **not deprecated**; available iOS 5.0+,
  iPadOS 5.0+, Mac Catalyst 13.1+, visionOS 1.0+. Not listed on Apple's
  deprecated-symbols page.
- `class func dictionaryHasDefinition(forTerm:) -> Bool` is the documented way
  to check availability *before* presenting
  (`UIReferenceLibraryViewController(term:)` would otherwise show an empty
  controller).
- The class is `@MainActor`-isolated in the modern SDK. Under Swift 6/strict
  concurrency the availability query must run on the main actor; the
  implementation hops to the main actor explicitly. First query may block
  briefly while the system loads its dictionary database; subsequent queries
  are cheap. Import flows call it once per candidate word, sequentially.
- The system dictionary **vends no programmatic content**: no definition text,
  phonetics, or word forms can be extracted — only availability plus the
  presentation UI. This is why the wordbook now keeps a *word key list* and
  defers definitions/pronunciations to the system UI at presentation time.
- System dictionaries are managed assets: on a fresh device they may not be
  downloaded yet, so `dictionaryHasDefinition` can return `false` for real
  words until the user downloads dictionaries (Settings › General › Dictionary)
  or the system fetches them on demand. The detail view re-checks availability
  live on every appearance, so entries self-heal once dictionaries arrive.
- Inflexions: the system dictionary resolves inflected forms ("gave",
  "running") at presentation time, so per-word lemma storage is unnecessary
  for display. It does not, however, canonicalize the stored key (see residual
  risks).
- Pronunciation playback is unaffected: `EnglishPronunciationPlayer`
  (AVSpeechSynthesizer) never depended on the bundled database.

## 3. App Store risk

**None identified.** Both APIs are public, documented UIKit; no private or
undocumented API is used, and `dictionaryHasDefinition(forTerm:)` is used
exactly as documented (pre-presentation availability check). No new
entitlements, no network access, no third-party code. Removing the bundled
ECDICT data also drops the MIT attribution requirement from the shipped app
(the license file was removed with the data).

## 4. What changed

- New `SystemDictionaryLookupService` (runtime `DictionaryLookupService`):
  availability via `UIKitSystemDictionaryAvailability` (seam protocol for
  tests); returns `.enriched` (system dictionary has a definition) or
  `.notFound`, always with a **key-only** `DictionaryEntry`
  (`isContentBearing == false`).
- New `SystemDictionaryView` (`UIViewControllerRepresentable` over
  `UIReferenceLibraryViewController(term:)`), presented from the word detail
  view via a "在系统词典中查看释义" button when a live availability check passes.
- `WordbookRepository` and `LegacyWordbookMigrator` only apply lookup results
  whose entry `isContentBearing`; key-only results refresh a `.notFound` badge
  to `.enriched` without touching stored/user content (non-destructive; all
  existing SwiftData records, phonetics, senses, tags, and import contexts are
  preserved; no schema migration).
- Removed from runtime: `SQLiteDictionaryLookupService`,
  `BareWordDictionaryLookupService`, `Dictionary.sqlite`,
  `ECDICT-LICENSE.txt` (Resources group deleted).
- User-facing copy no longer claims a "本地词典": missing-copy now references
  the system dictionary with a Settings › General › Dictionary hint; add-word
  and empty-state copy updated. Zero remaining occurrences of
  `本地词典暂未收录` (and of `本地词典` at all) in app sources.
- Tests: `SQLiteDictionaryLookupServiceTests` deleted;
  `DictionaryLookupTests` rewritten around the new service (stubbed
  availability, key-only contract, non-destructive re-import, legacy-migration
  preservation, UIKit smoke test). The `BundledDictionaryLookupService` test
  double and the import/repository suites that use it are unchanged.

## 5. Residual risk (exact)

1. **No offline enrichment for new imports.** New entries store only the word
   key; phonetic/senses/tags/forms are no longer persisted. Words imported
   before this change keep their stored ECDICT content (preserved, not
   migrated). Calendar challenge cards that need a translation
   (`CalendarWord.translation`) will fall back to user translations for
   key-only entries; entries with neither stored nor user translation can only
   be quizzed via forms that don't need a translation prompt — verify challenge
   eligibility filtering still excludes translation-less words.
2. **Availability false-negatives before dictionaries download.** Imports on a
   device without downloaded dictionaries are marked `.notFound` (待补充) even
   for common words. Mitigated by live re-check in the detail view and by the
   status-refresh path on re-import; not auto-healed for rows that are never
   re-opened/re-imported.
3. **No lemma canonicalization at import.** "give" and "gave" now import as
   separate keys (previously collapsed via `lemma_lookup`). Duplicate-adjacent
   entries may accumulate; the system dictionary still shows correct
   definitions for each. Restoring canonicalization would require another
   public API (e.g. NaturalLanguage `NLTagger` `.lemma`), which was out of
   scope for this change.
4. **No auto-correct suggestions.** `autoCorrected` status is no longer
   produced at runtime (the system API has no suggestion surface);
   misspelled words import as `.notFound` keys. `lemmaResolved` /
   `autoCorrected` / `ambiguousResolved` statuses remain in the model for
   existing records and for content-bearing test doubles.
5. **Dictionary coverage differs from ECDICT learner tags.** Exam tags
   (CET4/考研…) and frequency ranks are unavailable from the system
   dictionary; existing records keep theirs.
6. `scripts/build_dictionary.py` is retained but now orphaned (its output is
   no longer shipped); regenerate-only provenance. `docs/local-first-architecture.md`
   still describes the bundled-dictionary architecture and should be refreshed
   by the coordinator.

## 6. Verification

- Debug build: `xcodebuild build -scheme WordMem -configuration Debug` — succeeded.
- Tests: full `WordMemTests` suite on iPhone Duo simulator (iOS 27.1) — see task report.
- `grep -rn "本地词典" WordMem WordMemShareExtension WordMemTranslationProvider WordMemTests` — zero matches.
