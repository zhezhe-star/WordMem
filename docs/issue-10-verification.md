# Issue 10 — Shared import selection verification

## Result

Implemented one reusable, source-ordered candidate selection system for manual, text, image, and Translation Provider flows. The image and text flows no longer use a vertical candidate list; they now use the shared material context cards, compact step indicator, wrapping `FlowLayout` chip grid, selection controls, sticky selected-count CTA, and Simplified Chinese accessibility metadata. SwiftData models, submission wire fields, repository transaction behavior, duplicate history, OCR cancellation, camera permission handling, and provider persistence/session behavior remain unchanged.

## Changed / added Swift and project files

- `WordMem/Import/ImportCandidateModels.swift`
- `WordMem/Import/ImportFlowLayout.swift`
- `WordMem/Import/ImportContextViews.swift`
- `WordMem/Import/ImportSelectionViews.swift`
- `WordMem/TextImportView.swift`
- `WordMem/ImageImportView.swift`
- `WordMem/ImageImportSourceCard.swift`
- `WordMem/WordImportViews.swift`
- `WordMem/AddWordView.swift`
- `WordMem/ContentView.swift`
- `WordMem/Domain/WordImportModels.swift`
- `WordMemTranslationProvider/WordPickerView.swift`
- `WordMemTests/WordImportTests.swift`
- `WordMem.xcodeproj/project.pbxproj`

Shared import files are members of both `WordMem` and `WordMemTranslationProvider`. `TextImportView.swift`, `ImageImportView.swift`, and `ImageImportSourceCard.swift` are app-target focused view files. SwiftUI previews are included in `TextImportView.swift` and `ImageImportView.swift`.

## Focused tests added

All are in `WordMemTests/WordImportTests.swift`:

1. Default-all selection preserves source order.
2. Selection count and per-chip selection state.
3. Grouping preserves first-seen group order and source order.
4. 55 app candidates convert to stable source-ordered chip identities.
5. Refresh preserves deselections and selects newly introduced chips.

TDD evidence:

- Initial red: symbols absent (`Cannot find 'ImportCandidateChip'...`), `/tmp/wordmem-red.log`.
- Assertion red before selected-order implementation: three selection assertions failed, `/tmp/wordmem-helper-red.log`.
- Refresh red before API implementation: `Value of type 'ImportChipSelection' has no member 'updateChips'`, `/tmp/wordmem-update-red.log`.
- Final suite: 103 tests, 0 failures.

## Exact verification evidence

Date: 2026-10-23 Asia/Shanghai.

### Strict format

```sh
xcrun swift-format lint --strict --parallel <all changed/new Swift files>
```

Result: exit 0, zero findings (`/tmp/wordmem-swiftformat-final.log`, 0 lines).

### Tests, run twice consecutively

```sh
xcodebuild test -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1'
```

- Run 1: exit 0; `Executed 103 tests, with 0 failures`; `/tmp/wordmem-test-final-1.log`.
- Run 2: exit 0; `Executed 103 tests, with 0 failures`; `/tmp/wordmem-test-final-2.log`.

### Debug build

```sh
xcodebuild build -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1' -configuration Debug
```

Result: exit 0; `** BUILD SUCCEEDED **`; `/tmp/wordmem-debug-build.log`.

### Release signing-exempt build

```sh
xcodebuild build -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=1BEA71F5-D00C-4DD0-979B-44F5FC92E1D1' -configuration Release CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: exit 0; `** BUILD SUCCEEDED **`; `/tmp/wordmem-release-build.log`.

## Requirement disposition

| Requirement | Disposition |
|---|---|
| Image wrapping chip grid | Replaced `WordCandidateListView`; `ImageImportView` uses `ImportCandidateChipGrid`/`FlowLayout`. |
| Two-step image flow | Step 1 selects photo/camera and previews OCR context; step 1 becomes step 2 only after recognized candidates arrive. |
| Context visibility | Image keeps thumbnail plus recognized text in `ImportContextCard`; text/manual/provider show source context. |
| Shared manual/text/image/provider model | All use `ImportCandidateChip`, `ImportChipSelection`, `ImportCandidateChipGrid`, toolbar, and CTA. |
| Select/deselect, quick controls | Chips toggle selection; `ImportSelectionToolbar` exposes 全选 and 清除 with count. |
| 50+ candidates | Stable normalized/phrase IDs, source-order sorting/grouping, wrapping layout; 55-candidate unit test. |
| Selected-count sticky CTA | Shared `ImportPrimaryCTA` remains outside scroll content and reports count/save state. |
| Provider behavior | Translation session, phrase/word tokenization, builder fields, save coordinator, and completion behavior unchanged; only selection/presentation is shared. |
| Persistence semantics | No schema change or wire-format change; text/image/manual submission construction and metadata remain as before. |
| Accessibility | Chinese labels, values, button/selected traits, header/update-frequency traits, and contextual labels are present in shared controls. |
