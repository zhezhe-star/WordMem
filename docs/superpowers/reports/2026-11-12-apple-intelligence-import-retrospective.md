# Apple Intelligence 单词导入 — 复盘报告

- **日期**：2026-11-12
- **任务**：Issue #20「Apple Intelligence 翻译功能调研」及导入流程落地
- **分支**：`feature/foundation-model-candidate-curation`
- **最终提交**：`d6d572e`
- **状态**：已完成并合入 `main` / `release/testflight`

## 1. 目标与结果

目标是把 Apple Intelligence 接入 WordMem 的单词导入流程，同时不破坏原有的翻译、拆词和保存能力。最终结果：

- Foundation Models 从“硬依赖”改成“可选增强”；
- 原有确定性拆词 + 功能词过滤 + 系统词典校验作为永久兜底；
- 翻译从高保真策略自动回退到低延迟/传统策略；
- 文本导入交互完成一轮 UI/UX 收口，并落地 Superdesign 设计稿；
- 最终 **115 tests, 0 failures**，三个 Scheme Release 构建通过。

## 2. 关键时间线

| 阶段 | 发生了什么 | 结果 |
| --- | --- | --- |
| 初始调研 | 梳理 Translation / Foundation Models / 导入管线 | 确认 FM 适合做语义筛选，不适合作为翻译主通路 |
| 管线落地 | Canonical Document、Vision OCR、Translation Engine、Review UI | 导入从字符串拼接升级为结构化文档管线 |
| FM 接入 | 用 Foundation Models 做候选词筛选 | 初期把 FM 变成了唯一筛词入口 |
| 真机反馈 | 用户遇到转圈、空白、候选词不出现 | 暴露“AI 失败即整条流程不可用” |
| 回退重构 | 恢复确定性过滤，FM 只做收窄 | AI 失败仍可出词、可选、可保存 |
| 交互修正 | 去除额外按钮、收起键盘自动整理、无候选空状态 | 形成无新增按钮的完整闭环 |
| 设计收口 | Superdesign 6 页流程稿 + 视觉细节落地 | 设计稿与代码基本对齐 |
| 验证合并 | 测试、Release 构建、模拟器截图、推送 | `d6d572e` 合入 main / release |

## 3. 做对了什么

1. **真机反馈驱动定位**  
   没有继续在模拟器里猜，而是用真机截图、`availability=` 日志和超时现象定位到 FM 可用性与结构化输出问题。

2. **独立 QA 与红绿测试**  
   QA agent 复核了生命周期、失败态和 UI 终态；关键修复都有先红后绿的回归测试，例如终态文案渲染、FM 失败回退、翻译顺序。

3. **确定性兜底最终落地**  
   把“先拆词 + 过滤 + 词典校验，再让 FM 收窄”作为基线，AI 只做减法，不做加法。这是本次最重要的架构修正。

4. **交互先做减法**  
   最终没有新增「整理内容」按钮，而是复用“收起键盘”这个已有动作触发整理；保存仍然只走原有的「导入 N 个单词」。

5. **设计与实现同源**  
   Superdesign 的 6 页流程稿直接约束了 sheet 高度、键盘行为、空状态、badge、骨架卡和 toast，减少了反复试错。

## 4. 暴露的问题与根因

### 4.1 把 AI 做成了强依赖

**现象**：FM 不可用、超时或返回空时，导入页没有候选词，用户认为“完全无法使用”。

**根因**：

- 为了强调“由模型判断”，删除了原有确定性候选过滤；
- `curator` 失败直接进入 `.curatorUnavailable`，没有 fallback；
- 只测试了 stub 成功/失败状态，没有把“失败后仍可用”当作产品契约。

**修正**：恢复确定性基线，FM 失败时直接使用该集合；FM 成功时也只能在基线内做删除。

### 4.2 失败文案被 UI 隐藏

**现象**：真机上既没有候选词，也没有“暂时无法整理候选词”的提示。

**根因**：`ImportInlineStatusView` 只在 `isError` 或 `showsProgress` 时渲染文本；终态两者都不满足，整段文案被隐藏。

**修正**：文案始终渲染，只有 spinner 是条件显示；新增渲染回归测试，旧代码下会失败。

### 4.3 可选翻译阻塞了核心流程

**现象**：翻译可用性检查或翻译任务慢时，拆词也迟迟不开始。

**根因**：`prepare` 先 `await session.checkAvailability()`，再准备候选词；翻译卡住会拖住整条链路。

**修正**：先出候选词，再检查/启动翻译；翻译失败只影响译文卡，不影响选词和保存。

