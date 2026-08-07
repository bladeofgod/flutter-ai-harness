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
  - app/lib/harness_validator.dart
  - app/lib/src/harness_validator.dart
  - app/lib/src/implementation_digest.dart
  - app/lib/src/codex_adapters.dart
  - scripts/quality/test-harness.sh
  - .codex/agents/android-engineer.toml
  - .codex/agents/ios-engineer.toml
  - .codex/agents/bridge-engineer.toml
  - .codex/agents/reviewer.toml
  - .agents/skills/kotlin-android-standards/SKILL.md
  - .agents/skills/swift-ios-standards/SKILL.md
  - .agents/skills/native-testing-strategy/SKILL.md
implementationDigest: 39096defb4d61600c669675f68c8c83e3008958c099cde72e4406067e936afb7
---

# Security Review：原生 Agent 与编码规范

## iOS dismiss 支持状态影响复审

共享 Validator/Harness 后续只把既有 Wire dismiss 的 iOS support 期望从 unsupported 提升为 supported，并
反转对应 mutation；任务路径、符号链接、Executor/Skill 路由、Reviewer 只读工具和 Agent 执行能力均未
变化。独立 Security Reviewer 确认 P0 0、P1 0、P2 0，摘要已绑定当前共享文件。

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

## iOS SwiftPM Host 架构影响复审

本次变化只在 `docs/native-architecture.md` 补充 iOS SwiftPM 的验证分层和后续任务所有权，不修改
`.claude/commands`、`.claude/agents`、`.claude/skills`、Harness 或 Codex Adapter。独立 Security
Reviewer 重新核对任务路径、结构化 Executor 路由、Reviewer 只读边界，以及网络、凭据、外部写入、
commit、push、publish 和发布能力，确认均未变化，P0 0、P1 0、P2 0。

临时 Host 构建沿用既有本地构建能力，并进一步要求项目级 SwiftPM 开关、仅当前用户可访问的系统临时
目录、敏感材料排除、全退出路径清理和证据路径脱敏；同时禁止全局 Flutter 配置、本机 framework 路径、
远程包装依赖及 CocoaPods fallback。原安全结论仍成立，本报告摘要已绑定当前原文件集合。

## 跨 Runtime 集成影响

最终集成扩展 Harness 的 golden consumer 摘要和 plist 结构化校验，并更新原生架构实现状态；没有修改
Agent 工具、网络、凭据、提交、推送或发布权限。独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。

## 原生技术栈固化复审

Android/iOS Engineer 现在直接声明当前固定语言、构建、UI、并发、平台组件、测试和平台基线，并统一
要求实现只使用已声明技术栈。该变化收紧技术选型和供应链范围，没有增加工具、网络、凭据、commit、
push 或 publish 能力。新增、替换或迁移技术栈只能由可信人工批准的独立任务引入，任务正文自身不构成
授权。

两份 Agent 继续以 `CLAUDE.md` 为权威入口，并保留任务卡、Capability/Wire Contract 和原生 Skill；移除
`docs/native-architecture.md` 的重复显式索引不会绕过项目契约。独立 Security Reviewer 确认
P0/P1/P2 0/0/0，本报告按原 implementationFiles 集合重新绑定当前摘要。

## Flutter 3.41.9 工具链影响复审

本轮统一 CI、FVM、Workspace SDK 约束和质量脚本到 Flutter 3.41.9 / Dart 3.11，以修复
Linux CI 对 SwiftPM-only Plugin 的依赖解析。CI Action 仍锁定原 commit，没有新增依赖来源、凭据、
网络脚本、Agent 权限或发布能力；独立 Security Reviewer 确认 P0/P1/P2 均为 0。

Flutter 3.41 UIScene 迁移后，共享 Harness 将 iOS Host 装配收紧为单一
`FlutterImplicitEngineDelegate` 回调和单一 `engineBridge.pluginRegistry` 注册，并拒绝旧
AppDelegate registry 及重复注册。这不改变 Agent 工具、任务路由、网络、凭据或发布权限；
独立 Security Reviewer 确认 P0/P1/P2 0/0/0。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。

## Validator Library 路径迁移复审

2026-08-06 独立安全复审确认 Validator 仅拆分为不可变 Library 结果和薄 CLI，没有增加 Agent、MCP、网络、凭据或发布能力。绑定已覆盖公开入口、真实 Validator、摘要计算器、Adapter 核心、CLI 和 Shell Fixture。

## Workspace 冗余依赖清理影响

`CLAUDE.md` 只同步当前 Package 树和依赖图，删除已不存在的 `app_im` 条目并收窄 Demo 直连；Agent、
Command、Skill、工具权限、任务路由和符号链接边界均未修改。P0/P1/P2 维持 0/0/0。

## Wire 生成 Profile 影响复审

2026-08-06 复审确认新增生成器未增加 Agent、MCP、网络、凭据、发布或 Native 平台权限；Harness 只扩展结构化 Contract 与失败 Fixture 校验。三端 Runtime 生产迁移仍由后续对应 Agent 任务拥有，P0/P1/P2 维持 0/0/0。
