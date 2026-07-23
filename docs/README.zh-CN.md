# Flutter AI Harness

[English](../README.md)

面向生产级 Flutter 与混合移动应用仓库的 AI 原生工程 Harness。

Flutter AI Harness 是一套仓库模板，适用于希望让 AI 编码 Agent 在明确、可测试工程边界内工作的团队。它将项目契约、任务规划、专业 Agent 角色、可复用 Skill、审查流程和可执行质量门禁组合在一起，适用于 Flutter Monorepo，也支持同时长期维护 Android 和 iOS 原生代码的混合工程。

本项目用于帮助 AI Agent 参与应用工程开发，不是在 Flutter App 内集成 AI 功能的运行时 SDK。

## 提供的能力

- Harness 原生支持 Claude，并为 Codex 提供由 Claude 事实源生成的适配层。
- 从同一套 Claude Command、角色和 Skill 事实源生成 Codex 原生 Skill 与 Agent 适配。
- 提供任务规划、Figma 拆解、任务执行、代码审查和发版检查工作流。
- 提供架构、实现、测试、原生 Bridge、审查、资源和 App 操作等专业角色。
- 按任务加载 Dart、GetX、go_router、测试、Protobuf、UI、性能和平台相关 Skill。
- 用仓库内 Git hooks 和 lint 脚本把架构规则变成可执行门禁。
- 通过分层 Flutter Workspace 阻止 Proto Message 和数据库 Row 泄漏到公共接口。
- 为 Android、iOS 提供契约优先的 MethodChannel/EventChannel 规范。
- 提供项目级 Marionette MCP 配置，用于检查和操作运行中的 Debug App。
- 提供从 `spec-writer`、静态审计到 Marionette 执行的可 Review UI 行为 Spec 流程。
- 提供包含仓库检查与 Android/iOS Debug 构建的 GitHub CI，以及依赖来源门禁，保证公开 Clone 可复现。

## 仓库模型

```text
flutter-ai-harness/
├── AGENTS.md               Agent 入口
├── CLAUDE.md               权威项目契约
├── .claude/                Command、Agent、Skill 和可复用 Memory
├── .agents/                生成的 Codex 原生 Skill 适配
├── .codex/                 生成的 Codex 原生项目 Agent 适配
├── docs/                   架构与工作流文档
├── scripts/                Git Hooks 和可执行质量门禁
└── app/                    包含 Ai-Harness Demo 的 Flutter Workspace
```

规划的 Package 依赖方向如下，`A -> B` 表示 Package A 可以 import Package B：

```text
apps/demo -> app_features, app_data, app_im, app_core, app_ui
app_features -> app_data, app_im, app_core, app_ui
app_data / app_im -> app_core
app_core / app_ui -> 不依赖其他 Workspace Package
```

## 工作流

```text
产品输入或 Figma
        ↓
拆分任务
        ↓
执行单张任务卡
        ↓
静态分析与测试
        ↓
只读审查 → 显式修复 → 复审
        ↓
归档证据和决策
```

仓库已经包含一套通过 Harness 实际迭代完成的 Shoppe 风格 `Ai-Harness` Demo。任务卡、Review、App 文档和 Memory 都来自真实使用过程，让仓库展示真实工作流，而不是预先编造的示例历史。

未完成任务卡直接放在 `docs/tasks/`，完成后移动到 `docs/tasks/done/`。任务卡可以由开发者、Agent、Command 或其他工具创建；文件使用清晰、能概括内容且全局唯一的 lowercase kebab-case slug，无需编号、生产者前缀或指定规划入口。普通任务只负责实现、聚焦测试、只读审查、显式修复和证据归档。UI 自动化由人独立安排：`/plan-spec` 生成独立行为契约，`/execute-ui-spec` 只对人明确选择的平台执行静态审计和 App Operator。Spec、Audit 和 Run 不作为普通任务门禁，也不随任务归档。实现证据和 Review 结论随任务归档，只有长期有效的项目知识才写入 `.claude/memories/`。

## 质量门禁

