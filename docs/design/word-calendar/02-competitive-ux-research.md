# Competitive UX Research: Everyday Challenge Direction for WordMem

_Status: research synthesis for design discussion. Research date: 2026-10-19. It does not reproduce proprietary screenshots, illustrations, marketing copy, or product wording._

## 1. Scope and evidence rules

WordMem's near-term constraint is an **offline, local-first SwiftUI app**: daily progress, scheduling, and content must work without a required backend. This document therefore separates:

- **Observed / verifiable pattern (`O`)**: a publicly documented or directly stated product behavior. The linked source was opened or returned usable content during research; where Cloudflare blocked full-page rendering but the search tool returned official help-center content, that limitation is noted.
- **General product knowledge (`G`)**: a pattern remembered from ordinary use or public discussion that was not verified against an open source in this pass.
- **Speculative inference (`S`)**: WordMem's proposed interpretation or design extrapolation. These are hypotheses to validate, not claims about another product.

Products reviewed:

1. **Anki** — configurable SRS reference.
2. **Quizlet** — adaptive study sessions and familiar school-adjacent modes.
3. **Duolingo** — gamified daily habit loop, streak protection, and speech interaction.
4. **Drops** — very short visual vocabulary sessions.
5. **墨墨背单词 / Maimemo** — Chinese-market, exam- and word-book-oriented SRS.
6. **Pleco** — Chinese dictionary + paid flashcard add-on; relevant as an iOS-native, local-companion product.

## 2. Source key

