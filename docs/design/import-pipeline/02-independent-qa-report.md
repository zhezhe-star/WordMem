# Independent Import Pipeline QA Report

## Result

**FAIL — do not release.** Functional Phases 1-4 matched the approved design in the inspected tree, but the required `swift-format lint --strict --parallel` gate returned exit 1.

## Scope and baseline

- Repository: `/Users/zhezhu/orca/workspaces/WordMem/apple-intelligence`
- Branch: `feature/import-document-pipeline`
- Implementation commits inspected: `6ce8b0d`, `771aaff`, `0f4b7b1`, and `ae35454`
- Base comparison commit: `b275a8b`

## Required gates

| Command | Result | Exit |
|---|---|---:|
| `xcrun swift-format lint --strict --parallel <all changed Swift files>` | FAIL | 1 |
| `xcodebuild test -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0'` (run 1) | 70 tests, 0 failures | 0 |
| Same `xcodebuild test` command (run 2) | 70 tests, 0 failures | 0 |
| `xcodebuild build -project WordMem.xcodeproj -scheme WordMem -configuration Debug -destination '<required destination>' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` | BUILD SUCCEEDED | 0 |
| Same build command with `-configuration Release` | BUILD SUCCEEDED | 0 |

The strict formatter reported indentation and line-length violations in:

1. `WordMem/Import/Document/CanonicalDocumentModels.swift`
2. `WordMem/Import/Document/TextDocumentCanonicalizer.swift`

## Design-contract results

| Contract | Result | Evidence |
|---|---|---|
| Unified `CanonicalDocument` | PASS | Text and image paths create `CanonicalDocument`; document session owns translation and candidate preparation stays separate. |
| Deterministic text canonicalization | PASS | Repeated canonicalization is equal; paragraphs, headings, lists, quotes, fenced code, UTF-16 spans, and long markdown-like articles are covered. |
| Vision reader with testable mapping | PASS | Snapshot boundary maps title, paragraph, list, table, geometry, confidence, and stable IDs without invoking iOS-only Vision in tests. |
| Typed translation states and no silent catch | PASS | Availability, download, unsupported, translating, completed, and typed failures are explicit; missing/empty/unknown failures are mapped. |
| `highFidelity` only where OS permits | PASS | Main app uses `LanguageAvailability(preferredStrategy: .highFidelity)` and configuration strategy; extension production flows remain unchanged. |
| Simple UI without pipeline terminology | PASS | Semantic review/translation copy is used; user-visible strings are checked for Vision/OCR/Foundation/batch/stage terminology. |
| Keyboard dismissal and sheet detents | PASS | Text sheet uses `[.medium, .large]`; focus is released for review, “完成” commits/dismisses, and scrolling dismisses interactively. |
| Existing save semantics unchanged | PASS | `WordImportSubmission`, `WordbookRepository`, and `WordMemStore` files have no implementation-branch diff; submissions still pass through repository dictionary validation and v3-compatible local metadata. |

## Adversarial coverage

| Input/condition | Result |
|---|---|
| Empty text | PASS — model resets; canonicalizer produces no blocks. |
| Whitespace-only text | PASS — model resets; canonicalizer produces no blocks. |
| Very long markdown-like article | PASS — added regression test validates 1,000 repetitions, structure, determinism, and unique IDs. |
| Markdown-like headings/lists/code/bold/link | PASS — source text is preserved while recognized structure remains deterministic. |
| Vision list/table fixtures | PASS — structure, geometry, confidence, and reading order are mapped. See advisory D1 for duplicated container/child text. |
| Unsupported language pair | PASS — fake availability produces typed unsupported state and no system translation request. |
| Unavailable/failed translation | PASS — missing response, empty response, generic errors, detection failure, and retry recovery are covered. |
| Unavailable Foundation Models | N/A — Phases 1-4 contain no Foundation Models dependency; deterministic path remains usable. |
| Dictionary-unavailable candidates | PASS — advisor marks unavailable words not offered; all-unavailable input shows the semantic no-words state. |
| Rapid re-processing | PASS — added controlled race keeps only the latest preparation and does not retain stale words. |
| AI/model suggestions introducing source words | N/A — no model-suggestion stage is implemented; candidates come from source text and dictionary availability remains the save gate. |
| Suggestions stored as dictionary content | PASS/N/A — translations are metadata on user-selected dictionary-validated candidates; no separate dictionary corpus is written. |

## Defects

### D1 — Duplicated structured Vision content in document translation metadata

- **Severity:** Low/Medium (data quality; does not block word selection or dictionary gate).
- **Location:** `VisionDocumentCanonicalMapper` emits both list/table container blocks and their child blocks; `ImportDocumentSession.translatedDocument` joins every block.
- **Reproduction:** Map the existing fixture with one list of two items and a 2×2 table, complete document translation, then inspect `model.translatedText`: item text appears both in the list container and in its child blocks; table text appears both in the table container and in each cell.
- **Impact:** The “phraseTranslation” metadata can duplicate list/table content.
- **Required follow-up:** Define one translation unit strategy for structured containers and children, or project a non-duplicating semantic translation surface.

### D2 — Required strict-format gate fails

- **Severity:** High for release gating.
- **Location:** `CanonicalDocumentModels.swift` and `TextDocumentCanonicalizer.swift`.
- **Reproduction:** Run the exact strict formatter command above.
- **Impact:** Branch fails the task’s mandatory QA gate despite functional tests/builds passing.
- **Required follow-up:** Run the project-approved formatter on those production files and rerun lint, tests, and builds.

### D3 — Approved-design status documentation mismatch

- **Severity:** Low.
- **Observation:** The inspected design file was still marked Proposed and had an execution cutline stating no implementation was authorized.
- **Resolution in QA commit:** Status/cutline metadata now records Phases 1-4 approval; contractual content is unchanged.

## Release decision

**Release cannot proceed.** Fix D1 after approval and D2 before release; also complete the design’s manual device matrix for image/text import on supported and fallback devices.
