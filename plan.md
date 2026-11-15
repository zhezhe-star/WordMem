# Issue #22 翻译流程 bug 修复 — 计划

Status: **draft（等待决策节点 1 批准）**

- Repo: `zhezhe-star/WordMem`
- Branch: `zhezhe-star/翻译流程-bug-修复`
- Issue: [#22 翻译流程 bug 修复](https://github.com/zhezhe-star/WordMem/issues/22)
- Devflow: `~/.orca/devflow` VERSION 1.1.3 / commit `790523b`
- Kickoff 基线: `c889bbe`，`115 tests, 0 failures`（2026-11-15 14:32 CST）

## 1. 现状调研结论

Issue 描述的三个现象都能在代码里定位到确定原因：

1. 导入后“翻译暂时不可用”，重试一次才恢复；
2. 重试后原文翻译恢复了，但拆解单词的中文释义仍然缺失；
3. 文字导入最容易触发。

### 根因表

| ID | 根因 | 证据 | 影响 |
| --- | --- | --- | --- |
| R1 | 主 App 导入页同时挂载两个 `.translationTask`，文档翻译和单词释义翻译几乎同时启动 | `WordMem/Import/DocumentImportReviewViews.swift:83-92`，两个 configuration 在 `DocumentImportReviewModel.prepare` 末尾同时置非 nil（`:303-312`） | 两个 Translation 会话争用系统翻译扩展；首次冷启动时一个会话中断，表现为“翻译暂时不可用” |
| R2 | 四个翻译入口都没有在翻译前调用 `session.prepareTranslation()` | `WordMem/Import/Document/DocumentTranslationEngine.swift:52-72`；`WordMemShareExtension/ShareViewController.swift:236`；`WordMemTranslationProvider/WordPickerView.swift:259`；`TranslationCardView.swift:107` | 首次使用 / 语言资源刚安装 / Apple Intelligence 模型未就绪时首轮翻译失败；稍后重试才成功 |
| R3 | 单词释义翻译被文档翻译结果门控 | `WordMem/Import/DocumentImportReviewModel.swift:306-312` 仅在文档 phase 为 `.translating/.completed` 时启动 chip 翻译 | 文档翻译失败时，单词释义翻译**根本不启动**；拆解词永远没有中文 |
| R4 | 重试只重启文档翻译，不重启单词释义翻译；单词释义也没有独立重试入口 | `WordMem/Import/DocumentImportReviewViews.swift:330` + `WordMem/Import/Document/ImportDocumentSession.swift:119-122`；chip 失败后无 UI 动作 | 用户重试后文档中文恢复，但拆解词仍是“暂无翻译”；保存时 `translation == nil`，词条落库无中文 |
| R5 | Translation Provider 的 chip 翻译失败被 `try?` 静默吞掉，随后仍允许保存 | `WordMemTranslationProvider/WordPickerView.swift:259-267`，`WordImportSubmission.swift:269-288` | 系统翻译 App 里拆解词中文缺失且无提示、无重试 |
| R6 | 语言资源未安装（`.needsLanguageDownload`）时不会自动进入翻译会话，必须用户手动点重试才会弹出下载 | `DocumentImportReviewModel.swift:317-323` 只对 `.translating` 启动；`DocumentImportStatusPresenter` 只展示“需要下载翻译资源” | 首次导入多一步“重试”，与 Issue 的“需要重试”现象一致 |
| R7 | Share Extension / Translation Provider 没有自动 low-latency 兜底（主 App 有，扩展没有） | `ShareViewController.swift:236-247`，`TranslationCardView.swift:107-117` | 扩展侧高保真策略失败后直接进入失败态，只能手动重试 |

### 关键外部事实

- Apple 文档明确 `TranslationSession.prepareTranslation()` 用于提前请求语言资源下载/准备；对“内容会动态出现”的 App 是官方推荐做法。
- Apple WWDC 说明 Translation API **在模拟器不可用**，必须在真机验证；因此本轮模拟器只能验证状态机、构建和 UI 终态，真机能力另附手工清单。
- `TranslationSession` 在 view 消失或 configuration 改变后不可再使用；同一视图挂两个 `translationTask` 会放大配置失效和会话中断风险。

## 2. 目标状态与“完成”的度量

完成后：

1. 主 App 的文本/图片导入只有一个 Translation 会话在运行；不存在文档翻译与 chip 翻译并发。
2. 每次进入翻译会话都先 `prepareTranslation()`；首次使用、资源刚安装、模型未就绪时不再依赖“用户先失败一次再重试”。
3. 重试（文档卡上的“重试”或单词区的“重新翻译释义”）会重启**所有未完成的翻译工作**；已成功的译文保留，不重复、不清空。
4. 文档翻译失败不会阻止单词释义翻译；所有流程终态错误统一用系统弹窗呈现，重试动作放在弹窗上；模块内部不再出现重试按钮。
5. Share Extension 与 Translation Provider 同样先 prepare，并在首次失败后自动尝试一次 low-latency（可用时）。
6. 保存路径不变；翻译失败不再提供“暂不翻译后保存”的旁路——用户只能重试或取消本次导入，避免无中文词条静默落库。

可检验判据：

- `xcodebuild test` 全绿，新增测试覆盖 prepare 顺序、单会话、失败后 chip 仍翻译、重试重启全部工作、重试保留已完成结果。
- 主 App 导入页源码中只剩一个 `.translationTask` 挂载点。
- `WordMem` / `WordMemShareExtension` / `WordMemTranslationProvider` 三个 Scheme Release 构建通过。
- 模拟器冒烟：文本导入可出词、可选；翻译失败态弹窗只有“重试/取消导入”；无崩溃。
- 真机手工清单（本轮无法自动执行）记录在 `docs/tasks/issue-22/real-device-checklist.md`。

## 3. 非目标

- 不接入云端翻译或第三方翻译服务。
- 不改拆词、候选筛选、Foundation Models curation、保存/去重/词书 schema。
- 不重做导入页视觉设计；**模块内部不新增任何按钮**，重试只存在于系统弹窗。
- 不承诺模拟器能验证真实翻译能力；真机验证不在本轮自动验收范围内。
- 不处理与 Issue #22 无关的翻译 App 集成问题（如系统 Translation UI 自身行为）。

## 4. 约束与不变式

- 可重试的翻译失败不允许静默保存无中文词条：用户必须重试成功或取消本次导入。
- 不支持的语言对属于不可恢复限制：信息弹窗“知道了”后仍可保存；这是唯一不重试的翻译终态。
- 图片处理、保存失败的弹窗动作不得导致数据丢失。
- 主 App 导入页同一时刻最多一个 Translation 会话。
- `TranslationSession` 只在 `.translationTask` 提供的 action 闭包生命周期内使用；configuration 改变后不得复用旧 session。
- 扩展 target 最低 iOS 18：`preferredStrategy`（iOS 26.4+）必须用 `#available` 守卫；不可提高扩展部署版本。
- 不新增依赖、不改 CI/CD、不改数据库 schema。
- 用户可见文案保持现有设计口径；只新增“单词释义暂不可用，可重试”一类可操作提示。

## 5. 技术方案

### 5.1 主 App：一个导入 = 一个翻译会话

把 chip 释义翻译并入 `ImportDocumentSession`，由同一个 `.translationTask` 驱动：

- 新增 `ChipTranslationUnit { id, text }`；`ImportDocumentSession` 持有 `chipUnits`、`chipTranslations`、`chipPhase`。
- `DocumentImportReviewModel.prepare` 在 chips 生成后 `session.registerChips(offeredChips)`，再启动一次会话。
- `ImportDocumentSession.handle(session)` 顺序：
  1. `try await session.prepare()`
  2. 文档翻译（仅当 `documentWorkPending`）
  3. chip 翻译（仅当 `chipWorkPending`，只翻缺失项）
  4. 成功后清空 configuration；失败则按“high-fidelity → low-latency”只重试一次
- 删除 `ImportCandidateTranslationModifier`（不再有第二个 `translationTask`）。
- `DocumentImportReviewModel.chipTranslations / chipTranslationPhase / isChipTranslating` 改为读取 `documentSession` 的计算属性，保存路径与视图绑定不变。

### 5.2 prepareTranslation

- `DocumentTranslationSessionHandling` 增加 `prepare()`，提供默认空实现以免破坏所有测试 fake。
- `SystemDocumentTranslationSession.prepare()` 调 `session.prepareTranslation()`。
- Share Extension / Translation Provider 在各自 `translate` 前调用 `try await session.prepareTranslation()`。

### 5.3 重试语义

- `ImportDocumentSession.retry()`：重新检查 availability；对未完成的文档/chip 工作置 pending，再启动新 configuration。一次点击覆盖**文档 + 全部缺失 chip**，不再只重启文档。
- 所有重试保留 `chipTranslations` 中已成功的结果。
- 不新增 retryChips() 之类的第二入口；重试入口只有一个——失败弹窗上的“重试”。
- 弹窗只在**自动 high-fidelity → low-latency 兜底也失败后**出现一次：
  - 文档翻译最终失败；或
  - 文档成功但仍有 chip 释义缺失。
  正常翻译中不弹；`.unsupportedLanguagePair` 弹信息型弹窗（只有“知道了”，无重试）；资源未安装由 `prepareTranslation()` 自动拉起系统确认，用户拒绝后才进入可重试的失败弹窗。

### 5.4 资源未安装

- `.needsLanguageDownload` 也启动会话；`prepareTranslation()` 会由系统弹下载确认。
- 用户拒绝下载时映射回 `.needsLanguageDownload`，保留可重试状态。

### 5.5 统一失败弹窗（交互主方案）

约束：用户在“收起键盘/确认输入”后停在导入页等待结果，错误应当集中、可操作，而不是散落在各模块。

- 在 `DocumentImportReviewScreen` 根部只挂一个 `.alert(item:)`，所有导入终态错误都走同一个 `ImportFailureAlert`。
- 弹窗字段：`kind`（translation / imageProcessing / save）、标题、说明、重试标题、次要按钮标题、是否显示重试。
- 交互：
  | 失败类型 | 标题 | 说明 | 主按钮 | 次按钮 |
  | --- | --- | --- | --- | --- |
  | 文档翻译失败 | 翻译暂时不可用 | 请重试；也可以取消本次导入。 | 重试（全流程） | 取消导入 |
  | 仅 chip 释义缺失 | 部分单词释义暂不可用 | 原文已翻译，请重试补齐释义。 | 重试（全流程） | 取消导入 |
  | 语言资源被拒绝/未安装 | 需要翻译资源 | 下载语言资源后才能翻译。 | 重试（重新拉起系统确认） | 取消导入 |
  | 不支持的语言对 | 暂不支持翻译 | 当前设备暂不支持英语到中文的翻译，仍可保存单词（不可恢复限制）。 | 知道了 | — |
  | 图片处理失败 | 无法处理这张图片 | 换一张图片，或返回后重试。 | 重新选择 | 取消 |
  | 保存失败 | 导入失败 | 单词还没有写入，请重试。 | 重试（重新提交） | 取消 |
- 弹窗只出现一次；用户点“取消导入”会退出本次导入，不写入任何词条。模块内只保留静态状态文案（无按钮）。
- 弹窗由系统呈现，自动获得 VoiceOver 焦点与无障碍语义。

#### 取消路径（按导入方式定义）

“取消”不是统一的关闭动作，而是回到该入口“确认导入之前”的状态：

| 入口 | 取消后的落点 | 实现 |
| --- | --- | --- |
| App 文字导入 | 回到文字编辑器，保留用户输入的草稿；清空候选词、翻译、错误态；不自动弹键盘，用户修改后再次收起键盘即可重跑完整流程 | `TextImportView` 保留 `draftText`；`model.beginEditingOriginal()` |
| App 图片导入 | 回到“已选图片 + 已识别原文”的预览态；清空候选词、翻译、错误态；保留 `capturedImage` / `imageData` / 原文，用现有“更换照片 / 重拍”重新选择 | `model.cancelTranslationKeepingSource()`；`ImageImportView` 不清理图片状态 |
| Translation Provider | 直接退出组件，回到系统翻译界面 | `context.finish(translation: nil)` |
| Share Extension | 关闭扩展，回到系统分享面板 | `onClose()` → `completeRequest` |

约束：取消路径不得写入词书，不得保留半成品 submission；文字/图片入口不得关闭整个导入 sheet。

### 5.6 扩展侧

- Share Extension：prepare + 自动 low-latency 重试一次（`#available(iOS 26.4, *)`）；最终失败用弹窗（重试 / 关闭扩展），移除模块内的“重新翻译”按钮。
- Translation Provider：整句与拆解词都先 prepare，并在首次失败后自动 low-latency 重试一次；最终失败用弹窗（重试 / 退出组件），**模块内不新增按钮**；拆解词失败不再静默吞掉。

## 6. 失败模式与回滚

| 失败模式 | 检测 | 处理 |
| --- | --- | --- |
| 删除 modifier 后 pbxproj 引用断裂 | 三个 Scheme 构建 | 恢复文件引用或改用保留文件空实现；不影响行为 |
| 单会话顺序执行导致总耗时变长 | 模拟器/真机冒烟 | 文档先完成即展示；chip 后置，不阻塞选词 |
| prepare 触发下载弹窗被用户拒绝 | 映射为 `.needsLanguageDownload` | 保留现状文案与重试；不阻塞保存 |
| low-latency 重试仍失败 | 单元测试 + 真机清单 | 进入可重试终态；不再无限循环 |
| 扩展 target 编译不支持 `preferredStrategy` | Release 构建 | 用 `#available(iOS 26.4, *)` 守卫；否则退回默认配置重试 |
| 真机仍偶发失败（无法本地复现） | 真机手工清单 | 保留日志点；按 run-log 记录，不宣称已彻底修复 |

回滚策略：按任务小步提交；任一里程碑失败可回退到上一个 checkpoint，三件套记录原因。

## 7. 里程碑与验收证据

### M1 — 主 App 核心修复（T01–T06）

验收：

- 新增/更新测试全绿；
- 导入页只有一个 `.translationTask`；
- 测试证明：prepare 先于 translate；文档失败后 chip 仍翻译；弹窗“重试”重启文档+缺失 chip 且不重做已完成文档；重试保留已有译文。

### M2 — 扩展侧一致性（T07–T09）

验收：

- Share Extension / Translation Provider 源码均先 prepare，并有自动 low-latency 重试与统一失败弹窗；
- 两个扩展 Scheme Debug/Release 构建通过。

### M3 — 文档与端到端验证（T10–T12）

验收：

- Fallback Matrix 更新；
- 全量 `115+` 测试 0 失败；
- 三个 Scheme Release 构建通过；
- 模拟器文本导入冒烟截图与日志（披露“模拟器不支持真实 Translation”）；
- 真机清单落盘。

## 8. 熔断与高风险

- 熔断：同一修复连续失败 3 次 → 停下写 failure 诊断，等人指示。
- 高风险操作：本计划**不涉及** schema、删数据、CI/CD、新依赖、对外请求。删除一个未被引用的 Swift 文件 + pbxproj 引用属于可构建验证的普通改动。

## 9. 设计方向

- 不改变现有导入页层级、卡片、CTA。
- **模块内部不新增任何按钮**；所有终态错误统一走系统弹窗，重试放在弹窗主按钮上。
- 弹窗只在自动兜底仍失败后出现一次；没有“暂不翻译”旁路，只有重试或取消导入。
- 终态必须有可见文案 + 可执行动作（弹窗），符合 `docs/design/import-pipeline/05-fallback-matrix.md`。

## 10. 已知限制

- 当前机器只有 iOS 模拟器（iPhone 17 Pro / iPhone Duo Test），没有可用真机；模拟器不支持 Translation API。
- 因此“真机上首次导入是否还需要重试”只能由用户按 `docs/tasks/issue-22/real-device-checklist.md` 验证；本轮不会把模拟器结果冒充真机证据。

## 11. 测试环境与机型（2026-11-15 18:30 更新）

| 项 | 现状 |
| --- | --- |
| Xcode | 27.1 (27A9275) |
| 已安装 iOS Runtime | 初始仅 iOS 27.1；**现已安装 iOS 27.0 (24A434)** |
| iOS 27.0 支持的设备类型 | 包含 `iPhone 17 Pro` |
| 当前可用模拟器 | **iPhone 17 Pro**，UDID `55DBFA05-48DE-453C-8871-288A22D251F3`，iOS 27.0（Booted）；iPhone Duo Test，iOS 27.1（Booted） |
| 本机旧 iPhone 17 Pro 模拟器 | UDID `30FBCCE6-...` 仍绑定 iOS 26.4 runtime（未改动）；用新建的同名 iOS 27.0 设备替代 |
| 项目 Deployment Target | 27.0；可运行在 iOS 27.0 / 27.1 模拟器 |

结论：

- 独立 agent 已通过 `xcodebuild -downloadPlatform iOS -buildVersion 27.0` 安装 iOS 27.0 runtime，并创建 iPhone 17 Pro 模拟器。
- 自动化测试已切换到 iPhone 17 Pro（iOS 27.0）：126 tests / 0 failures。
- 模拟器冒烟在 iPhone 17 Pro 上确认单一“暂不支持翻译 / 知道了”弹窗、无模块内重试按钮；由于新建 iOS 27.0 runtime 的系统词典资源尚未就绪，出词/保存冒烟仍由 iPhone Duo Test（iOS 27.1）覆盖。
- 真机 Translation 能力仍以 `docs/tasks/issue-22/real-device-checklist.md` 为准；模拟器不验证真实翻译。
