---
name: xcodecloud-trigger
description: 触发、查询和诊断 Xcode Cloud 构建与 TestFlight 发布。当 push 到发布分支后 Xcode Cloud 没有出构建、需要查询构建状态/进度、需要手动触发 TestFlight 发布、或需要确认 TestFlight 包是否上传成功时使用。基于 App Store Connect REST API（本机已配置签名脚本）。
---

# Xcode Cloud 触发与诊断

## 前置：ASC API 签名脚本（本机已配置）

- `~/.appstoreconnect/asc-api.swift <path-with-query>`：签名 ES256 JWT 并 GET 任意 API 路径，打印 JSON。读 stderr 的 `HTTP <code>` 判断结果。
- 密钥：`~/.appstoreconnect/private/AuthKey_<KEY>.p8`，key id / issuer 默认内置；权限不足时先查报错里的 `REQUIRED_AGREEMENTS_MISSING`（需人在 ASC 网页签协议）。
- ⚠️ p8 私钥字节不得打印进日志；调试 DER 结构时不要用 `openssl asn1parse -o` 输出原始内容。

## 本项目常量

- Product id：`7514a0e4-0655-4a40-877c-bbba4902deff`
- TestFlight Beta workflow id：`C633C94D-A1E0-4A3B-AD7A-C99DF6CD1E90`（跟踪 `release/testflight` 分支，push 触发）
- 发布分支：`release/testflight`；流程见 `docs/testflight-release.md`

## 核心事实（踩过坑验证过的）

1. **手动 API 启动构建不能选分支**：`POST /v1/ciBuildRuns` 的 `relationships.workflow` 指向 workflow 即可启动（HTTP 201），但**永远打仓库默认分支 main**。`sourceBranchOrTagName`、`inputs`（属性和关系形式）均被 409 拒绝。要构建 release/testflight → **推新提交触发**。
2. **同 SHA 重推不产生 push 事件**：GitHub 对 ref 无变化不发 webhook。要重触发就用空提交：
   ```bash
   TREE=$(git rev-parse <base>^{tree})
   C=$(git commit-tree $TREE -p <base> -m "chore(ci): retrigger")
   git push origin "$C:refs/heads/release/testflight"
   ```
3. **列构建必须走 product 集合**：`GET /v1/ciProducts/{id}/buildRuns?limit=200`（直接 GET `/v1/ciBuildRuns` 集合是 403；`sort` 参数基本都无效，取回后按 `attributes.number` 自己排序）。
4. **构建关系子路径**：`GET /v1/ciBuildRuns/{id}`（`executionProgress`/`completionStatus`：SUCCEEDED/FAILED）；`GET /v1/ciBuildRuns/{id}/builds` 看 TestFlight 包（`processingState: VALID` = 可安装）。`inputs` 关系不存在。
5. 构建 ~35 分钟；workflow 的 `manualBranchStartCondition`/`branchStartCondition` 可从 `GET /v1/ciWorkflows/{id}` 查看。

## 诊断流程（push 后无构建时）

1. `git ls-remote origin release/testflight` 确认远端 SHA；
2. 查 product buildRuns，确认最近构建的 `sourceCommit.commitSha` 与 `startReason`；
3. 若 push 后 5–10 分钟仍无新 run（webhook 静默丢失）→ 空提交重推（见上）；
4. 若必须手动 API 启动（默认分支也接受时）才用 POST ciBuildRuns；
5. 轮询直到 `completionStatus` 非空，再查 `/builds` 确认 TestFlight `VALID`。
