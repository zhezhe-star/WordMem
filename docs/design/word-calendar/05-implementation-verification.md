# Word Calendar v1 implementation verification

- **Date:** 2026-10-19 (Asia/Shanghai working session)
- **Branch / HEAD:** `zhangzhe/issue-6` / `64a73d979272aa228ff564fe389b0c5b9c252d88`
- **Result:** Release-ready for v1, subject only to the environment limitations below.
- **Verification verdict:** Scope, local-only behavior, compatibility, iOS 15 target, accessibility states, edge states, and the final test suite passed. One low-risk SwiftUI defect was found and fixed.

## 1. Scope checks

| Check | Method | Result |
| --- | --- | --- |
| Exactly two root tabs | Reviewed `ContentView` and searched all Swift sources for `TabView`. The sole root contains 单词本 and 日历. | PASS |
| Calendar-only task indexing | Reviewed `CalendarChallengeService.dueWords` and `CalendarHomeView.monthDays`. Tasks use local `WordData.createdAt` plus offsets `0, 1, 3, 7, 14`; every local day is rendered. `createDateString` is display-only. | PASS |
| Day-to-Challenge navigation | Reviewed available-day `NavigationLink` paths and selected-day summary. Available due/partial/complete days navigate to `CalendarChallengeView`; rest, empty, and future cells do not. | PASS |
| Mixed question list | Reviewed `questions(on:from:)`; forms include meaning, listening, reverse translation, cloze when supported, and spelling. UI shows a single scrollable list. | PASS |
| Local progress persistence | Reviewed separate `wordmem.calendar_challenge.progress.v1` storage, service reload tests, per-answer save, and completion timestamp. Malformed challenge data resets only challenge progress. | PASS |
| `saved_words` compatibility | Reviewed unchanged `LocalStorageManager`, additive `createdAt` initializer parameter, existing wordbook test, and new cross-read test. Challenge storage does not write `saved_words`. | PASS |
| No microphone/camera/cloud/network/analytics | Scanned `WordMem` and `WordMemTests` for capture, `URLSession`, CloudKit, telemetry, and related Info.plist keys. AVFoundation is used only for local TTS playback. No matches were found. | PASS |
| No unnecessary changes | Compared `main...HEAD` and the working tree. New code is Calendar/service/view/test/report support only; existing wordbook flows remain unchanged. | PASS |
| iOS 15 compatibility | App/test deployment target is iOS 15.0. New controls (`NavigationView`, `foregroundStyle`, `textInputAutocapitalization`, `submitLabel`, `tint`) are iOS 15-compatible. | PASS |
| Accessibility | Reviewed labels, status text, button traits, 44 pt targets, color-plus-text feedback, and snapshot strings such as “10月20日，待完成，可打开挑战。” | PASS with zh-CN literals consistent with the existing app |
| Edge states | Reviewed empty wordbook, rest day, future day, due, partial, complete, one/missing distractors, missing example, missing TTS fallback, and local day boundaries. Unit tests cover scheduling, boundaries, mixed generation, persistence, completion, and `saved_words`. | PASS |

## 2. Commands and exact outcomes

1. Final test command:

   ```sh
   xcodebuild test -project WordMem.xcodeproj -scheme WordMem -configuration Debug \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
     -derivedDataPath build/CalendarChallengeDerivedData
   ```

   Outcome:

   - `Executed 7 tests, with 0 failures (0 unexpected)`
   - `** TEST SUCCEEDED **`
   - shell exit `0`
   - log: `build/calendar-challenge-final-test.log`

2. Forbidden-capability scan:

   ```sh
   grep -RInE 'AVCapture|AVAudioApplication|AVAudioSession|URLSession|NSURLSession|CFNetwork|Analytics|Firebase|Mixpanel|Sentry|PostHog|Amplitude|NSMicrophoneUsageDescription|NSCameraUsageDescription|CKContainer|CloudKit|dataTask|websocket' WordMem WordMemTests
   ```

   Outcome: no matches.

3. Diff hygiene:

   ```sh
   git diff --check
   ```

   Outcome: no whitespace errors.

## 3. Defect found and fixed

- **Defect:** `monthDays()` created every leading blank calendar cell from the same `CalendarDayItem` ID. Duplicate `Identifiable` IDs are undefined behavior in `ForEach`.
- **Fix:** Generate unique `blank-<month>-<offset>` IDs for the leading blanks.
- **File:** `WordMem/CalendarChallengeViews.swift`
- **Verification:** Reran the final full `xcodebuild test`; all 7 tests passed and `TEST SUCCEEDED` was reported.

No other functional defects were found.

## 4. Simulator UI evidence

Screenshots are under `docs/design/word-calendar/evidence/`.

| File | Evidence |
| --- | --- |
| `01-initial-tab.png` | Actual final root launch: exactly 单词本 and 日历; empty wordbook state and add/import affordance. |
| `03-calendar-home-today.png` | Month title, month grid, rest/due/future indicators, selected today overview, “已答 0/7”, and Start Challenge button. |
| `04-day-challenge-top.png` | Day Challenge list with “进行中 0/5”; visible mixed 释义选择 and 听力选择 cards, options, hint, and TTS controls. |
| `06-day-challenge-partial-persisted.png` | Reloaded partial state at 1/5; completed card has a green icon and “回答正确。”, while later cards remain interactive. |
| `07-day-challenge-complete.png` | Completion state at 5/5, green progress, “已完成 5/5 题正确”, local-save notice, and answered mixed-form cards. |
| `08-existing-wordbook.png` | Existing wordbook list and add affordance remain functional with local seed data. |
| `09-final-root-launch.png` | Final rebuilt app again shows the unchanged two-tab root and populated wordbook. |

The requested iPhone 17 Pro / iOS 26.4 simulator was available and used. The headless XcodeBuildMCP tap mapper dispatched bottom controls below the visible iOS 26 hit area, so interactive bottom taps were not reliable. To avoid changing product behavior, temporary diagnostic-only root destinations were used to open the same Calendar, Challenge, and Wordbook views for screenshots; all temporary source edits were reverted. Persisted partial/completion evidence was prepared through the same local UserDefaults schema and reloaded by the production service/views.

## 5. Remaining limitations

- UI copy is localized as zh-CN literals, matching the existing app. No additional localization catalogs were introduced.
- Xcode emits non-blocking warnings that the iOS 17.0 XCTest framework is newer than the test bundle’s iOS 15.0 simulator target; this affects only the test runtime and no app source/API failure was observed.
- Manual month-arrow taps were not exercised in the headless simulator because of the tap-coordinate issue above; the implementation and accessibility controls were code-reviewed, and month/day rendering was visually verified.
- Design docs `01`, `02`, and `04` were pre-existing untracked working files and were not modified or treated as implementation diffs.

## 6. Release readiness

Recommend **release-ready for approved v1**. The implementation is coherent and local-only, preserves the wordbook contract, passes all tests, and has no remaining in-scope product defect. The review-only source fix and report/evidence artifacts remain uncommitted for normal review; do not push or open a PR until those intentional changes are accepted/committed under the repository’s normal workflow.

## 7. Coordinator post-commit re-verification

After independent verification, the leading-blank identity fix was committed as `bd83ceb`, and the design/review artifacts were committed in the documentation commit. The coordinator reran the same iPhone 17 Pro / iOS 26.4 test command from commit `27d835a`. The final result was `Executed 7 tests, with 0 failures (0 unexpected)` and `** TEST SUCCEEDED **`. No code changed after that test.
