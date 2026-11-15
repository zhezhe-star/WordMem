# Issue #22 Run Log

条目格式：`- [ISO 时间] <类型> — <内容>`；类型：decision / evidence / failure / milestone / checkpoint / quota-stop / evolve / release。

## 日志

- [2026-11-15T14:40:00+08:00] decision — Devflow kickoff 启动。Toolkit VERSION 1.1.3 / commit 790523b；项目基线 `c889bbe`，全量 115 tests / 0 failures。Issue #22 关联 worktree `翻译流程-bug-修复`，branch `zhezhe-star/翻译流程-bug-修复`。
- [2026-11-15T14:40:00+08:00] decision — 调研结论：主因是「双 Translation 会话并发 + 未 prepare + chip 翻译被文档结果门控 + 重试只重启文档」。证据见 plan.md 根因表 R1–R7。
- [2026-11-15T14:40:00+08:00] decision — 范围假设：修复主 App 文本/图片导入、Share Extension、Translation Provider 三处；不改 schema/依赖/CI。模拟器不能验证真实 Translation，真机验证以手工清单独立交付。
- [2026-11-15T14:40:00+08:00] evidence — 基线测试命令：`xcodebuild test -project WordMem.xcodeproj -scheme WordMem -destination 'platform=iOS Simulator,id=987CB4F0-4DB9-478B-99AF-AF2E45C0B4A0'` → **TEST SUCCEEDED**，115 tests / 0 failures。
- [2026-11-15T14:40:00+08:00] decision — 状态：三件套 draft，等待决策节点 1 批准。批准前不修改业务代码。
- [2026-11-15T14:52:00+08:00] decision — 用户修正范围：不新增“重新翻译单词释义”按钮；现有翻译卡“重试”升级为全流程重试（文档 + 全部缺失 chip），且只在自动 high-fidelity → low-latency 兜底仍失败后出现。已更新 plan.md / checklist.yaml 的 T03、T04、T07。
- [2026-11-15T15:10:00+08:00] decision — 用户提出交互主方案：用户在确认输入后停在导入页等待，所有终态错误统一用系统弹窗呈现，重试按钮放在弹窗上；模块内部不再保留重试按钮。方案升级为：单一 `.alert(item:)` + `ImportFailureAlert`，覆盖翻译（重试/暂不翻译）、图片处理（重新选择/取消）、保存（重试/取消）；Share Extension 用弹窗替换“重新翻译”，Provider 用弹窗替换手动入口。checklist 调整为 12 项（M1 6 / M2 3 / M3 3）。
- [2026-11-15T15:18:00+08:00] decision — 用户要求不提供“暂不翻译”选项。翻译失败弹窗改为“重试 / 取消导入”；取消会退出导入且不写入任何词条，避免无中文词条静默落库。由此翻译失败不再允许保存旁路，属于对 Fallback Matrix “翻译可选、失败可保存”契约的收紧，将在 T10 文档中显式记录。
- [2026-11-15T15:26:00+08:00] decision — 用户确认“取消导入”按入口定义返回路径：App 文字导入回文字编辑器（保留草稿）；App 图片导入回“已选图片+已识别原文”预览（保留图片）；Translation Provider 退出组件；Share Extension 关闭扩展。文字/图片入口不关闭导入 sheet，取消不写词书。已写入 plan.md 取消路径表与 T04 验收。
- [2026-11-15T15:38:00+08:00] decision — 用户要求测试使用 iPhone 17 Pro 机型。核实本机：Xcode 27.1，仅安装 iOS 27.1 runtime，且该 runtime 只支持 iPhone Duo；iPhone 17 Pro 设备绑定 iOS 26.4 runtime（未安装），在 iOS 27.1 上创建返回 `Incompatible device`，`xcodebuild -destination 'name=iPhone 17 Pro'` 返回找不到设备。项目 Deployment Target 为 27.0，无法回退到 26.4。当前自动化测试继续使用 iPhone Duo Test；改用 iPhone 17 Pro 需用户安装兼容 iOS 27.x runtime 或提供物理真机。已写入 plan.md 第 11 节。

