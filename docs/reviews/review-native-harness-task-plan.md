# Native Harness 任务规划独立审查

## 结论

**第二轮修复复审通过。** 当前 4 张 Bootstrap/Contract 任务卡为 `P0=0`、`P1=0`、`P2=0`。首轮 6 张任务卡曾发现 **4 个 P1** 和 **1 个 P2**，以下保留原始问题与两轮修复记录。

## 审查范围

- 分支：`feat/native-harness`
- 首轮工作树新增的 6 张 `docs/tasks/*.md`；第二轮收敛为当前 4 张 Bootstrap/Contract 任务卡。
- 对照 `CLAUDE.md`、`docs/architecture.md`、`docs/infrastructure-modules.md`、`docs/bridge/README.md`、`.claude/commands/execute-tasks.md` 和 Reviewer 规则。
- 本轮由独立 Reviewer 只读检查任务规划；除本报告外没有修改任务卡、实现、测试、配置或依赖。

## P0

无。

## P1

### 1. Native Capability 与 Wire Contract 合并在 `bridge-engineer` 任务中，Core 又反向依赖 Bridge Contract

- 位置：[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L2)、首轮任务 `media-capture-android-core.md`、首轮任务 `media-capture-ios-core.md`、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L49)
- 影响：Native 公共 API 容易被 Flutter Wire 形态反向塑形，未来原生消费者会成为次级消费者；Core 演进也会被 Channel 兼容性不必要地约束。这与任务卡已经声明的“Bridge 不拥有 Native Capability”矛盾。
- 证据：`media-capture-capability-contract` 同时由 `bridge-engineer` 定义 Native 公共能力和 Wire Contract；Android/iOS Core 又把 `docs/bridge/media-capture.contract.yaml` 作为实现输入。
- 修法：拆成两个任务。先由 transport-neutral 的 Capability 任务定义 `docs/infrastructure/media-capture.md` 和两端 Native 公共语义；再由 `bridge-engineer` 从 Capability 派生 Wire Contract。Android/iOS Core 只依赖 Capability 文档，不依赖 Bridge Contract。

### 2. Flutter Bridge Adapter 被错误地与 Figma UI 一起延期

- 位置：[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L14)、首轮任务 `native-harness-quality-gates.md`
- 影响：当前 6 张任务卡最终不会实现或验证 `Flutter Bridge Adapter -> Native Module` 这一核心依赖方向，原生 Harness 最关键的跨 Runtime 边界仍停留在文档中；Bridge DTO、注册和错误映射也被一个只影响视觉与交互的 Figma 前置条件不必要地阻塞。
- 证据：质量门禁任务把 `app_media_capture_bridge` 与 Android/iOS Native UI、Shoppe 页面一起延期到 `plan-figma`，但现有任务已明确 Figma 缺失只影响布局、视觉 Token 和未确认交互。
- 修法：新增非 UI 的 `bridge-engineer` 任务，依赖 Capability/Wire Contract 与两端 Core，实现 Dart Client、Android/iOS Bridge Adapter、DTO/Native Model 映射、注册、Contract Test 和 Host Build。只有 Native UI 与 Shoppe 页面接入等待 Figma。

### 3. 跨 Android/iOS 的质量门禁任务使用了无效 Executor

