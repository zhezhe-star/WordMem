# AGENTS.md — WordMem

## Orca 流程约定

本仓库使用**指针模式**：Orca 协议和 toolkit skills 只从唯一权威路径读取，
不在本仓库保留 `.claude/skills/orca-*` 副本。devflow 更新（`~/dev-flow` 合并
main 后由 post-merge hook 自动分发到 `~/.orca/devflow`）对所有接入项目即时生效，
本仓库无需任何逐项目升级动作。

识别方式：仓库根目录同时存在 `plan.md`、`checklist.yaml`、`run-log.md`
三个文件。

开始 Orca 任务前必须先读 `~/.orca/devflow/ORCA-PROTOCOL.md`
（自动分发的唯一权威路径，勿在本仓库复制协议内容）。当前版本见
`~/.orca/devflow/VERSION`。

## 构建与测试

- 全量测试：`xcodebuild test -project WordMem.xcodeproj -scheme WordMem
  -destination 'platform=iOS Simulator,id=55DBFA05-48DE-453C-8871-288A22D251F3'`
  （iPhone 17 Pro, iOS 27.0；iPhone Duo Test 为 iOS 27.1 备选）。
- 三个 Scheme（WordMem / WordMemShareExtension / WordMemTranslationProvider）
  需分别构建验证；Release 用 `xcodebuild archive -destination
  'generic/platform=iOS Simulator'`。
- 模拟器不能运行真实 Translation API：翻译功能只能真机/TestFlight 验证，
  判读方法见 `.claude/skills/translation-device-ladder`。

## TestFlight 发布

- 流程见 `docs/testflight-release.md`：push 到 `release/testflight` 触发
  Xcode Cloud `TestFlight Beta` workflow。
- ⚠️ 同 SHA 重推不会触发构建（GitHub 不产生 push 事件）；webhook 可能静默
  丢失——推送后 5–10 分钟内用 ASC API 确认构建确实启动：
  `swift ~/.appstoreconnect/asc-api.swift "/v1/ciProducts/7514a0e4-0655-4a40-877c-bbba4902deff/buildRuns?limit=10"`
  （详见 `.claude/skills/xcodecloud-trigger`）。
- Xcode Cloud 手动 API 启动固定打默认分支（main），无法指定 release/testflight。