- [2026-11-15T18:06:00+08:00] evidence — T01–T05 核心实现完成。`xcodebuild test ...` → **TEST SUCCEEDED**，126 tests / 0 failures（新增 prepare 顺序、单会话、文档失败仍翻 chip、chip 重试不重做文档、重试只补缺失 chip、翻译/图片/保存弹窗、取消路径等 11 个测试）。WordMem / WordMemShareExtension / WordMemTranslationProvider Debug 构建均 **BUILD SUCCEEDED**。
- [2026-11-15T18:06:00+08:00] decision — M1 代码改动：`ImportDocumentSession` 统一文档+chip 翻译并新增 prepare/重试状态机；`DocumentImportReviewModel` 改为单一 `ImportFailureAlert`；删除 `ImportCandidateTranslationModifier.swift` 及 pbxproj 引用；文字/图片取消路径已接线。
- [2026-11-15T18:07:00+08:00] checkpoint — M1 提交 `606076e`（15 files）。126 tests / 0 failures；WordMem / ShareExtension / TranslationProvider Debug 构建通过。T01–T06 complete。
- [2026-11-15T18:20:00+08:00] evidence — M2 扩展侧完成：Share Extension / Translation Provider 均在翻译前 prepare，首次失败自动 low-latency 重试；最终失败用弹窗（Share: 重试/取消关闭扩展；Provider: 重试/退出组件），模块内无手动重试按钮。两个扩展 Debug 构建 **BUILD SUCCEEDED**。
- [2026-11-15T18:25:00+08:00] evidence — T10 文档完成：Fallback Matrix 更新 prepare/单会话/统一弹窗/取消路径；新增 `docs/tasks/issue-22/real-device-checklist.md`。
- [2026-11-15T18:25:00+08:00] evidence — T11 全量验证：`docs/tasks/issue-22/logs/tests.log` → 126 tests / 0 failures；WordMem、ShareExtension、TranslationProvider Release 三个 `BUILD SUCCEEDED`，日志在 `docs/tasks/issue-22/logs/`。
- [2026-11-15T18:25:00+08:00] evidence — T12 模拟器冒烟（iPhone Duo Test / iOS 27.1）：文本导入出现单一“暂不支持翻译 / 知道了”弹窗，无模块内重试按钮；选择 2 个词并保存成功。截图 `docs/tasks/issue-22/screenshots/01-03`，副本在未跟踪 `tmp-issue-22-screenshots/`。**披露**：模拟器不能运行真实 Translation，可重试失败/取消路径仅由单元测试覆盖；真机待按清单验证。
- [2026-11-15T18:30:00+08:00] decision — 独立 agent 完成环境安装：iOS 27.0 (24A434) runtime + iPhone 17 Pro 模拟器 UDID `55DBFA05-48DE-453C-8871-288A22D251F3`（Booted）。旧 iOS 26.4 设备未改动。
- [2026-11-15T18:30:00+08:00] evidence — 测试切换到 iPhone 17 Pro：`tests-iphone17pro.log` → 126 tests / 0 failures。Release 三 Scheme 最终代码重跑均 BUILD SUCCEEDED。
- [2026-11-15T18:30:00+08:00] evidence — iPhone 17 Pro 冒烟：单一“暂不支持翻译 / 知道了”弹窗，无模块内重试按钮（截图 04）。新建 iOS 27.0 runtime 系统词典资源未就绪，出词/保存冒烟由 iPhone Duo Test 完成（截图 01-03）；已在 evidence-manifest 披露。
- [2026-11-15T18:30:00+08:00] checkpoint — 最终代码/文档待提交；M1 checkpoint `606076e`，M2 checkpoint `4297252`，M3 evidence `581dbb8`。所有 12 项任务 complete，进入最终验收（决策节点 4）。
