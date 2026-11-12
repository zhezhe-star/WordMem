# WordMem 单词导入 — Superdesign 交互设计稿

Date: 2026-11-12
Tool: Superdesign (editable canvas)

## Canvas

https://superdesign.dev/teams/e895d94f-bdd8-41b0-aaf2-d6ec07e75d72/projects/69299388-9550-43ea-a17e-61ac8ba27bf4

## Design direction

**安静编辑纸感 / Quiet editorial notebook**

- 暖纸底色 `#F6F5F1`，白色 18pt 卡片；
- 墨色正文 `#1C1C1E`，单一森林绿强调色 `#4A7542`；
- SF Pro，20pt 屏幕边距，充足留白；
- 等宽字体只用于词形/音标等局部信息；
- 不用渐变、霓虹、玻璃拟态、AI 紫色光效。

## Flow

| # | Screen | Purpose |
| --- | --- | --- |
| 01 | 输入 · 空 | 全高 sheet，无额外主按钮；只保留取消 |
| 02 | 输入 · 键盘 | 键盘「完成」收起键盘后自动整理，不新增按钮 |
| 03 | 整理中 | 内联进度、骨架候选词；没有底部按钮 |
| 04 | 挑选 · 有候选 | 原文、译文、候选词、已选计数、导入 CTA |
| 05 | 挑选 · 无候选 | 只保留「编辑原文」的兜底空状态 |
| 06 | 保存成功 | sheet 关闭，词书上的轻量 toast |

## Key interaction decisions

1. **一个全高 sheet，不做多步向导。** 输入、整理、挑选在同一个 sheet 内切换。
2. **不新增确认按钮。** 收起键盘（键盘「完成」）即开始整理；整理只是预览，不保存。
3. **唯一保存入口是原有的「导入 N 个单词」。** 输入态和整理态没有底部按钮。
4. **处理中不可下滑关闭。** 只有取消或保存成功才关闭 sheet。
5. **AI 失败也必须出词。** 兜底候选来自系统词典；界面不出现模型名或技术阶段。
6. **保存成功用 toast，不用阻塞 alert。**

## Evidence

- `01-empty-input.png`
- `02-keyboard-typing.png`
- `03-organizing.png`
- `04-review-candidates.png`
- `05-no-candidates.png`
- `06-save-success.png`

## Implementation notes

- 01/02/03 可以直接映射到现有 `TextImportView` + `DocumentImportReviewScreen`：
  - `.presentationDetents([.large])`
  - 键盘工具栏「完成」只设置 `isSourceFocused = false`
  - focus 从 true 变为 false 时自动调用 `prepareText`
  - 输入态和整理态不显示底部 CTA
  - 处理中 `.interactiveDismissDisabled(true)`
- 04/05 对应 `DocumentImportReviewScreen` 的 review / noWords 状态。
- 06 对应现有保存成功后的 toast/alert；建议把阻塞 alert 换成底部轻量 toast。
- 颜色、圆角、间距与现有 `WordMemDesign` token 基本一致；实现时优先复用现有 token。

## Related tools

- `product-design:ideate` — 需要 3 个明显不同的视觉方向时，可基于这套 brief 生成图片方案。
- `product-design:image-to-code` — 选定一页后，用于把设计稿忠实实现为 SwiftUI。
- `design-review` — 实现完成后做一次视觉/交互质量门禁。
