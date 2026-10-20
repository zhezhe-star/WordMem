# Full-page challenge cards: design and verification

- **Date:** 2026-10-21 (Asia/Shanghai working session)
- **Baseline:** merge `77f3278` (calendar challenge integrated with the offline ECDICT wordbook)
- **Request:** the v1 challenge presented all questions as a scrollable list, which did not match the expected word-app experience (reference: 欧路/墨墨-style review flows). Each question should occupy the whole page; answering slides automatically into the next question.

## 1. Confirmed product decisions

| Decision | Outcome |
| --- | --- |
| Interaction model | Keep the five existing question forms (meaning choice, listening choice, reverse translation, example cloze, spelling). Only the presentation changes; scheduling, answer state machine, and persistence are untouched. |
| Spelling card | Add hint affordances: phonetic, example sentence, per-letter slots, and a progressive letter-reveal hint button. |
| Navigation | After an answer is recorded, feedback shows briefly (~0.8 s) and the pager auto-advances. Manual swiping back to answered cards shows the locked recorded answer. |
| Appearance | Follow system light/dark; no forced dark theme. Layout mirrors the reference: top close button + progress bar + counter, centered hero content, bottom action area. |

## 2. Implementation summary

| Area | Change |
| --- | --- |
| `WordMem/CalendarChallengeService.swift` | `CalendarChallengeQuestion` gains `target` and `targetTranslation` so full-page cards render the word/translation as heroes without parsing `prompt`. Questions are not persisted, so no migration is needed. |
| `WordMem/CalendarChallengeFlowViews.swift` (new) | Rewritten `CalendarChallengeView` as a `TabView` page flow (one page per question + completion page) with a custom top bar (dismiss X, date title, answered/total counter, linear progress). `ChallengeQuestionPage` renders per-form heroes and bottom answer controls. `SpellingHintSlots` is a pure helper for the letter slots. Auto-advance is guarded so it never yanks the user back after a manual swipe. Completion page lists missed words. |
| `WordMem/CalendarChallengeViews.swift` | Old list-style `CalendarChallengeView`, `ChallengeQuestionCard`, and helpers removed; calendar home unchanged. |
| `WordMem/ContentView.swift`, `CalendarChallengeViews.swift` (DEBUG only) | `DebugDeepLink` environment hooks (`WORDMEM_OPEN_CHALLENGE`, `WORDMEM_CHALLENGE_DATE_OFFSET`, `WORDMEM_CHALLENGE_PAGE`) for headless-simulator UI verification; compiled out of Release. |
| `WordMemTests/CalendarChallengeTests.swift` | New tests: generated questions carry `target`/`targetTranslation`; spelling slot tokenization (reveal order, separator visibility, letter counting). |

## 3. Verification evidence

| Check | Method | Result |
| --- | --- | --- |
| Unit tests | `xcodebuild test` on iPhone Duo (iOS 27.1) simulator | PASS — 34/34 |
| Release compile | Runbook Release simulator build (`build/ReleaseVerification`) | PASS — `** BUILD SUCCEEDED **` |
| Full-page spelling card, light | Headless-simulator launch via `DebugDeepLink`, screenshot | PASS — `evidence/10-fullpage-spelling-card.png` |
| Second question page | Same, `WORDMEM_CHALLENGE_PAGE=1` | PASS — `evidence/11-fullpage-spelling-card-second.png` |
| Completion page | Same, page index = question count | PASS — `evidence/12-fullpage-completion.png` |
| Dark appearance | `simctl ui appearance dark`, relaunch, screenshot | PASS — `evidence/13-fullpage-spelling-card-dark.png` |

Environment note: this Mac's Xcode 27 install has no standalone Simulator.app and no idb, so taps/swipes cannot be injected; interactive states (auto-advance animation, locked review cards) are covered by code review and the unit-tested answer state machine instead of screenshots.
