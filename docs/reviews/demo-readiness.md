# Demo 开发就绪审查

## 范围与结论

- 审查基线：`b446620 feat(harness): 完成 P1 基础能力闭环`
- 审查视角：从设计输入、任务规划、实现、运行调试、测试留证、Review 到发布检查的完整 Demo 开发链路
- 初审结论：未发现 P0；存在 1 个 P1 和 5 个 P2。规划生命周期 P1 和全部 5 个 P2 已在后续复审中关闭。

| 阶段 | 当前状态 | 结论 |
| --- | --- | --- |
| 全新 Clone、Bootstrap、静态门禁 | 已验证 | 可用 |
| Android Debug 构建 | 已验证 | 可用 |
| Figma 读取 | 配置已识别，等待批准和真实设计 | 外部前置未完成 |
| Demo 任务规划 | 任务 slug、活动/归档位置和关联产物契约已统一 | 可用 |
| 单元与 Widget 测试 | 已验证 | 可用 |
| Integration Test、App Operator | 标准入口与 Spec 闭环已建立 | 可用，等待首个真实流程 |
| iOS 构建 | 宿主已建立，本机 Platform/destination 不可用 | 换可用环境复验 |

## P1

### 1. 普通规划与 Figma 规划没有统一的任务产物生命周期

- 位置：`.claude/commands/plan-tasks.md`、`.claude/commands/plan-figma.md`、`app/tool/harness_check.dart`
- 影响：`plan-tasks` 和 `plan-figma` 曾分别定义 Overview、输入快照和任务卡位置，Agent 严格执行时可能覆盖已有规划文件或自行发明目录与编号。与此同时，Harness Check 只在 `executor` 已存在时校验其值，无法阻止缺少必需 frontmatter、重名或位置错误的任务卡进入执行流程。
- 证据：两个规划命令曾对同一组任务采用不同目录约定，也没有统一如何处理文件名冲突或把 Figma 快照关联到任务。
- 修法：活动任务直接使用 `docs/tasks/<task-slug>.md`，完成后移入 `done/`；Figma 输入独立放在 `docs/figma/` 并由任务显式引用；让两个规划命令复用同一任务卡 Schema，由 Harness Check 强制校验位置、slug、frontmatter、依赖和关联路径。

## P2

> 初审状态：5 项待办；当前状态见文末“P2 修复复审”。

### 2. Integration Test 没有标准运行入口

- 位置：`scripts/quality/run-tests.sh:6`、`Makefile:14`、`.claude/skills/testing-strategy/SKILL.md:15`
- 影响：默认测试发现只覆盖 `test/*_test.dart`，未来 `integration_test/` 可以存在但不会被 `make test` 或 `make check` 执行，完整门禁可能给出不完整的通过结论。
- 修法：增加显式 `make integration-test` 和设备选择约定；由任务卡与 `check-release` 按影响面调用，不把设备测试静默并入快速本地测试。

### 3. App Operator 尚未进入任务执行闭环

- 位置：`.claude/commands/execute-tasks.md:31`、`.claude/agents/app-operator.md`、`.claude/skills/ui-behavior-spec/SKILL.md`
- 影响：首个 `.spec.yaml` 出现后，流程只会执行静态 `spec-auditor`，不会自动运行 App Operator；运行报告的写入方、失败证据和通过条件也尚未定义。
- 修法：在首个真实 Spec 任务中同步定义 Schema、Operator 条件阶段、报告路径、失败证据、Teardown 和静态/运行态双重通过条件。

### 4. Quick Start 对首次开源使用者仍有环境歧义

- 位置：`README.md:64`、`docs/README.zh-CN.md:64`、`app/.fvmrc:1`、`scripts/flutter-tool.sh:8`
- 影响：公开文档使用 SSH Clone，并只把 FVM 标为推荐；脚本检测到 FVM 后会优先调用它。没有 GitHub SSH 身份或已安装 FVM 但未缓存 Flutter 3.35.7 的使用者可能在第一步被阻塞。
- 修法：公开 Quick Start 默认使用 HTTPS；明确 `cd app && fvm install`，或提供能够准备固定 SDK 的根级 Setup 入口，同时说明系统 Flutter fallback。

### 5. 远端没有持续集成门禁

- 位置：`Makefile:38`、仓库缺少 `.github/workflows/`
- 影响：本地 `make check` 已完整，但 PR、未安装 Hook 的提交和 Linux Shell 兼容性没有统一远端结果。
- 修法：模板结构稳定后增加最小 CI，锁定 Flutter 3.35.7 并执行 `make bootstrap`、`make check`；平台构建按成本拆分 Job。

### 6. 私有路径与依赖来源门禁没有覆盖未来应用代码

- 位置：`app/tool/harness_check.dart:347`、`app/tool/check_package_dependencies.dart:39`
- 影响：私有路径检查当前覆盖核心文档、`.claude/` 和少量原生配置，但不覆盖 `app/` 源码、`pubspec.yaml`、`scripts/` 与 Makefile；依赖检查只校验 Workspace Package 方向。未来 Agent 加入本机绝对路径、私有 `path` 依赖或不可复现的 Git/Hosted 依赖时，现有 Harness 门禁可能放行。
- 修法：使用 YAML 解析所有 `pubspec.yaml`，按开源策略校验 dependency source；把应用源码、脚本和构建配置纳入二进制安全的路径扫描，并为允许的相对 Workspace 依赖和禁止的本机路径增加 Fixture。

