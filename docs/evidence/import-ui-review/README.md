# 文本导入 UI/UX Review

Date: 2026-11-12
Device: iPhone Duo Test simulator, iOS 27.1

## Flow reviewed

1. Open text import from the empty wordbook.
2. Focus the source editor.
3. Enter an English sentence.
4. Confirm the source and reach word review.

## Findings

| Priority | Finding | Fix |
| --- | --- | --- |
| P1 | Text import opened in a medium sheet. The source editor and bottom action were clipped; a software keyboard would leave almost no editing space. | Text import now uses a full-height `.large` sheet. |
| P1 | The keyboard toolbar "完成" both committed the draft and dismissed the keyboard, so processing could start unintentionally. | "完成" now only dismisses the keyboard. Dismissing the keyboard starts preparation; no extra commit button was added. |
| P1 | The input state had a disabled "导入 0 个单词" bottom action, which was not the next step. | Input and organizing states have no bottom action. The existing "导入 N 个单词" appears only when review is ready. |
| P2 | The sheet showed two "导入" headings: the navigation title and a large in-content title. | Text import uses a compact subtitle instead of the duplicate large header. |
| P2 | The empty editor showed "没有可保存的单词" before any content had been entered in Debug builds. | The preview model now starts in `.capturing` when the source and chips are empty. |
| P2 | The sheet could be swiped away while processing or saving. | Interactive dismissal is disabled while busy or saving. |
| P2 | Translation/unavailable states could start an optional translation task and show a blocking system sheet. | Translation availability is checked after chips are ready, and chip translation starts only when document translation is available. |
| P2 | The no-candidates state was a single line of copy and still mentioned a non-existent "手动添加" action. | It now has an icon, title, body, one "编辑原文" action, and revised copy. |
| P2 | The translation card had no language pair indicator. | It now shows an "EN → 中文" badge above the card. |
| P2 | The input state had no helper copy or character count. | It now shows the supported-content hint, a live character count, and the keyboard-dismiss hint. |
| P2 | The organizing state had no candidate placeholders. | It now shows skeleton candidate cards while preparing. |
| P2 | Save success used a blocking alert. | It now uses a compact bottom toast. |
| P3 | The cancel action was a plain toolbar text button. | It is now a pill button matching the design. |
| P3 | Candidate cards used a vertical accent bar and separate badges. | They now use a top-right check and a single monospaced provenance line. |

## Behaviour after the fix

- Typing does not start processing.
- The keyboard "完成" only dismisses the keyboard.
- Dismissing the keyboard starts preparation automatically; the sheet stays open.
- There is no extra commit button. The only save action is the existing "导入 N 个单词".
- Processing and review happen in the same sheet; the sheet only closes on cancel or after a successful save.
- If Apple Intelligence is unavailable, deterministic candidates still appear (`garden`, `grow`, `quickly` in the evidence).

## Evidence

- `01-before-empty-medium-sheet.png`: clipped medium sheet, duplicate title, misleading empty message.
- `02-before-typed-keyboard-toolbar.png`: keyboard "完成" mixed with the import CTA.
- `03-after-empty-no-extra-cta.png`: full-height sheet, compact subtitle, no extra bottom button.
- `04-after-typed-keyboard-no-cta.png`: keyboard open, helper/character count, no extra CTA.
- `05-after-review-existing-import-cta.png`: review state with the translation badge, polished chips, and the existing import CTA.
- `06-after-no-candidates-empty-state.png`: no-candidates empty state with a single edit action.
- `07-after-save-toast.png`: compact save-success toast over the wordbook.

## Verification

- `xcodebuild test`: 114 tests, 0 failures.
- Release builds: `WordMem`, `WordMemShareExtension`, `WordMemTranslationProvider` all `BUILD SUCCEEDED`.
- `swift-format lint --strict` passed for the changed Swift files.
