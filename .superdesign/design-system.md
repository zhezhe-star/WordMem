# WordMem Import — Interaction Design System

## Product context

WordMem is a local-first English vocabulary app for Chinese-speaking learners.
The import flow turns any English text or image into a small, reviewable set of
words the user can save.

The product promise is simple: paste something interesting, see the words worth
keeping, choose them, and get back to reading. AI is an optional assistant, never
a gate. The interface must still work when Apple Intelligence, translation, or
the network is unavailable.

## Design direction

**Quiet editorial notebook.** A calm paper-like surface, ink-dark type, a single
forest-green accent, and generous margins. It should feel like marking up a
printed article, not configuring a dashboard.

Use:

- warm off-white paper surfaces;
- thin separators and soft 18pt cards;
- one green accent for selection and primary action;
- SF Pro with clear type hierarchy;
- monospaced type only for lemmas, phonetics, and word identity details;
- restrained motion: sheet expansion, chip selection, progress states.

Avoid:

- gradients, neon, glassmorphism, purple AI glow;
- dashboard cards, metric tiles, badges for every feature;
- full-screen spinners;
- exposing model names, framework names, or technical stages;
- auto-committing text, auto-closing the sheet, or auto-selecting words.

## Flow model

One full-height sheet. Three user-visible stages:

1. **输入** — paste or type English content.
2. **整理** — the app extracts structure, translates when possible, and prepares
   dictionary-backed candidate words.
3. **挑选** — review the source, optional translation, and candidate chips, then
   import the selected words.

The sheet only closes when the user taps Cancel or after a successful import.

## Screen 1 — Empty input

- Full-height iOS sheet with a visible grabber.
- Inline navigation title: “导入”. A pill “取消” button on the trailing edge.
- One-line subtitle: “输入英文内容，挑选要加入单词本的词。”
- Large paper card labeled “原文”, with placeholder “输入或粘贴英文内容。”
- Helper line under the editor: “支持段落、列表、表格。”
- Sticky bottom action: primary “整理内容”, disabled while the editor is empty.
- No empty-state error copy before the user has entered anything.

## Screen 2 — Typing with keyboard

- The editor card grows with the text; the sheet stays full height.
- The primary “整理内容” button sits above the keyboard, not under it.
- The keyboard toolbar contains only “完成”, which dismisses the keyboard. It
  must not start processing.
- A small “粘贴” affordance sits inside the editor card.
- Optional character count appears only after the first line, in a quiet caption.
- The source remains editable; nothing is confirmed until the user taps
  “整理内容”.

## Screen 3 — Organizing

- The source card collapses to a readable preview with “编辑原文”.
- One inline status row: small progress ring + “正在整理内容…”.
- Translation card appears only when it has something to show. If unavailable,
  it shows “翻译暂不可用，可以直接保存单词。” with a quiet “重试”.
- Candidate area uses skeleton chips or a subtle shimmer; no blank screen.
- Sticky bottom action becomes disabled “正在整理内容…”.
- The sheet cannot be swiped away while organizing.

## Screen 4 — Review with candidates

- Source card: label “原文”, 2–3 line preview, trailing “编辑原文”.
- Translation card: language badge “EN → 中文”, translated text clamped to 5
  lines, “显示全部” when expandable. Failure state stays actionable.
- Selection toolbar: “已选 2/8” on the left; “全选” and “清除” on the right.
- Candidate chips in a two-column adaptive grid. Each chip is a soft card with:
  - the word in 17pt semibold;
  - an optional lemma line, e.g. “原文 grows · 原形 grow”;
  - a quiet translation line (“暂无翻译” until available);
  - a 22pt circular check control on the right.
- Selected chips use the forest accent: green tint background, green border,
  green check. Unselected chips stay paper-white.
- Sticky bottom action: “导入 2 个单词”, enabled only when at least one word is
  selected.
- If AI is unavailable, show a quiet inline note: “已为你准备词典候选。” Do not
  mention Apple Intelligence or Foundation Models.

## Screen 5 — No candidates

- Keep the source and translation cards visible.
- Empty state inside the candidate area:
  - short title “没有可保存的单词”;
  - body “可以换一段内容，或手动添加。”
  - primary “编辑原文”;
  - secondary “手动添加”.
- Do not show a spinner. Do not auto-close the sheet.

## Screen 6 — Save success

- Sheet dismisses only after a successful save.
- The wordbook is visible and a compact toast confirms “已添加 2 个单词”.
- No blocking alert for a normal successful save.

## Visual tokens

- Paper background: #F6F5F1
- Card surface: #FFFFFF
- Ink: #1C1C1E
- Secondary ink: #6B6B70
- Accent forest: #4A7542
- Accent tint: #E7EFE3
- Divider: #E5E3DD
- Warning: #B26A2E
- Error: #B4433B

Type:

- Large title / sheet title: 28–32pt, semibold
- Section title: 20pt, semibold
- Body: 17pt, regular
- Secondary / helper: 15pt, regular
- Caption: 13pt, medium
- Word chip heading: 17pt, semibold
- Lemma / phonetic: 13pt, monospaced

Spacing:

- Screen margin: 20pt
- Card padding: 16pt
- Card radius: 18pt
- Card gap: 12pt
- Section gap: 20pt
- Minimum touch target: 44pt

Motion:

- Sheet expansion: system spring.
- Chip selection: 160ms ease-out scale 0.98 → 1.0 + tint change.
- Status transitions: opacity + 4pt slide, no bouncing.
- Respect Reduce Motion.

## Component inventory

1. `ImportSheetHeader` — inline title, subtitle, Cancel pill.
2. `SourcePaperCard` — editor or read-only preview, label, helper, edit action.
3. `TranslationCard` — language badge, clamped text, expand/collapse, retry.
4. `InlineStatusRow` — progress ring or icon + one-line status.
5. `SelectionToolbar` — selected count, Select All, Clear.
6. `CandidateChip` — word, lemma line, translation line, check control.
7. `StickyPrimaryAction` — full-width 52pt primary button with icon.
8. `QuietToast` — bottom toast for save confirmation.

## Copy deck

- Sheet title: 导入
- Cancel: 取消
- Subtitle: 输入英文内容，挑选要加入单词本的词。
- Editor placeholder: 输入或粘贴英文内容。
- Helper: 支持段落、列表、表格。
- Primary, empty: 整理内容
- Primary, busy: 正在整理内容…
- Primary, review: 导入 N 个单词
- Organizing: 正在整理内容…
- Preparing words: 正在准备单词…
- Translation unavailable: 翻译暂不可用，可以直接保存单词。
- No candidates: 没有可保存的单词
- No candidates body: 可以换一段内容，或手动添加。
- Edit source: 编辑原文
- Add manually: 手动添加
- Select all: 全选
- Clear: 清除
- Saved: 已添加 N 个单词

## Accessibility

- Every chip is a single accessible button with label “word，meaning，selected
  or not”.
- The selection toolbar announces “已选 N 个，共 M 个”.
- Status changes are announced once; do not repeat announcements on every
  render.
- All controls meet 44pt touch targets.
- Support Dynamic Type; the editor grows and the sticky action stays reachable.
- Do not rely on color alone for selection: include the check mark and
  accessibility value.

## What makes this feel professional

- One primary action per state.
- The next step is always visible above the keyboard.
- The app never pretends AI is required.
- Errors are quiet, actionable, and never leave a blank screen.
- The sheet behaves like a document editor, not a wizard.
