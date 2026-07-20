# Harness 基线审查

- 审查范围：`7c071a5..946ea70` 以及提交后的完整仓库状态
- 审查视角：AI Harness 工作流、架构契约、可执行门禁、移动端反馈闭环与开源可用性
- 初审结论：未发现 P0；存在 5 个 P1 和 4 个 P2。Sprint 1 已修复并复审关闭全部 P1，4 个 P2 保持待办。

## P1

### 1. 依赖方向图与真实 Import 方向相反

- 位置：`CLAUDE.md:58`、`README.md:35`、`docs/README.zh-CN.md:35`
- 影响：权威契约把箭头画成 `app_core -> ... -> apps/demo`，而实际 `pubspec.yaml` 是 `apps/demo -> app_features -> app_data/app_im/app_rtc -> app_core`。Agent 容易把图理解成允许的 Import 方向，进而创建反向依赖或循环。
- 证据：`app/packages/app_features/pubspec.yaml:10` 依赖基础设施包，`app/apps/demo/pubspec.yaml:10` 依赖全部下层包。
- 修法：把图改成真实的 Import/Dependency 边，或明确标注现有箭头是“装配/能力流”而非依赖方向；最好补一张允许依赖矩阵，并由脚本校验各 `pubspec.yaml`。

### 2. 架构门禁会放行契约明确禁止的代码

- 位置：`scripts/lint/repository-boundaries.sh:8`、`scripts/lint/repository-boundaries.sh:23`、`scripts/lint/test-repository-boundaries.sh:32`
- 影响：`make lint` 目前只检查 Feature 间路径、Page/Widget 的部分 `Get.find<Api>`、GetX UI API 和直接生成目录引用；没有检查 Controller 内服务定位、壳工程直接引用 Feature 实现、Package 反向依赖。AI 生成代码即使违反 `CLAUDE.md:70-73` 仍可通过完整门禁。
- 证据：审查时构造了同时包含以下三项违规的临时 Fixture，脚本返回 0：Controller 内 `Get.find<ExampleApi>()`、Demo 壳 import `feature_alpha/controllers`、`app_core` import `app_features`。
- 修法：新增 Controller API 注入检查、壳工程内部实现检查和基于 Pub Workspace 的依赖图检查；为每类违规和允许装配点分别增加正反 Fixture。若正则开始复杂，应改用 Dart analyzer/AST 小工具。

### 3. “完整命令输出”与隐私规则冲突

- 位置：`.claude/commands/execute-tasks.md:30`、`docs/development-workflow.md:50`、`CLAUDE.md:185`
- 影响：执行工作流要求把完整 stdout/stderr 提交到 `docs/reviews/test-evidence/`，但 Flutter/Pub/Test 默认会输出本机绝对路径，测试和构建日志还可能包含环境、账号或用户数据。这会让 Agent 在遵守证据规则时违反“不输出本机私有路径”和敏感信息规则。
- 证据：本次 `make check` 输出中包含工作区绝对路径；当前没有脱敏或提交前校验步骤。
- 修法：继续跟踪证据文件，但定义可复现的脱敏流程：保存命令、版本、退出码和必要结果，把仓库根替换为 `<repo>`，删除 Token/签名/用户数据；原始日志只留本地临时目录。增加 evidence lint，发现绝对用户目录或常见凭据形态时失败。

### 4. 当前 Demo 缺少移动端宿主，无法验证移动端 Marionette 闭环

- 位置：`app/apps/demo/pubspec.yaml:1`、`CLAUDE.md:136`、`docs/development-workflow.md:82`
- 影响：`marionette_flutter 0.6.0` 支持运行在 Android/iOS 上的 Flutter App，但本仓库只有 `main.dart`、Marionette Binding 和移动端 Bridge 契约，没有 `android/`、`ios/` 平台宿主。因此 `flutter run`、平台构建、移动端 Marionette App 连接和 Bridge 任务都无法实际执行。Marionette 操作的是 Flutter Widget Tree，不应把系统原生界面自动化纳入其能力范围。
- 证据：`flutter build apk --debug` 报告 unsupported Gradle project；`flutter build ios --debug --no-codesign` 报告 `Application not configured for iOS`。
- 修法：把“生成并中立化 Android/iOS 壳工程”设为 Demo 第一张基础任务卡，明确 application id/bundle id 占位、最低版本和可替换项；加入至少一个 Debug 启动/构建烟测，再验证 Marionette connect/disconnect。

### 5. `make check` 没有验证 Harness 自身资产，也未包含 Proto 同步检查

- 位置：`Makefile:26`、`Makefile:31`、`CLAUDE.md:7`
- 影响：本仓库交付的核心产品是 `.claude` 工作流、Agent、Skill、MCP 和文档契约，但完整门禁只验证 Dart、仓库正则和测试。无效 frontmatter、失效 Agent/Skill 引用、断链文档、错误 JSON/脚本语法都可能合入；已有 `proto-check` 也不在 `make check` 中，未来克隆或 CI 无法发现已提交的生成漂移。
- 证据：`check` 依赖只有 `format analyze lint lint-test hook-test test`；当前没有 Harness 配置/链接校验脚本。
- 修法：增加 `harness-check`，校验 JSON、YAML frontmatter、Agent/Skill/Command 引用、`paths`、本地 Markdown 链接、Shell 语法、敏感/业务残留；把 `proto-check` 和 `harness-check` 纳入 `make check`，并给校验器自身添加 Fixture。

