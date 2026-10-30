# WordMem Import & Detail UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Rebuild import review, word detail, and word list presentation around readable source context, phrase translation, pronunciation, phonetic metadata, and consistent iOS cards.

**Architecture:** Add a shared OCR formatter and extend the shared Translation session to translate both the phrase and selected-word candidates. Persist phrase translation through submission metadata into `WordImportContext`. Split SwiftUI presentation into reusable cards so list, detail, and import views share one visual rhythm.

**Tech Stack:** SwiftUI, SwiftData, VisionKit OCR, Apple Translation API, AVSpeechSynthesizer, XCTest.

**Spec:** Confirmed Phase 1 design in conversation: original text first, phrase translation second, split-word translations third; detail context text before source image; local optional phonetic; generic `EN` badge without flags.

## Global Constraints

- Do not introduce a public dictionary database or scrape Apple dictionary content.
- Apple dictionary is used only for availability and the system detail sheet.
- Do not fabricate IPA; `WordEntry.phonetic` is optional local metadata.
- Use a generic `EN` badge; do not use country flags.
- Preserve batch import default-deselection behavior.
- Preserve dictionary availability validation and identity normalization rules.
- New import enrichments do not block importing an otherwise valid word when translation fails.
- Keep exploration code native and clean; no compatibility shims.

---

### Task 1: OCR source formatting

**Files:**
- Create: `WordMem/Import/OCRTextFormatter.swift`
- Modify: `WordMem/ImageImportView.swift`
- Test: `WordMemTests/CanonicalCleanResetTests.swift`

**Interfaces:**
- Produces: `OCRTextFormatter.formattedText(from:) -> String`

- [x] Write failing tests proving clock/status/symbol noise removal, line merging, punctuation cleanup, and paragraph retention.
- [x] Implement deterministic OCR formatting using the existing sanitizer output.
- [x] Use formatted text for image import UI, candidate context, and submission source text.
- [x] Run the focused test suite and commit.

### Task 2: Phrase translation and persistence

**Files:**
- Modify: `WordMem/Import/ImportCandidateTranslationModifier.swift`
- Modify: `WordMem/TextImportView.swift`
- Modify: `WordMem/ImageImportView.swift`
- Modify: `WordMem/Domain/WordImportSubmission.swift`
- Test: `WordMemTests/CanonicalCleanResetTests.swift`

**Interfaces:**
- Produces: `ImportCandidateTranslationModifier.phraseIdentifier`
- Produces: submission metadata key `phraseTranslation`

- [x] Add a failing repository test proving submission metadata reaches import context metadata.
- [x] Extend the shared translation modifier to translate source text in the same batch as candidate chips.
- [x] Pass phrase translation into submission metadata from text and image imports.
- [x] Show phrase translation state in import review UI.
- [x] Run focused and full tests, then commit.

### Task 3: Detail metadata and pronunciation

**Files:**
- Modify: `WordMem/Domain/WordEntry.swift`
- Modify: `WordMem/ContentView.swift`
- Modify: `WordMemTests/CanonicalCleanResetTests.swift`

**Interfaces:**
- Produces: optional `WordEntry.phonetic: String?`

- [x] Add a failing test proving optional phonetic metadata persists.
- [x] Add optional phonetic without fabricating values.
- [x] Add a 44pt pronunciation button driven by `EnglishPronunciationPlayer`.
- [x] Add a generic `EN` language badge; no flags.
- [x] Run focused/full tests, then commit.

### Task 4: Shared presentation cards

**Files:**
- Create: `WordMem/WordPresentationViews.swift`
- Modify: `WordMem.xcodeproj/project.pbxproj`
- Modify: `WordMem/ContentView.swift`

**Interfaces:**
- Produces: `LanguageBadge`, `WordListCard`, `WordDetailHeader`, `InfoMetaCard`, `SourceEvidenceCard`

- [x] Implement reusable list/detail/context cards with shared spacing, radius, typography, and accessibility.
- [x] Replace the plain list row and detail form layout with the confirmed three-tier structure.
- [x] Render import context as formatted source text first and image second.
- [x] Compile for simulator and commit.

### Task 5: Import review UI

**Files:**
- Modify: `WordMem/Import/ImportContextViews.swift`
- Modify: `WordMem/Import/ImportSelectionViews.swift`
- Modify: `WordMem/TextImportView.swift`
- Modify: `WordMem/ImageImportView.swift`

**Interfaces:**
- Produces: `ImportSourceTextCard`
- Produces: `ImportPhraseTranslationCard`
- Produces: refreshed candidate card grid

- [x] Reorder import review into source text, phrase translation, candidate words.
- [x] Give candidate cards stable word/translation/badge hierarchy and 44pt targets.
- [x] Preserve restore-original behavior and selection state.
- [x] Run full tests twice and Release build, then commit.

### Task 6: Release verification

- [x] Run full test suite twice on simulator `987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0`.
- [x] Run unsigned Release simulator build.
- [x] Verify no `🇺🇸` / `🇬🇧` / manual import residue.
- [x] Summarize exact verification evidence.
