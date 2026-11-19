---
name: translation-device-ladder
description: 调试 iOS Translation API（翻译导入/系统翻译）相关问题的真机判读方法。当模拟器翻译结果不可信、真机翻译行为与代码预期不符、需要判断用户测的是不是最新构建、或设计翻译失败路径的真机验证清单时使用。
---

# Translation API 真机判读阶梯

## 前提事实

- **模拟器不能运行真实 Translation API**：任何模拟器里的翻译成功/失败都不是证据，只能验证状态机、UI 终态和构建。
- 真机结论必须绑定**构建号**：先确认 TestFlight App 里的版本号 (build)，再谈行为。

## 判读阶梯（按序检查）

1. **构建号指纹**：本项目的失败弹窗文案随版本变化。用户报"还是老问题"时，先让用户报版本号+构建号，或用弹窗文案反推：
   - 「暂不支持翻译 / 知道了」→ **旧包**（修复前的文案），一切结论作废；
   - 「需要下载翻译语言」+ 设置路径 + 重试/取消导入 → 新代码生效，才进入下一步。
2. **语言资源就绪**：新代码下失败弹窗先指引「设置 > App > 翻译 > 语言」下载语言包；`LanguageAvailability(.supported)` ≠ 已下载，下载与否只有真机知道。
3. **策略阶梯**：代码顺序是 high-fidelity（依赖 Apple Intelligence，`preferredStrategy`，iOS 26.4+ 守卫）→ legacy `LanguageAvailability()` → low-latency 重试一次。诊断时区分失败发生在哪一层。
4. **取消竞态**：SwiftUI 视图重布局会取消 `.translationTask`；`ImportDocumentSession.handleCancellation` 会 invalidate configuration 并保留 pending 标记。若表现为"永久转圈"或"闪一下就失败"，优先查这条路径（`ImportDocumentSession.swift`）。

## 真机清单

`docs/tasks/issue-22/real-device-checklist.md` 是权威清单（首次导入、拒绝下载、文档失败、chip 失败、重试保留译文）。

## 纪律

- 不用模拟器结果冒充真机证据；run-log 里 evidence 必须注明构建号/来源（simulator vs TestFlight build N）。
