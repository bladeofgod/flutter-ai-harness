---
task: native-harness-agent-standards
status: passed
p0: 0
p1: 0
---

# Review：原生 Agent 与编码规范

## 结论

最终 Review 通过，P0 0、P1 0，未发现剩余 P2。Android、iOS、Bridge 与通用任务的
结构化分流、平台 Skill、只读 Reviewer 边界和任务入口校验均与任务卡一致。

## 首轮问题与修复

### 1. 合法 Executor/工作类型组合覆盖不完整

首轮 Fixture 没有证明全部 11 个 `workKinds`、四种 Executor、双平台质量门禁、
Bridge Contract、Flutter/Dart Client 和文档平台组合都能通过。修复后改为表驱动合法矩阵，
同时保留字段缺失、未知值、重复值和所有权冲突的失败用例。

### 2. 平台 Engineer 的 Skill 组合缺少精确不变量

首轮只校验 Skill 引用存在，不能阻止平台 Engineer 同时加载错误平台 Skill 或漏掉
`native-testing-strategy`。修复后 Harness 精确要求 Android Engineer 使用
`kotlin-android-standards` 与 `native-testing-strategy`，iOS Engineer 使用
`swift-ios-standards` 与 `native-testing-strategy`。

## 复审问题与修复

### 1. iOS Engineer 的 Skill 失败路径缺少 Fixture

第一轮修复只对 Android Engineer 覆盖 `skills` 缺失、错平台和缺少原生测试 Skill。
修复后两个平台共用表驱动负向测试，三类错误在 Android/iOS 上都会被拒绝。

### 2. `docs/tasks` 根目录链接可绕过文件级检查

后续审查发现仅拒绝任务文件链接不足以覆盖任务根目录链接。首版修复又因目录路径尾部斜杠
导致 `typeSync(..., followLinks: false)` 仍跟随仓库内链接。最终实现对无尾斜杠的 `docs` 和
`docs/tasks` 词法路径逐级检查节点类型，再校验真实路径位于仓库内；Fixture 覆盖任务文件及
任务根目录分别指向仓库内、仓库外的场景。

## 已确认项

- Android/iOS Agent 只获得实现所需工具，未获得提交、推送、发布、凭据或无约束网络能力。
- 普通 Reviewer 与 Security Reviewer 的生成适配都保持 `read-only` sandbox。
- `platforms`、`workKinds` 与 Executor 的路由只读取 frontmatter，不从文件名或正文猜测。
- 活动任务强制新 Schema，未声明新字段的历史归档任务继续兼容。
- Claude Agent/Skill 事实源与 Codex Adapter 已同步，Skill `paths` 由 Harness 直接校验。

## 验证

[测试证据](test-evidence/native-harness-agent-standards.log) 保留了修复过程中的失败记录；日志
最后一轮 `make format`、`make harness-check`、`make harness-test` 和 `git diff --check`
均为退出码 0。此前完整成功轮还覆盖 `make codex-adapters`、
`make codex-adapters-check`、`make analyze` 与 `make lint`。

最终独立复审未重新执行命令，基于当前实现、完整 diff 与最后一轮成功证据确认通过。
