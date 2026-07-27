---
executor: task-executor
blockedBy:
  - media-capture-bridge-contract
---

# 验证原生 Harness Bootstrap 并生成第二阶段任务

## 背景

原生架构、平台 Agent/Executor、Media Capture Capability Contract 和 Flutter Wire Contract 只建立实施前提，不等于 Media Capture 已经拥有可执行的原生实现计划。本任务是第一阶段唯一完成门禁：必须读取实际落地产物，再生成第二阶段任务，避免在 Contract 未完成时提前规划或在四张前置卡归档后遗漏实现任务。

## 输入与事实来源

- 已归档的 `native-harness-architecture-foundation`、`native-harness-agent-standards`、`media-capture-capability-contract` 和 `media-capture-bridge-contract`。
- `CLAUDE.md`、`docs/native-architecture.md` 和更新后的 `plan-tasks`、`execute-tasks`、Reviewer 规则。
- `docs/native/contracts/capability.schema.json`。
- `docs/infrastructure/contracts/media-capture.capability.json`。
- `docs/bridge/contracts/wire.schema.json`。
- `docs/bridge/contracts/media-capture.wire.json`。
- `docs/infrastructure/media-capture.md` 与 `docs/bridge/media-capture.md`。
- 已有订单评价设计和实现，以及 Media Capture 增量 UI 尚未批准的边界。

## 目标

- 确认第一阶段架构、Agent、Task Schema、Capability 和 Wire 产物完整且相互一致。
- 使用更新后的结构化任务元数据生成可执行的第二阶段任务图。
- 让 Android、iOS、Dart 和跨端集成分别由明确 Executor 所有。
- 在任何实现开始前对新任务图执行独立 Review。

## 非目标

- 不实现 Camera、Native Module、Dart Client、Bridge Adapter、权限、Host 注册或 UI。
- 不重新定义 Capability/Wire 语义或版本。
- 不在增量设计缺失时生成 Native UI、媒体入口、附件状态或 Shoppe 视觉接入任务。
- 不运行 Android/iOS Build、Flutter Test、Figma MCP 或设备验证。

## 具体要求

1. 前置四张任务必须已经完成、通过各自 Review/Security Review 并归档；固定路径下的架构、Agent、Schema、Contract、详情文档和 Harness Fixture 必须存在且通过门禁。缺一项就停止，不生成占位实现卡。
2. 依据更新后的 `plan-tasks` 规则和实际 Contract 生成第二阶段任务，不复制首轮已移除任务，也不从旧 Review 报告恢复过期要求。
3. 第二阶段至少拆分以下所有权，具体 slug 由实际产物命名：
   - Android Native Core：`android-engineer`、`platforms: [android]`、`workKinds: [native]`。
   - iOS Native Core：`ios-engineer`、`platforms: [ios]`、`workKinds: [native]`。
   - Android Bridge Adapter：`android-engineer`、`platforms: [android]`、`workKinds: [bridge-adapter]`。
   - iOS Bridge Adapter：`ios-engineer`、`platforms: [ios]`、`workKinds: [bridge-adapter]`。
   - Dart Client：`task-executor`、`platforms: [flutter]`、`workKinds: [dart-client]`。
   - Android/iOS 独立质量门禁：对应平台 Agent、单平台 `quality-gate`。
   - 跨 Runtime Host 注册、Contract Test 和最终集成：`bridge-engineer`、声明全部涉及平台、`workKinds: [integration]`。
4. Core 只依赖 Capability Contract；Dart Client 和两端 Bridge Adapter 依赖 Wire Contract；平台 Adapter 额外依赖对应 Core；最终集成依赖 Dart Client、两端 Adapter 和两端平台门禁。任务图必须无环并允许两端平台工作在没有共享写入时并行。
5. Android/iOS Core 和 Adapter 分别维护平台详情与证据文件；并行任务不得同时更新 `docs/infrastructure/media-capture.md`、`docs/bridge/media-capture.md`、根 Validator、共享 Registry、Host 或 CI 聚合入口。这些共享写入只归最终集成任务。
6. 所有改变 Camera/Microphone 权限、媒体文件、平台通道、第三方依赖或构建脚本的第二阶段任务必须声明 `securityReview: required`；纯 Dart Client 是否标记按实际输入边界判断，不机械扩大。
7. Bridge、Dart Client、平台 Adapter、Core、Contract Test 和非 UI 集成不得等待 Figma。只有新增拍摄 UI、订单评价媒体入口、预览/附件状态和 Shoppe 视觉接入等待增量设计后另行 `plan-figma`/`plan-tasks`。
8. 生成后运行 Harness 门禁，并由没有参与任务生成的独立 Reviewer 检查元数据、Executor、DAG、共享写入、Capability/Wire 依赖和 Figma 边界。存在 P0/P1 时本 Gate 不得归档，且任何第二阶段任务不得开始执行。
9. 明确记录“Bootstrap 已完成、Media Capture 尚未实现”；不得把第二阶段任务生成或静态 Contract 校验表述成 Android/iOS Build、设备 Camera 或 Flutter 集成已经验证。

## 同时编写的测试与证据

- `make harness-check` 验证所有新任务具有合法 `executor`、`platforms`、`workKinds`、`blockedBy` 和 `securityReview`。
- `make harness-test` 只验证确定性 Schema、Contract 和任务元数据规则；不声称它能证明 LLM 的规划过程。
- 独立 Review 使用实际生成的任务卡检查多平台拆分结果，并在报告中列出 DAG、共享写入所有者和剩余设计输入。

## 验收标准

- 第一阶段所有事实源和门禁均通过后才生成第二阶段任务。
- Android、iOS、Dart、Bridge 集成和平台门禁均有独立、可执行且范围匹配的任务卡。
- 第二阶段 DAG 无环，不存在并行任务共享写入同一聚合文件。
- 独立 Review 为 `P0=0`、`P1=0`；P2 必须记录负责人或 Follow-up。
- 当前四张前置卡完成不再被误述为 Media Capture 实施计划或功能已经完成。
- `make harness-check`、`make harness-test` 和 `git diff --check` 通过。

## 验证命令

```bash
make harness-check
make harness-test
git diff --check
```

## 平台或环境限制

本任务只验证 Bootstrap 产物并生成、审查第二阶段任务卡，不需要 Android SDK、Xcode、设备、Figma MCP 或 Marionette。任何真实平台能力和 Host 构建证据必须由第二阶段对应任务产生。