| ID | Source and access status |
|---|---|
| A1 | [Anki Manual — Deck Options](https://docs.ankiweb.net/deck-options.html): daily new-card and review limits, workload simulation, FSRS, desired retention, maximum interval. Page opened successfully. |
| A2 | [Anki Manual — Backups](https://docs.ankiweb.net/manual/backups): periodic local card-data backups, restore warnings, media backup distinction. Markdown representation opened successfully. |
| Q1 | [Quizlet Help Center — Learn mode](https://help.quizlet.com/hc/en-ca/articles/360030986971-Studying-with-Learn-mode): progression from easier multiple-choice to harder written questions; optional audio, shuffle, starred terms, and question-type settings. Full page opened successfully. |
| Q2 | [Quizlet Help Center — Studying with Spaced Repetition](https://help.quizlet.com/hc/en-us/articles/48324742264077-Studying-with-Spaced-Repetition): website-only flashcard spacing behavior. Full page did not open in this environment because of a bot-check; search returned the official help-center excerpt. |
| Q3 | [Quizlet Help Center — Answer Streaks](https://help.quizlet.com/hc/en-us/articles/40011154960653-Studying-with-Answer-Streaks): consecutive-correct-answer streak within Learn. Full page did not open in this environment because of a bot-check; search returned the official help-center excerpt. |
| D1 | [Duolingo Help Center FAQ](https://www.duolingo.com/help/faq): streak concept, advance-purchase streak freeze, gem-purchased streak repair, quests as a gem source, weekly leaderboards, notification settings, and accessibility settings entry point. JSON-bearing page opened successfully. |
| D2 | [Duolingo Help Center — microphone / speaking exercises](https://support.duolingo.com/hc/en-us/articles/204642264-My-microphone-is-not-working-How-can-I-fix-it): speaking exercises are not available in every course; iOS can require speaking, microphone, and Apple speech-recognition permissions. Page opened successfully. |
| R1 | [Drops official site](https://languagedrops.com/): five-minute word games, visual/mnemonic vocabulary, spaced repetition and contextual learning claims, reminders, streaks, offline learning, and ad-free messaging. Page opened successfully. |
| M1 | [Maimemo / 墨墨背单词 help](https://www.maimemo.com/help30): recognizes “know / fuzzy / forgot / mastered” feedback; first-of-day feedback drives longer-term planning; learning load balances suggested new words and reviews; mastered words leave planning; per-word progress ring appears before due reviews. Page opened successfully. |
| P1 | [Pleco iOS flashcard tutorial](https://iphone.pleco.com/manual/30200/flashtut.html): SRS, due-card continuation, daily new-card limits, repeat-incorrect behavior, and tone/pinyin/handwriting test modes. Page opened successfully. |
| P2 | [Pleco Chinese Dictionary — App Store page](https://apps.apple.com/us/app/pleco-chinese-dictionary/id341922306): iPhone/iPad form factor, iOS TTS and optional native-recordings/TTS add-ons, flashcards as a paid add-on, handwriting/OCR positioning. Page opened successfully through a browser client. |

Some consumer-app accessibility behaviors are not fully published. Unless explicitly cited, treat accessibility claims below as **design requirements for WordMem**, not as verified claims about competitors.

## 3. Cross-product comparison

The table records observed/verifiable patterns first. If a cell has no public detail found, it says so rather than inventing a behavior.

| Dimension | Anki | Quizlet | Duolingo | Drops | Maimemo | Pleco |
|---|---|---|---|---|---|---|
| **Daily queue construction** | New cards/day and max reviews/day are configurable; sub-deck limits and a workload simulator help tune burden [A1]. | Learn organizes study around a set and user familiarity; spaced repetition is documented for web flashcards, not the same flow [Q1][Q2]. | Streak generally requires completing a lesson; quest/gem economy adds secondary goals [D1]. | Fixed very short word sessions make the unit of entry a time-boxed game rather than a count of due items [R1]. | Review plus suggested new words are combined into one adjustable “learning load”; heavy review days reduce new-word suggestions [M1]. | SRS shows due cards and can resume an interrupted session; new cards can be limited by day or total in circulation [P1]. |
| **Forgetting-curve scheduling** | Extensive knobs: FSRS desired retention, maximum interval, learning steps, and workload simulation [A1]. | Learn adapts by correctness within a set; separate web flashcard mode supports recall ratings and future review [Q1][Q2]. | Little public detail in sources reviewed; likely prioritizes course progression over explicit per-word SRS (`G`). | Public site names spaced repetition as part of its method, but exact per-word algorithm is not disclosed [R1]. | First-of-day feedback changes future interval; “know/fuzzy/forgot/mastered” has concrete short- and long-term effects [M1]. | Built-in SRS spaces successful cards farther apart and warns that long gaps may force restarting a card's progress [P1]. |
| **Challenge variety** | Variety comes from user-created note types and add-ons more than built-in minigames (`G`). | Multiple choice, written, spelling, flashcards, audio options, starred terms, and shuffle [Q1]. | Lessons, quests, leaderboards, legendary-style challenges, and subscription perks are referenced by FAQ/search results [D1]. | Word games, review modes, challenges, contextual quiz mode, and visual association are marketed as the core method [R1]. | Recall modes include recognizing English from Chinese, spelling, today/history review, and self-rating with memory-feedback buttons [M1]. | Modes include self-grading flashcards, pinyin entry, tone drills, fill-in-the-blank, and handwriting; dictionary capture can become cards [P1][P2]. |
| **Pronunciation / speech interaction** | Depends on note fields/add-ons; not a strong built-in speaking coach (`G`). | Audio settings and Spell mode are documented; no source reviewed establishes robust speech scoring [Q1]. | Speaking exercises exist but vary by course; iOS uses Apple speech recognition and can require microphone/speech permissions [D2]. | Native-speaker audio is part of marketing; public source reviewed does not verify local speech scoring [R1]. | Sources reviewed establish pronunciation as part of recall definitions, but not a verified speech scoring loop (`G` for interaction details). | iOS TTS plus optional native-speaker recording/higher-quality TTS add-ons; tone drills test perception rather than production [P1][P2]. |
| **Streak / recovery** | No default streak identified in sources reviewed; recovering missed work is a queue/backlog problem [A1][A2] (`G` for community norms). | Answer streak is within-session and resets when switching question types or answering incorrectly; no calendar streak found in cited source [Q3]. | Daily lesson streak plus advance-purchased freeze and paid repair; recovery is framed as forgiving but economic [D1]. | Reminders and streaks are official messaging; exact recovery rules not found in cited source [R1]. | Sources reviewed focus on memory planning rather than streak preservation; today/history review supports catch-up without changing future plans [M1]. | No streak mechanic found in manual; queue can resume later [P1]. |
| **Progress / calendar visualization** | Deck due counts and workload simulator; no source reviewed describes a polished consumer calendar [A1]. | Set mastery and answer streak are visible; no cited source establishes a full habit calendar [Q1][Q3]. | Streak, stats/profile, achievements, and league positions are surfaced through FAQ/profile descriptions [D1]. | Site emphasizes streak tracking; no detailed calendar visualization found [R1]. | Explicit word-level progress rings and charted study/forgetting data; some Maimemo-family help also describes calendar review planning (`G` for the exact current screen) [M1]. | Due-card counts and card statistics exist; manual source reviewed does not emphasize a consumer calendar [P1]. |
| **Session length / time budget** | User chooses limits, but workload can grow sharply without tuning [A1]. | Learn options customize question types and audio, but the cited page does not expose a default median session time [Q1]. | Short lessons; exact default length not cited in source reviewed (`G`). | Fixed five-minute entry point is the product promise [R1]. | Learning-load setting is explicitly a pressure/time-control lever [M1]. | No fixed consumer time budget; due queue determines session length [P1]. |
| **Friction / onboarding** | Powerful but configuration-heavy; manual itself says to spend weeks learning defaults before changing them [A1]. | Low setup around existing sets; paywall/trial messaging may add decision friction [Q1]. | Very low first-lesson friction; social/economic mechanics can add cognitive load (`S`). | Tap/swipe-first and five-minute cap reduce commitment friction [R1]. | Word-book selection and learning-load choices require intent; strong fit for exam users [M1]. | Add-on purchase and manual/profile setup create friction for casual learners [P1][P2]. |
| **Motivation system** | Mastery and workload control; motivation is mostly intrinsic (`G`). | Progress, answer streaks, and familiar study modes [Q1][Q3]. | Streaks, XP, gems, quests, weekly leaderboards, and reminders [D1]. | Streaks, short wins, visuals, challenges, and reminders [R1]. | Long-term retention curves and visible mastery help exam-oriented persistence [M1]. | Mastery, lookup-to-card convenience, and measurable card progress; little social motivation [P1][P2]. |
| **Accessibility** | Manual/documentation are text-based; app accessibility support varies by client and was not verified (`G`). | Options include audio and question-type choice; broader accessibility support not verified (`G`). | FAQ names an accessibility settings area, and speaking permissions are explicit [D1][D2]. | Public source reviewed did not enumerate accessibility support [R1]. | Accessibility support not found in cited source (`G`). | Manual shows display/audio customization; Voice Over support not verified (`G`). |
| **Failure states** | Missed days create backlog; backup restore loses changes since backup, and media needs separate handling [A1][A2]. | Wrong answers reset answer streak; interruption behavior not detailed in cited sources [Q3]. | Missed day breaks streak unless protected in advance; repair exists but can require currency/payment [D1]. | Timer end is a soft stop, but exact missed-day behavior was not verified [R1]. | Forgetting a word reappears sooner; review is not presented as irreversible failure [M1]. | Interrupted SRS session resumes; overlong gaps may effectively restart a card [P1]. |
| **Offline / local posture** | Local collection and local backups are central; sync is optional [A1][A2]. | Cloud account/content-centric; cited spaced-repetition workflow is web-only [Q2]. | Networked, account/social-centric; speech uses platform services [D2]. | Offline learning is advertised, but exact scope of free/offline assets was not verified [R1]. | Cloud word books/account exist in public product understanding; cited help does not establish a fully offline promise (`G`). | Dictionary/flashcards are device-centered companions; some add-ons/content are paid [P1][P2]. |

## 4. Reusable UX patterns

1. **Make tomorrow's burden visible before adding novelty.** Anki documents the causal relationship between new-card volume and future review load, and offers workload simulation [A1]. WordMem should show “if you learn 10 new words today, tomorrow's calendar will look like this.”
2. **Use a single honest daily budget, not separate new/review quotas.** Maimemo explicitly balances review and suggested new words to stabilize pressure [M1]. This is better than letting novelty crowd out retention.
3. **Let the user choose a time envelope and derive word count.** Drops's five-minute promise lowers commitment [R1]; Anki supports numeric limits [A1]. A time-first selector can reconcile both.
4. **Preserve the queue across interruptions.** Pleco resumes an unfinished SRS test later [P1]. WordMem should treat closing the app, a phone call, or low battery as a pause, not as lost progress.
5. **Turn errors into immediate micro-repair, not shame.** Pleco's repeat-incorrect option [P1] and Quizlet's in-session answer streak reset [Q3] show two useful halves: repair without punishing long-term progress.
6. **Separate a long-term forgetting schedule from optional practice.** Maimemo's today/history reviews do not affect future planning [M1], while Anki's filtered decks can support cramming [A1]. WordMem should expose “review” and “extra practice” as different modes.
7. **Use graduated challenge variety, not random novelty.** Quizlet moves from easier recognition to harder production [Q1]. WordMem can map this to recognition → meaning selection → recall → spelling/speaking.
8. **Reward consistency but make recovery recoverable.** Duolingo's streak freeze/repair is motivating but can feel punitive if it requires purchases [D1]; Drops frames streaks as progress support [R1]. WordMem should favor local, earned, or free recovery.
9. **Offer a compact memory state per word.** Maimemo's per-word progress ring gives a decay cue without exposing algorithm internals [M1]. A simple glyph, color, or ring can make the calendar legible.
10. **Back up and explain data-recovery consequences.** Anki distinguishes card-data backups from media and warns that restore loses later changes [A2]. Local-first WordMem needs equal clarity.
11. **Make permissions a prerequisite, not a surprise.** Duolingo documents speaking plus microphone and speech-recognition permissions on iOS [D2]. WordMem should gate speech challenges with a visible fallback.
12. **Design a no-audio/no-mic path.** Duolingo says speaking exercises are not available in every course [D2]. WordMem should never let an unsupported microphone or missing voice make the daily queue feel blocked.

## 5. WordMem-specific differentiators

These are **speculative product directions (`S`)**, grounded in the observed patterns above but not claims about competitors.

1. **Calendar-as-queue, not calendar-as-streak.** Most products emphasize a streak count. WordMem's differentiator can be a local calendar that shows today's due load, predicted tomorrow, catch-up days, and rest days. The visible goal is “keep memory healthy,” not “do not break the flame.”
2. **Offline time-boxed challenge.** WordMem can start with a 3/5/10-minute contract, then derive a queue from local due words. This combines Drops's low commitment [R1] with Anki/Maimemo workload control [A1][M1] while keeping the app useful on a plane or subway.
3. **Memory load as the primary control.** Instead of a fixed 20-new-words setting, WordMem can expose Light / Normal / Intense. The scheduler adjusts new-word intake after reviewing the current due backlog, following Maimemo's pressure-balancing pattern [M1].
4. **Local personal-context challenges.** Without licensed content or backend generation, WordMem can create low-cost challenge variants from user-owned words: audio recall, cloze from a user-entered example, reverse recall, spelling, and speaking. This is closer to Anki/Pleco flexibility [A1][P1] than to a content subscription.
5. **Speech as optional spice, never a dependency.** On-device iOS speech recognition can unlock a “say it” challenge after Duolingo-style permission setup [D2], but WordMem should fall back to listen-and-self-rate or tap/typing so accessibility, noisy rooms, and unsupported locales do not break the day.
6. **Recovery insurance with no paywall.** WordMem can grant one local “catch-up token” per completed week and allow a missed day to become a shortened recovery session. It should avoid Duolingo-style currency/payment framing [D1] because the product promise is local ownership.
7. **Local-first diagnostics and repair.** WordMem can show whether the database, backups, audio assets, and calendar records are healthy, and let the user export a portable archive. This extends Anki's backup discipline [A2] into a friendlier failure-state UI.
8. **Privacy-honest adaptive scheduling.** If WordMem personalizes intervals, it can state “based only on your device history.” That differentiates from data/networked habit systems and fits local-first expectations.

## 6. Recommended Everyday Challenge flow

This flow is a **design hypothesis (`S`)**; it should be prototyped and validated.

### A. Today screen

1. Show a single primary card: **Today's 5-minute challenge**.
2. Beside it, show three compact facts: due words, likely new words, and estimated minutes.
3. Show a weekly memory bar rather than a guilt-heavy streak flame: completed, recovery, rest, and future load.
4. Put “Change duration” and “Just review” as secondary actions.

### B. Queue construction

1. Reserve the first 50–70% of the time envelope for due words.
2. Fill remaining capacity with new words, but reduce intake when due backlog exceeds the user's recent completion rate.
3. Interleave one “confidence” item after a failure to avoid ending on frustration.
4. Keep an optional 30-second preview before new words, but do not require it.

### C. Challenge sequence

1. **Warm-up:** one recent success or audio-only recognition item.
2. **Review:** mixed recognition/recall challenges, with keyboard optional.
3. **Production:** spelling or speaking only for eligible words; always offer “skip speaking today.”
4. **Micro-quiz:** three rapid items from today's mistakes.
5. **Closure:** show words learned, words retained, time spent, tomorrow's predicted load, and one local backup/health indicator when relevant.

### D. Failure and recovery

- **Closed mid-session:** mark the item boundary as the resume point.
- **Partially completed:** count completed items toward the daily calendar and schedule the remainder as a shorter recovery.
- **Missed day:** do not reveal the full backlog by default; offer a 3-minute recovery that reschedules the oldest or highest-risk items first.
- **Bad speech experience:** self-rate or convert to listening; mark the result as provisional rather than “wrong.”
- **Database/backup failure:** route the user to a plain-language repair/export screen before normal study resumes.

## 7. Risks and tradeoffs

| Risk | Why it matters | Mitigation to test |
|---|---|---|
| **Challenge variety erodes scheduling clarity** | Minigames can obscure whether an item is due, new, practice, or assessment. | Every screen keeps a mode label and scheduling effect; practice never silently changes long-term state. |
| **A strict time box underserves exam users** | Maimemo's audience benefits from explicit learning-load control [M1]. | Offer a normal time-first mode plus an advanced word-count/load mode. |
| **A calendar can create streak anxiety** | Duolingo's freeze/repair shows recovery mechanics can motivate or pressure users [D1]. | Frame calendar cells as memory states; make recovery always free and never auto-enroll users into social comparison. |
| **On-device speech is uneven** | Duolingo documents per-course limitations and iOS permission requirements [D2]. | Treat speech as an enhancement; test locale, microphone, and accessibility fallbacks before counting it as progress. |
| **Local-first limits content richness** | WordMem cannot rely on licensed media, server generation, or cloud user content. | Start with system TTS/recorded user audio, simple local illustrations, and user-provided examples; make export/import first-class. |
| **Personalization may feel opaque** | SRS users need to trust why an item returned. | Show next-interval reasoning in plain language and allow an expert view. |
| **Backups and restore are easy to get wrong** | Anki warns that restoration loses later changes and treats media separately [A2]. | Create scheduled and manual local archives; warn before overwrite; provide a checksum and version marker. |
| **Accessibility retrofits are expensive** | Public product documentation rarely provides complete accessibility evidence. | Set WordMem acceptance criteria for Dynamic Type, VoiceOver, reduced motion, captions/transcripts, and keyboard/switch paths before building challenge modes. |

## 8. Open questions

1. Should WordMem's minimum viable challenge contain recognition only, or must it include recall/spelling from day one? Quizlet's easier-to-harder progression [Q1] suggests starting with recognition, but vocabulary retention may require production earlier.
2. Is the calendar primary or secondary? A queue-first home screen may be more useful, while a month view may be more motivating.
3. What is the minimum free local backup story? Anki's automatic backups include card data but not media [A2]; WordMem may need a different boundary if audio is central.
4. Which Chinese-market users matter most: exam-driven users who want Maimemo-like control [M1], casual travelers who want Drops-like five-minute wins [R1], or lookup-driven learners who want Pleco-like capture [P1]?
5. How much algorithm transparency is useful? Maimemo exposes behavior effects and progress [M1]; Anki exposes parameters [A1]. WordMem needs a middle ground.

## 9. Source list

1. Anki Manual — Deck Options: <https://docs.ankiweb.net/deck-options.html>
2. Anki Manual — Backups: <https://docs.ankiweb.net/manual/backups>
3. Quizlet Help Center — Learn mode: <https://help.quizlet.com/hc/en-ca/articles/360030986971-Studying-with-Learn-mode>
4. Quizlet Help Center — Studying with Spaced Repetition: <https://help.quizlet.com/hc/en-us/articles/48324742264077-Studying-with-Spaced-Repetition>
5. Quizlet Help Center — Answer Streaks: <https://help.quizlet.com/hc/en-us/articles/40011154960653-Studying-with-Answer-Streaks>
6. Duolingo Help Center FAQ: <https://www.duolingo.com/help/faq>
7. Duolingo Help Center — microphone and speaking exercises: <https://support.duolingo.com/hc/en-us/articles/204642264-My-microphone-is-not-working-How-can-I-fix-it>
8. Drops official site: <https://languagedrops.com/>
9. Maimemo / 墨墨背单词 help: <https://www.maimemo.com/help30>
10. Pleco iOS flashcard tutorial: <https://iphone.pleco.com/manual/30200/flashtut.html>
11. Pleco Chinese Dictionary — App Store: <https://apps.apple.com/us/app/pleco-chinese-dictionary/id341922306>
