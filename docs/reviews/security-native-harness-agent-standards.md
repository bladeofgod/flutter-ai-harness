---
task: native-harness-agent-standards
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - .claude/agents/architect.md
  - .claude/agents/android-engineer.md
  - .claude/agents/ios-engineer.md
  - .claude/agents/bridge-engineer.md
  - .claude/agents/task-executor.md
  - .claude/agents/reviewer.md
  - .claude/commands/plan-tasks.md
  - .claude/commands/execute-tasks.md
  - .claude/commands/fix-review-findings.md
  - .claude/commands/review-changes.md
  - .claude/skills/kotlin-android-standards/SKILL.md
  - .claude/skills/swift-ios-standards/SKILL.md
  - .claude/skills/native-testing-strategy/SKILL.md
  - CLAUDE.md
  - docs/native-architecture.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
  - .codex/agents/android-engineer.toml
  - .codex/agents/ios-engineer.toml
  - .codex/agents/bridge-engineer.toml
  - .codex/agents/reviewer.toml
  - .agents/skills/kotlin-android-standards/SKILL.md
  - .agents/skills/swift-ios-standards/SKILL.md
  - .agents/skills/native-testing-strategy/SKILL.md
implementationDigest: 3e4e9f9e5e8db28c325b117a31573bb9d6f7a8b6691cd3975beb8c33629803ca
---

# Security Review：原生 Agent 与编码规范

## 结论

最终 Security Review 通过，P0 0、P1 0、P2 0。审查范围覆盖 Agent/Command/Skill 的执行
能力、任务输入信任边界、生成适配和对应 Harness/Fixture。

## 发现与修复

### 1. 任务文件符号链接可越过仓库边界

首轮发现执行命令只验证任务路径存在，Harness 又会跳过链接节点，可能让指向仓库外的任务卡
进入具备写入和 Bash 能力的 Executor。修复后活动任务必须是直属 `docs/tasks/<kebab>.md`
普通文件，Harness 拒绝仓库内外任务文件链接与特殊节点。

### 2. 任务根目录符号链接仍可绕过文件级约束

复审发现 `docs/tasks` 本身被替换为链接时，目标中的普通文件仍可能进入校验。最终实现逐级
拒绝 `docs`、`docs/tasks` 路径组件链接，并校验解析后的任务根仍位于解析后的仓库根内；
`execute-tasks` 同步声明从仓库根到任务文件的所有组件均不得为链接。Fixture 覆盖任务根指向
仓库内和仓库外两类失败路径。

## 已确认项

- Android/iOS Engineer 的工具集合限定为 `Read`、`Write`、`Edit`、`Bash`、`Grep`、
  `Glob`，并显式禁止提交、推送、发布、读取凭据和无约束外部网络。
- 普通 Reviewer 和 Security Reviewer 均无 Bash 或写入工具，调用工作流负责提供只读命令证据。
- Executor 只按受校验的结构化任务元数据分流，不从不可信正文推断执行角色。
- Codex Adapter 由事实源生成且受漂移检查约束，未手工扩大生成端能力。

## 验证

[测试证据](test-evidence/native-harness-agent-standards.log) 的最后一轮
`make harness-check`、`make harness-test` 和 `git diff --check` 均为退出码 0；历史失败记录
保留用于说明修复过程。最终安全复审只读检查当前实现与证据，未发现剩余安全问题。

## 后续共享门禁复审

Media Capture Capability 任务扩展了共享 `harness_check.dart` 与 Harness Fixture，因此本报告的
实现摘要同步更新。对应的独立 [Security Review](security-media-capture-capability-contract.md)
重新检查了任务入口符号链接防护、Executor/Skill 精确路由以及 Reviewer 只读边界，确认本任务
建立的安全不变量没有回归。

后续 Media Capture Bridge Contract 再次扩展了相同共享门禁。其最终独立
[Security Review](security-media-capture-bridge-contract.md) 复核了任务符号链接、结构化路由、
平台 Skill 和 Reviewer 只读边界，仍未发现本任务安全不变量回归；本报告摘要据此同步到当前实现。

后续 Thumbnail Capability V2 又扩展共享 Harness 与失败 Fixture。最终独立 Security Review 重新核对
task path、Executor/Skill 路由、Reviewer 只读边界、Security Review implementation binding/digest
与 Agent 能力限制，确认没有回归；本报告摘要同步到当前实现。

后续 `media-capture-flutter-package-registration` 只在 `CLAUDE.md` 同步真实 Workspace Package 目录和
允许依赖图，没有改变 Agent 工具、任务路由、命令能力或不可信任务输入处理。独立 Security Reviewer
确认原结论仍成立，本报告据此使用全部 implementation file 重新计算摘要。本轮没有重跑原任务的
`harness-check`、`harness-test` 或 `git diff --check`，不把历史结果表述为本轮新证据；新增 Plugin
discovery 门禁由后续任务自己的 Security Review 和 evidence 负责。

## 当前实现复审

独立只读复审重新检查 Android/iOS/Bridge/Task Executor 职责、Reviewer 只读边界、命令不授予
commit/push/publish/凭据能力、Skill 路由和安全审查门禁。当前实现未发现 P0、P1 或 P2，摘要可同步到
当前文件集合。本轮未执行 `codex-adapters-check` 或 `harness-check`，门禁结果由后续证据记录。

## V4 Harness 最终复审

独立安全复审确认共享 Harness 的 V4 projection 校验和临时 mutant 不增加 Agent 权限、网络、发布、
凭据或持久写入能力。当前实现 `P0=0`、`P1=0`、`P2=0`；摘要已绑定最终 Agent/Command/Skill 与
共享 Harness，最终 `harness-check` 由本批任务证据记录。

## Presentation Dismiss Harness 复审

本轮共享 Harness 只增加一个精确 Wire-only lifecycle method 白名单、历史 V2 投影移除规则和恶意
fixture，不改变 Agent 工具、网络、凭据、提交、推送或发布能力。任务 executor/platform/workKind 的
确定性路由、任务路径 symlink 防护和 Reviewer 只读边界仍由完整 Harness mutant suite 覆盖；最终
`make harness-test` exit 0，本报告摘要同步到当前文件集合。