## P2

### 6. Integration Test 不在默认测试发现范围

- 位置：`scripts/quality/run-tests.sh:6`、`CLAUDE.md:27`
- 影响：脚本只发现 `*/test/*_test.dart`，`flutter test` 默认也不会执行 `integration_test/`。技术栈与 Skill 支持集成测试，但标准命令可能给出不完整的通过结论。
- 修法：新增显式 `make integration-test`（要求设备/模拟器），任务卡和 Release Check 根据影响面调用；不要把需要设备的测试静默混入快速单测目标。

### 7. App Operator 尚未接入标准任务闭环

- 位置：`.claude/commands/execute-tasks.md:31`、`.claude/agents/app-operator.md:29`、`docs/app-operator/README.md:3`
- 影响：当 `.spec.yaml` 出现时，`execute-tasks` 只运行静态 `spec-auditor`，没有调用 `app-operator` 执行真实 App 行为；运行报告的调用方也未定义。当前占位状态可接受，但首个 Spec 落地前必须闭环。
- 修法：定义 Schema 时同步增加条件式 App Operator 阶段、运行报告路径、失败证据和清理规则，并明确静态审计与运行验证各自的通过条件。

### 8. 开源 Quick Start 对首次使用者不够稳健

- 位置：`README.md:67`、`docs/README.zh-CN.md:67`、`app/.fvmrc:1`
- 影响：公开仓库示例使用 SSH Clone，需要 GitHub SSH 身份；同时 `.fvmrc` 位于 `app/`，但 Quick Start 没有安装固定 SDK 的命令。安装了 FVM、却没有 Flutter 3.35.7 的用户可能在 `make bootstrap` 首步失败或被交互提示阻塞。
- 修法：公开文档默认使用 HTTPS Clone；增加明确的 `cd app && fvm install`，或让根 `make setup/bootstrap` 以非歧义方式准备固定 SDK，并记录全局 Flutter fallback。

### 9. 远端尚无持续集成门禁

- 位置：`README.md:80`、`Makefile:26`
- 影响：本地门禁已建立，但 PR/外部贡献者没有统一的远端结果，Shell/Linux 兼容性和未安装 hooks 的提交不会被自动发现。
- 修法：模板结构稳定后增加最小 CI：锁定 Flutter 3.35.7，运行 `make check` 和 Harness 校验；移动端完整构建可按成本拆为条件 Job。当前提取阶段可显式延后。

## 已确认事项

- 源工程专属标识与内容、私有/path/git 依赖和常见凭据形态扫描均无命中；本报告不复述扫描关键词，避免把审查证据本身变成残留。
- `.claude/memories/` 均为可泛化工程经验，没有多余 `repo/` 子目录。
- Skill `paths` 和 `.mcp.json` 的 `${CLAUDE_PROJECT_DIR:-.}` 语法符合 Claude Code 官方格式；本机 Claude Code 为 2.1.198。
- `figma` 与 `marionette` 项目 MCP 均被 Claude Code 识别，当前状态为 Pending approval；未把未批准连接误报为可用。
- `make check`、`make proto`、`make proto-check` 通过；其中 Proto 命令按占位设计跳过。
- 暂存区/提交内容不包含构建缓存、IDE 文件或 `.DS_Store`。

## 剩余验证风险

- 未批准并实际连接 Figma Desktop MCP。
- 未启动 Marionette MCP，也未连接运行中的 App。
- 因平台宿主不存在，Android/iOS 构建失败；这不是本机 SDK 环境缺失导致。
- 本机未安装 ShellCheck/shfmt，Shell 仅通过现有 Fixture 与 Bash 执行路径验证。

## 复审：Sprint 1

### P1-1 依赖方向：已关闭

`CLAUDE.md`、中英文 README 和 `docs/architecture.md` 已统一为 `A -> B` 表示 A 可以 import B，并增加允许直接依赖矩阵。

### P1-2 架构门禁：已关闭

门禁新增 Controller API 服务定位、壳工程内部 import 和结构化 Workspace 依赖图检查；正反 Fixture 均通过。

### P1-3 证据隐私：已关闭

任务证据统一通过采集器记录命令、退出码和脱敏输出；evidence lint 与路径、凭据、私钥、失败退出码 Fixture 已纳入完整门禁。

### P1-4 移动端宿主：已关闭

Demo 已生成并去本机化 Android/iOS 标准宿主。Android Debug 构建通过；iOS 已进入 Xcode Build，但本机 iOS Platform/destination 状态不可用，保留为明确环境验证缺口。

### P1-5 Harness 自检：已关闭

`harness-check` 覆盖 JSON、frontmatter、资产引用、任务 executor、Markdown 链接、Shell 语法、平台宿主、本机路径和 iOS Development Team。`make check` 已纳入 Harness、证据、Proto、架构和测试门禁；`melos run check` 委托该唯一入口并通过。

### 复审结论

P0/P1 均为 0。详细任务 Review 和脱敏命令证据见 `docs/reviews/execute-S1-*.md` 与 `docs/reviews/test-evidence/`。原 P2 不在本轮修复范围内。

## 后续状态

原 4 个 P2 已在后续 Demo 开发就绪复审中关闭；当前状态与新增依赖来源门禁见 `docs/reviews/demo-readiness.md`。
