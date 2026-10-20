# Local ECDICT SQLite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five-word development seed with a bundled, read-only ECDICT-derived SQLite dictionary while keeping WordMem fully offline.

**Architecture:** A reproducible Python build script trims ECDICT to learner-tagged words plus the top 50,000 frequency rank, emits a compact SQLite resource, and derives lemma lookup/forms from ECDICT's lemma database. A Sendable actor exposes read-only SQLite access through the existing `DictionaryLookupService` protocol; UI and SwiftData persistence stay unchanged.

**Tech Stack:** Swift 6, iOS 27 SwiftUI, SwiftData, Apple `SQLite3` module, Python 3 standard library, SQLite, XCTest.

**Spec:** `docs/local-first-architecture.md`

## Global Constraints

- App runtime must not create network connections; dictionary access is bundled-resource only.
- Minimum deployment target remains iOS 27.0.
- Uncompressed bundled SQLite must be ≤ 25 MB.
- Exact and lemma lookups must average < 30 ms; close-match lookup must average < 100 ms on iOS Simulator.
- Use Apple-native `SQLite3`, not third-party dependencies.
- Do not fabricate example sentences not present in ECDICT.

---

### Task 1: Reproducible ECDICT SQLite pipeline

**Files:**
- Create: `scripts/build_dictionary.py`
- Create: `WordMem/Resources/Dictionary.sqlite`
- Create: `WordMem/Resources/ECDICT-LICENSE.txt`
- Modify: `WordMem.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces SQLite tables `entries`, `lemma_lookup`, `forms`, `dictionary_meta`.
- `dictionary_meta.sourceRevision` records the ECDICT Git revision used to build the resource.

- [x] Verify ECDICT source is MIT and profile row counts/rank cutoffs.
- [x] Generate a prototype with learner tags (`zk,gk,cet4,cet6,ky,toefl,ielts,gre`) or rank ≤ 50000.
- [x] Confirm prototype is ≤ 25 MB and contains representative words.

### Task 2: Read-only SQLite dictionary actor

**Files:**
- Create: `WordMem/Services/SQLiteDictionaryLookupService.swift`
- Create: `WordMemTests/SQLiteDictionaryLookupServiceTests.swift`
- Modify: `WordMem/Domain/WordForm.swift` behavior only if an inflection kind is required
- Modify: app dependency wiring and project resources

**Interfaces:**
- Consumes: existing `DictionaryLookupService` protocol.
- Produces: `SQLiteDictionaryLookupService(databaseURL:)`.

- [x] RED: add tests for exact, lemma, close-match, not-found, metadata, resource size, and performance.
- [x] Verify RED by compiling/failing tests.
- [x] GREEN: implement Apple SQLite3 actor and resource lookup.
- [x] Verify GREEN.

### Task 3: Production wiring and cleanup

**Files:**
- Modify: `WordMem/ContentView.swift`
- Move test-only seed fixture out of app target
- Modify: `docs/local-first-architecture.md`

**Interfaces:**
- Produces: `ContentView` uses `SQLiteDictionaryLookupService` as production dependency.

- [x] Wire production service.
- [x] Document source/license/regeneration.

### Task 4: Verification

- [x] Run all tests on iOS 27.1 simulator.
- [x] Run Release simulator build.
- [x] Audit app source/runtime artifacts for network APIs.
- [x] Verify bundled resource size and exact/lemma/fuzzy performance thresholds.
- [x] Commit only after all checks pass.