## 已验证

- 当前工作区 `make check`：通过。
- 从 Commit `b446620` 创建全新 Clone 后执行 `make bootstrap`：通过，7 个 Package 完成 Bootstrap，Git Hooks 安装成功。
- 全新 Clone 执行 `make check`：通过；格式、Analyze、Harness、架构、Hook、证据、Proto 和 2 个 Widget 测试均成功。
- 全新 Clone 执行 Android Debug APK 构建：通过。
- Flutter 3.35.7 / Dart 3.9.2 与 `app/.fvmrc` 一致。
- Claude Code 能识别 `figma` 和 `marionette` 项目 MCP；二者当前均为 Pending approval。
- 本机已安装 `marionette_mcp 0.6.0`，与 App Binding 版本一致。
- 当前仓库未发现私有/path/git 依赖或本机用户路径；第 6 项是未来变更的门禁覆盖缺口，不是当前残留。

## Demo 启动前置

P1 已修复，仓库具备开始 Demo 实现的工程条件。正式拆卡前仍需提供：

1. 选定并复制到本地的 Figma Community 设计文件，以及作者、许可或使用说明和采用范围。
2. Demo 产品范围、核心用户流程和设计稿未表达的数据/错误/空状态决策。
3. 批准并验证 Figma Desktop MCP；Marionette 可在首个可交互页面运行后再批准和连接。

P2 不阻塞第一批 UI/架构任务，但 Integration Test 与 App Operator 应在首个端到端用户流程验收前补齐；CI、Quick Start 和依赖来源门禁应在对外宣布模板完成前处理。

## 复审

### P1-1 规划产物生命周期：已关闭

- `plan-tasks` 现在是唯一的任务命名和输出契约，定义了描述性唯一 slug、目标冲突停止、活动/归档位置、frontmatter 和验证规则。
- `plan-figma` 只负责设计输入标准化，把 `design-context.md` 写入 `docs/figma/`，任务卡继续复用统一输出契约。
- `docs/tasks/` 下只保留活动任务文件和 `done/` 子目录，不再维护 Overview 或批次目录。
- `execute-tasks` 不再为缺少 `executor` 的卡片猜测角色。
- Harness Check 会拒绝额外任务子目录、无效或重复 slug、不存在的依赖、无效 `executor`、无效 `blockedBy` 和缺少一级标题；相关失败 Fixture 已覆盖。

### 第一次复审结论（仅 P1）

P0/P1 均为 0；当时 5 个 P2 保持待办。`make check` 已通过，可以开始 Demo 设计输入和任务拆分。

## P2 修复复审

### Integration Test 标准入口：已关闭

- 新增 `make integration-test INTEGRATION_DEVICE=<device-id>`，只在显式设备上运行真实 `integration_test/`。
- `make check` 不运行设备测试，只运行 `integration-runner-test` 验证测试发现、无测试跳过、缺少设备拒绝和参数传递。
- `check-release` 与 `testing-strategy` 已引用统一入口。

### App Operator 任务闭环：已关闭

- 新增 `spec-writer` Agent 与 `/plan-spec`：根据已批准任务、产品规则和原型输入生成 `draft`/`ready` UI 行为 Spec。
- Version 1 Schema、`spec-check` 和失败 Fixture 已建立；原型信息不足时必须保留 `openQuestions`，不得交给 Operator。
- `uiSpec: required` 的任务必须依次通过机器 Schema 校验、`spec-auditor` 静态覆盖审计和 `app-operator` 运行验证才能归档；只有待决产品信息或外部运行状态需要人工介入。
- 当前没有真实 Demo Spec，因此未虚构 App Operator 运行历史；首个真实流程仍需验证 Marionette 连接和报告产出。

### Quick Start：已关闭

- README 默认使用 HTTPS Clone 和 `make setup`。
- `make setup` 已验证：使用 FVM 准备 Flutter 3.35.7，随后 Bootstrap Workspace Package 并安装 Git Hooks；无 FVM 时会严格校验系统 Flutter 版本。

### 远端 CI：已关闭实现，等待首个远端结果

- 新增 GitHub Actions Workflow，固定 Flutter 3.35.7，执行 `make bootstrap` 和 `make check`。
- Action 使用官方仓库当前 tag 对应的固定 Commit SHA；Harness Check 会拒绝缺失或遗漏关键步骤的 CI 配置。
- 本地已完成 YAML 与契约校验；Workflow 需要本次改动提交推送后才能获得首个 Ubuntu 运行结果。

### 私有路径与依赖来源门禁：已关闭

- Harness Check 现在扫描应用源码、全部 `pubspec.yaml`、脚本、Makefile 和 CI 配置中的本机用户路径。
- 依赖来源使用 YAML 结构化校验：允许 Pub.dev、Flutter/Dart SDK 和仓库内相对 path；拒绝绝对/越界 path、非 HTTPS 或未锁完整 Commit 的 Git、非 Pub.dev Hosted 来源。
- Fixture 覆盖仓库内相对 path 通过，以及本机 path、不可复现 Git、应用源码私有路径拒绝。

### 最终结论

P0/P1/P2 均为 0。`make setup`、`make check` 和无真实测试时的 `make integration-test` 路径均已验证。剩余两项外部运行验证是首个 GitHub CI Job，以及首个真实 ready Spec 的 Marionette App Operator 执行。