### 4.4 高保真翻译是单策略

**现象**：高保真策略不可用时，翻译直接失败，尽管传统翻译可能可用。

**根因**：可用性检查和 `TranslationSession.Configuration` 都只使用 `.highFidelity`。

**修正**：可用性检查回退到默认策略；运行时失败自动用 `.lowLatency` 重试一次；chip 翻译同样回退。

### 4.5 交互上先加了按钮，后来才做减法

**现象**：为区分“收键盘”和“确认”，新增了「整理内容」按钮，用户认为按钮过多。

**根因**：把“确认”理解成一个新的显式动作，而不是复用已有动作。

**修正**：移除按钮；收起键盘即开始整理；整理是预览，不保存、不关闭 sheet；唯一保存入口仍为原有的「导入 N 个单词」。

### 4.6 模拟器无法验证真实 AI 能力

**现象**：模拟器测试通过，但真机 FM 仍失败。

**根因**：模拟器 `SystemLanguageModel` 返回不可用，测试只能覆盖失败兜底，不能覆盖真实模型延迟、输出质量和可用性。

**修正**：明确“模拟器只验证生命周期和兜底，真机验证模型能力”的边界；补充真实 curator 在模拟器上的回退测试。

## 5. 可复用原则

1. **AI 是增强层，不是流程入口。**  
   任何 AI 组件都必须有确定性基线；AI 失败时用户仍能完成任务。

2. **AI 只能做减法，不能做加法。**  
   模型只能在既有候选集中删除低价值词，不能引入新词、功能词或重写原文。

3. **区分“处理预览”和“提交保存”。**  
   自动整理可以发生，但保存必须显式；整理不能关闭 sheet，也不能写词书。

4. **优先复用已有控件，不新增主按钮。**  
   新增按钮前先问：能否用已有手势、键盘动作或现有 CTA 完成同一件事？

5. **测试视图状态，不只测试模型状态。**  
   `reviewStatusMessage` 有值不等于用户能看到；终态渲染必须有回归测试。

6. **可选增强不能阻塞核心路径。**  
   翻译、AI 拆词、词典建议都应后置；候选词和保存路径必须独立可用。

7. **真机能力必须单独定义验收。**  
   模拟器不能证明 Foundation Models、翻译包和 Apple Intelligence 可用性；需要真机 TestFlight 清单。

## 6. 流程改进建议

1. 在 `docs/design/import-pipeline/01-technical-design.md` 增加 **Fallback Matrix**：每个增强能力失败时的用户可见行为和测试要求。
2. 在导入相关 PR 模板中增加三问：
   - AI/翻译失败时是否仍可完成导入？
   - 终态文案是否有视图级测试？
   - 是否新增了可以复用现有控件的按钮？
3. 建立真机验收清单：FM 可用性、模型准备状态、翻译语言包、低电量模式、长文本延迟。
4. 对旧文件做一次 `swift-format` 基线清理，避免 4-space/2-space 混用导致 lint gate 只能按文件选择性执行。
5. 设计阶段先出 Superdesign 流程稿，再改代码；把“无新增按钮”作为交互评审的默认约束。

## 7. 验证证据

- 全量测试：**115 tests, 0 failures**
- Release 构建：
  - `WordMem`
  - `WordMemShareExtension`
  - `WordMemTranslationProvider`
  - 全部 `BUILD SUCCEEDED`
- 模拟器日志：
  - `availability=modelNotReady`
  - `fallback deterministic candidateCount=3 tokenCount=4`
- UI 证据：
  - `docs/evidence/import-ui-review/`
  - `docs/evidence/import-ui-design/`
- 设计稿：
  - `https://superdesign.dev/teams/e895d94f-bdd8-41b0-aaf2-d6ec07e75d72/projects/69299388-9550-43ea-a17e-61ac8ba27bf4`

## 8. 遗留事项

- 真机 TestFlight 复测：Apple Intelligence 拆词、翻译语言包、长文本延迟。
- GitHub issue #20 仍为 OPEN，可在真机验收后关闭。
- `WordPresentationViews.swift` / `ImportCandidateModels.swift` 等旧文件仍是 4-space 风格，未做全文件格式化。
- 长文本 FM 请求仍可能超时；当前兜底已保证可用，后续可考虑分块或限制输入长度。
- `EN → 中文` badge 目前按当前产品语言对固定展示，未来多语言导入时需要动态化。

## 9. 一句话总结

这次最大的收获不是“接入了 Apple Intelligence”，而是明确了 **AI 只能增强、不能成为单点依赖**；把它放回可选层之后，导入流程才真正达到可发布状态。