- 位置：首轮任务 `native-harness-quality-gates.md`、[execute-tasks.md](../../.claude/commands/execute-tasks.md#L23)
- 影响：`/execute-tasks` 在实现前必须停止并要求改卡，因此该任务按当前工作流不可执行；把两平台格式、lint、测试、Make 和 CI 集中在一张卡里也阻止单平台门禁独立落地。
- 证据：任务声明 `executor: task-executor`，同时要求同步修改 Android、iOS 与跨平台 CI；现有 Command 明确禁止 `task-executor` 执行多原生平台同步修改。
- 修法：优先拆成 Android 门禁卡和 iOS 门禁卡，各自使用 `task-executor` 并只依赖对应 Core；再增加使用 `bridge-engineer` 的跨平台聚合/CI 卡。若不拆分，至少把当前任务 Executor 改为 `bridge-engineer`。

### 4. Media Capture 基础能力归类缺少任务内可审查的项目决策依据

- 位置：[native-harness-architecture-foundation.md](../tasks/native-harness-architecture-foundation.md#L30)、[native-harness-architecture-foundation.md](../tasks/native-harness-architecture-foundation.md#L55)、[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L45)
- 影响：任务一边声明 Harness 不决定模块业务归属、基础索引依赖真实复用，另一边直接要求把只有一个已记录消费者的 Media Capture 标记为已批准基础能力。后续实现者无法从任务事实区分这是明确的项目决策，还是 Harness 自动分类。
- 证据：当前任务只记录 Shoppe 订单评价为首个消费者；“Flutter 与未来原生业务复用”没有作为用户已批准的分类决定和预期消费者边界写入事实来源。
- 修法：在 Capability 任务中明确记录用户已经批准其作为基础能力的决策，以及 Flutter/原生直接复用的目标；或者在第二个真实消费者确定前使用分类中立的 Native Module 索引，不提前写入基础模块索引。

## P2

### 1. 可并行的 Android/iOS Core 会共同修改同一基础能力文档

- 位置：首轮任务 `media-capture-android-core.md`、首轮任务 `media-capture-ios-core.md`
- 影响：两张并行任务可能在 `docs/infrastructure/media-capture.md` 产生冲突、覆盖平台证据，或对整体实现状态作出不一致更新。
- 修法：为 Android/iOS 使用独立平台详情文档并由 Capability 页面索引，或把共享状态和验证命令汇总移到同时依赖两张 Core 卡的后续聚合任务。

## 已确认边界

- 6 张任务卡构成无环 DAG，Android/iOS Core 可以在共同前置完成后并行。
- 文档架构任务不声明 Security Review 合理；Agent 能力、Wire/权限/文件、原生依赖和 CI 工具任务均已声明 `securityReview: required`。
- Native Consumer 直接依赖 Native Module、Flutter Bridge 依赖同一 Native Module、Native Module 不反向依赖 Flutter 的目标在架构任务中表达清楚。
- 缺少 Figma 时没有提前规划最终 Native UI 和 Shoppe 页面视觉实现，该边界本身正确。

## 验证

- `make harness-check`：通过。
- 任务 slug、frontmatter、`blockedBy` DAG 和 Security Review 字段：通过当前 Harness 静态校验。
- 未运行 Android/iOS 构建、Flutter 测试或设备验证；本轮只有任务文档，没有应用实现。

## 待确认问题

- Media Capture 进入基础模块索引是否已经作为用户明确的项目决策批准；若已批准，应把该事实和预期原生消费者写进任务输入，而不是依靠隐含上下文。
- Flutter Adapter 是否还有本批之外的已批准任务；当前活动任务中没有。

## 修复复审

2026-07-27 按用户明确范围修复并由新的独立 Reviewer 复审第 2、4、5 项。复审结论：三项均已闭环，没有发现修复引入的新问题。

以下内容保留首轮修复历史；相关实现卡随后为两阶段 Bootstrap 方案移除，当前状态以文末第二轮复审为准。

- **原 P1-2 Flutter Bridge Adapter 延期：已解决。** 新增 `media-capture-flutter-bridge`，由 `bridge-engineer` 执行，依赖 Capability Contract 和两端 Core，覆盖 Dart Client、Android/iOS Adapter、映射、注册、Contract Test 与两端 Host Build；任务明确不等待 Figma，只有 Native UI 和 Shoppe 接入延期。
- **原 P1-4 基础能力归类缺少依据：已解决。** Capability 任务已记录用户批准 Media Capture 作为基础能力的项目决策，以及 Flutter Consumer 通过 Bridge、原生 Consumer 直接依赖 Native Module 的边界；基础模块索引必须保留该决策来源。
- **原 P2-1 平台任务共享写入：已解决。** Android/iOS Core 分别维护 `media-capture-android.md` 与 `media-capture-ios.md`，共享能力文档只由依赖两端 Core 的 Bridge 任务及其后续质量门禁串行汇总。

复审实际运行：

- `make harness-check`：通过。
- `git diff --check`：通过。
- 未运行 Native Build 或 Flutter Test；本轮只修改任务规划文档。

当前结论仍为 **未通过**：`P0=0`、`P1=2`、`P2=0`。原 P1-1（Capability/Wire Contract 所有权）和 P1-3（跨平台质量门禁 Executor/拆分）按用户要求保留讨论，未在本轮修改或复审。

## 第二轮修复复审

2026-07-27 根据用户确认继续修复原 P1-1 与 P1-3，并由独立 Reviewer 重新读取当前任务图后复审。复审结论：**通过，`P0=0`、`P1=0`、`P2=0`**，没有发现新问题。

- **原 P1-1 Capability/Wire 所有权：已解决。** `media-capture-capability-contract` 只定义 transport-neutral 的模块能力，排除 Channel、Wire 和 Flutter 概念；`media-capture-bridge-contract` 明确后置，并且只能映射既有能力。未来 Android/iOS Core 只依赖 Capability Contract，不读取 Bridge Contract。
- **原 P1-3 跨平台门禁 Executor：已解决。** 当前任务图不再提前创建 Android/iOS 实现和跨平台质量门禁卡。`native-harness-agent-standards` 先扩展 `android-engineer`、`ios-engineer` 与 Executor Schema，再要求重新运行 `plan-tasks`，将 Android Core/门禁、iOS Core/门禁、Dart Client、平台 Adapter 和跨端集成按所有权拆成独立任务。
- **原 P1-2 Bridge/Figma 边界：未回归。** Bridge Contract 与 Agent Bootstrap 都明确 Bridge、Dart Client、平台 Adapter 和非 UI 集成不等待 Figma；只有 Native UI 与 Shoppe 页面接入等待设计输入。
- 原 P1-4 的项目分类决策仍被 Capability 任务明确记录；原 P2-1 的共享文档并行写入风险由第二阶段重新拆卡规则继续约束。

当前 4 张活动任务形成无环 Bootstrap DAG：架构任务完成后，Agent/Executor 建设与 Capability Contract 可以并行；Wire Contract 只依赖 Capability Contract。第二阶段任务必须在 Agent/Executor 建设完成后重新规划并再次独立审查，不能直接恢复首轮已移除的实现卡。

最终验证：

- `make harness-check`：通过。
- `make harness-test`：通过。
- `git diff --check`：通过。
- 未运行 Android/iOS Build、Flutter Test 或设备验证；当前变更仅包含任务规划和审查文档。