> **提示：** 以下命令用于说明仓库提供的质量门禁，并不要求开发者在每次修改后手工执行全部命令。使用 Harness 工作流时，Agent 会根据任务影响范围选择并运行相关检查；已安装的 Git Hooks 和 CI 会在对应时机自动触发。人工操作主要用于首次环境准备，以及依赖设备、本地 MCP 授权或其他外部环境的验证。

开发时运行受影响的聚焦检查，交付前运行完整门禁：

```bash
make format
make analyze
make test
make integration-test INTEGRATION_DEVICE=<device-id>
make spec-check # 仅在创建或校验 UI 自动化产物时执行
make lint
make harness-check
make check
```

`.claude/` 下的资产是唯一事实来源。修改 Command、Agent 或 Skill 后运行 `make codex-adapters`；`make codex-adapters-check` 会只读校验生成的 `AGENTS.md`、`.agents/skills/` 和 `.codex/agents/`，不会修改文件，仓库 `pre-push` Hook 会自动执行这项轻量检查。Codex 通过 `$skill-name` 或语义匹配调用生成的工作流 Skill，Claude 继续使用 `/command` 入口。

任务证据必须通过 `scripts/quality/capture-evidence.sh` 采集；它会记录命令和退出码，并脱敏本机路径与常见凭据形态。`make setup` 会为每个 Clone 安装仓库 Git Hooks；如果当前 Clone 已配置其他 `core.hooksPath`，Setup 会报告冲突并保留原 Hook 工具链，不会静默覆盖。

## 快速开始

前置环境：Claude Code 2.1.198 或更高版本、`ripgrep`，以及推荐的 FVM；不使用 FVM 时需预先安装 Flutter 3.35.7。

macOS 使用 `brew install ripgrep` 安装；Ubuntu/Debian 使用 `sudo apt-get update && sudo apt-get install --yes ripgrep` 安装。`make setup` 会在 Bootstrap Workspace 前检查该依赖。

```bash
git clone https://github.com/bladeofgod/flutter-ai-harness.git
cd flutter-ai-harness
make setup
make check
```

`make setup` 会在 FVM 可用时安装 `app/.fvmrc` 锁定的 Flutter，否则校验系统 Flutter 版本；随后解析 Pub Workspace、Bootstrap Melos Package，并安装仓库内 Git Hooks。首次使用 Marionette 时额外运行 `make marionette-install`。

仓库中的 `Ai-Harness` Demo 是一套 Shoppe 风格的本地电商演示，包含 Welcome、Auth、Shop、Categories、Wishlist、Cart、Profile、Settings、Orders、Search、Promotions、Rewards、Support 和 Product Detail 流程。它使用确定性本地 Fixture 与 Mock API，不依赖远程后端，便于展示架构和交互。可通过 `TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh run` 启动。`com.example` 应用标识只是模板占位，发布前必须替换。

Figma 工作流使用项目级 Desktop MCP 配置。先在 Figma Desktop 打开设计文件，在 Dev Mode 中启用 Desktop MCP Server，再在 Claude Code 提示时批准项目的 `figma` Server。

运行态 Flutter UI 检查需要先执行 `make marionette-install`，以 Debug 模式启动 Demo，再把控制台中的 `ws://.../ws` VM Service URI 提供给 Agent。操作顺序固定为连接、检查或交互、断开。只有人在显式调用 `/execute-ui-spec` 后，工作流才会对本次选定的平台重复该流程，并分别保存经过校验且不含敏感信息的报告；普通任务执行不会启动 App Operator。Marionette 只操作 Flutter Widget Tree，不负责原生系统界面自动化。

## 当前状态

Harness 基线和第一批完整 Demo UI 已经完成。当前 Demo 任务卡均已归档到 `docs/tasks/done/`，Demo 使用本地确定性数据，不代表生产服务。Android Debug 构建和运行验证已具备；iOS 无签名构建及原生权限流程仍依赖可用的 Apple 工具链和设备环境。后续可以继续通过新的 Figma 任务卡扩展 Demo，不需要改变 Harness 契约。

## 许可证

Flutter AI Harness 使用 [MIT License](../LICENSE)。
