# 默认翻译 App 集成验证证据（issue #5）

本目录记录 WordMem 注册为系统「默认翻译 App」（iOS 18.4+ TranslationUIProvider）
后在模拟器（iPhone 17 Pro / iOS 26.4）上的端到端验证截图。

## 流程

1. `01_settings_default_translation_app.png` — 设置 → App → WordMem → 默认翻译 App，
   当前值已是 WordMem，系统已将 WordMem 识别为翻译服务候选。
2. `02_safari_selection_callout.png` — Safari 中长按选中单词，系统菜单出现「翻译」。
3. `03_wordmem_translation_card.png` — 点「翻译」后系统弹出 WordMem 翻译卡片：
   原句 + 翻译 + 「导入到 WordMem」（对照欧路「新词」体验复原）。
4. `04_word_picker_chips.png` — 点「导入」后进入选词页：取消 / 英文 / 保存，
   整句与逐词 chip 可勾选，保存写入 App Group 单词本。

## 验证

- XCUITest `SafariTranslateTests`（外置驱动工程）全流程通过：选词 → 翻译 → 卡片 →
  选词 → 保存，App Group `group.com.zhezhe.wordmem` 中 `saved_words` 正确写入。
- 分享扩展路径（share extension）回归通过：`DriveTests` 通过，单词本去重覆盖正常。
- 单元测试 4/4 通过（`LocalStorageManager` 持久化/迁移）。

## 已知模拟器限制

- 模拟器运行时未预置英→中翻译语言包，系统翻译组件返回失败；卡片按设计降级为
  「翻译不可用」提示并允许直接选词保存（释义可稍后在 App 内补充）。
  真机安装语言包后，卡片会自动填充整句与逐词释义。
- 模拟器系统翻译服务偶发在重启后丢失候选注册；重装 App 后即恢复。
