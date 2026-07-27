# Native Harness 任务规划第二意见审查

## 结论

当前 4 张 Bootstrap/Contract 任务卡未达到可直接执行状态：`P0=0`、`P1=5`、`P2=2`。

任务对 Capability、Native API 与 Wire 的所有权拆分方向正确，Security Review 标记也与当前风险边界一致；阻断项主要来自 Executor/平台范围无法确定校验、并行任务共享写入、第二阶段门禁不完整，以及部分测试要求无法由现有工具证明。

## 审查范围

- 分支：`feat/native-harness`
- 当前 4 张活动任务卡：
  - `native-harness-architecture-foundation`
  - `native-harness-agent-standards`
  - `media-capture-capability-contract`
  - `media-capture-bridge-contract`
- 对照当前 `CLAUDE.md`、架构/基础模块/Bridge 文档、Agent/Command、Codex Adapter 生成器、Harness Validator/Fixture、现有 Android/iOS Host、Figma 上下文与订单评价实现。
- 先独立形成判断，最后才读取 `docs/reviews/review-native-harness-task-plan.md` 做遗漏与矛盾检查。
- 除本报告外，没有修改任务卡、实现、配置、测试或依赖。

## P0

无。

## P1

### 1. 平台范围没有结构化事实，Validator 无法确定拒绝 Executor 冲突

- 位置：[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L57)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L63)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L71)、[harness_check.dart](../../app/tool/harness_check.dart#L472)
- 影响：任务要求 `execute-tasks` 不从文件名或 diff 猜平台，同时要求 Harness Fixture 拒绝“Android/iOS 范围与 Executor 不匹配”；但现有任务卡只结构化声明 `executor`、`blockedBy` 和可选 `securityReview`。Validator 只能确认 Executor 在 allowlist 中，无法从自然语言正文确定任务属于 Android、iOS、Dart 还是 Wire。实现者只能违反要求去解析 prose/路径，或留下一个不能证明验收标准的测试。
- 证据：任务第 10 条明确禁止运行时从文件名或 diff 推断，却没有新增 `platforms`、工作类型或目标文件等可校验字段；当前 `_validateTasks` 在 472-476 行只校验两个既有 Executor 值。现有 `plan-tasks` 也不要求结构化平台范围。
- 修法：二选一并在卡内定案。推荐为 Native/Bridge 任务增加最小结构化范围，例如 `platforms` 与 `workKinds`，同步更新 `CLAUDE.md`、`plan-tasks`、`execute-tasks`、Validator、活动/归档兼容和 Fixture；如果不扩展任务元数据，则删除“Validator 确定拒绝平台冲突”的验收，把它明确降为规划/执行阶段的语义 Review，不能声称 Harness 已机器保证。

### 2. DAG 允许三个任务并行修改同一 Validator 和 Fixture

- 位置：[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L3)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L68)、[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L3)、[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L55)、[media-capture-bridge-contract.md](../tasks/media-capture-bridge-contract.md#L3)、[media-capture-bridge-contract.md](../tasks/media-capture-bridge-contract.md#L48)
- 影响：架构任务完成后，Agent 标准与 Capability 可以并行；Capability 完成后 Bridge 也可与仍在执行的 Agent 标准并行。三张卡都要求扩展 `app/tool/harness_check.dart` 和 `scripts/quality/test-harness.sh`，会产生覆盖、冲突、漏合并 Fixture 或复审摘要失效。当前 DAG 因而只在 slug 层面无环，不满足共享工作树上的可并行执行条件。
- 证据：Agent 标准要求修改 Harness Task Validator 并扩展 Harness/Codex Fixture；Capability 和 Bridge 都明确要求修改 `harness_check.dart` 及失败 Fixture。它们之间没有 `blockedBy` 边，旧报告把这三者视为可并行，却只处理了未来 Android/iOS 平台详情文档的并发写入。
- 修法：最小修法是串成 `architecture -> agent-standards -> capability-contract -> bridge-contract`；这样还可确保 Capability 中需要 Android/iOS 沙箱判断的媒体句柄决策发生在原生知识资产建立之后。若必须并行，则先拆出单独的 Schema/Validator 基础任务，并把各 Contract Validator 与 Fixture 分到独立文件，明确唯一聚合任务，禁止多个并行任务编辑同一入口脚本。

### 3. 第二阶段重规划时点过早，且没有 Bootstrap 完成门禁

- 位置：[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L100)、[media-capture-bridge-contract.md](../tasks/media-capture-bridge-contract.md#L78)
- 影响：Agent 标准卡要求“完成本任务后”立即重新调用 `plan-tasks`，但此时 Capability 和 Wire Contract 按当前 DAG 可能尚未完成。第二阶段 Android/iOS Core、Dart Client 和平台 Adapter 会在缺少最终结构化契约时被规划，或者只能引用尚未确定路径的未来产物。反过来，如果不主动执行这句 prose，四张卡又都可以归档而不产生任何第二阶段任务，Bootstrap 会在“具备实现条件”之前被当成完成。
- 证据：重规划动作挂在只依赖架构任务的 Agent 标准卡末尾；Bridge 卡只说实现任务“重新规划后创建”，没有要求何时、由谁、以哪些已归档产物为门禁，也没有验收项确认第二阶段任务已生成并再次 Review。
- 修法：把第二阶段入口移到一个明确的 Bootstrap 批次门禁：只有架构、Agent、Capability 和 Wire 四卡均完成并归档后，才用更新后的 `plan-tasks` 读取实际产物生成平台 Core、平台 Adapter、Dart Client、分平台质量门禁与跨端集成卡；生成结果必须形成无环 DAG并再次独立 Review 后才能执行。若该动作保持人工触发，报告和任务说明必须明确“当前四卡完成不等于 Media Capture 实施计划完成”，不能只依赖 Agent 卡末尾的一句建议。

### 4. 两个 Contract 没有给出稳定产物路径，版本独立性测试也不是可观测不变量

- 位置：[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L46)、[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L55)、[media-capture-bridge-contract.md](../tasks/media-capture-bridge-contract.md#L19)、[media-capture-bridge-contract.md](../tasks/media-capture-bridge-contract.md#L39)、[media-capture-bridge-contract.md](../tasks/media-capture-bridge-contract.md#L57)
- 影响：Capability 卡只说“新增结构化 Contract”，没有文件路径、格式、Schema 标识或 Validator 入口；Bridge 卡的输入因此只能写成没有链接的泛称，并继续把实现方案留在“JSON Schema 或仓库标准解析方案”之间。下游无法确定引用哪个事实源，两个执行者也可能建立不兼容的结构。另一个验收要求让失败 Fixture 识别 Capability/Wire “同时升级或错误绑定”，但当前静态检查只看到一个仓库快照，无法判断两个独立版本是否恰好同号或是否在同一变更中升级；禁止同号会误拒绝合法独立版本。
- 证据：当前 `docs/bridge/README.md` 只有 prose 模板，并不存在可复用的结构化 Bridge Schema 约定；任务卡没有补足新约定的具体路径。现有 Harness Check 不读取 Git 历史，无法证明“同时升级”这一历史事件。
- 修法：在任务卡中固定 Capability Contract、Schema、Wire Contract、Schema 和 Validator/Fixture 的仓库相对路径与格式，定义稳定 operation/failure ID 及映射方式。把版本测试改为可静态证明的结构不变量，例如 Wire 有独立 `wireVersion`，显式声明兼容的 Capability version/range，禁止引用同一个 version source；不要把数值相等或同一 commit 中变更本身视为绑定。

### 5. Agent 标准卡要求的多个自动化测试在当前工具模型中不可执行

- 位置：[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L70)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L72)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L73)、[codex_adapters.dart](../../app/tool/codex_adapters.dart#L673)、[test-harness.sh](../../scripts/quality/test-harness.sh#L128)
- 影响：执行者无法诚实地用 `make harness-test` 证明“给定多平台输入会被 plan-tasks 拆卡”，因为 `plan-tasks` 是 Agent Markdown 工作流，不是可调用的确定性规划器。Codex Adapter 生成物也只复制 Skill 的 name/description 并链接事实源，不包含 `paths`，所以 path-only 变化不会产生 Adapter drift；强行让该测试通过会扭曲生成格式或写只检查文案的假测试。
- 证据：`_skillAdapter` 在 673-688 行只生成 name、description 和事实源链接；`scripts/quality/test-harness.sh` 的 `run_check` 只运行 Dart Validator，不会执行 LLM/Agent 规划。Claude Skill 的 `paths` 可由 Harness 校验源 frontmatter，但不能当成 Codex Adapter 内容漂移来测。
- 修法：把测试按可观测边界拆开：Codex Adapter Fixture 只测新增 Agent/Skill 的生成、缺失、过期、description 和只读 sandbox；Harness Fixture 测结构化 Executor/平台元数据与 Skill `paths` 的允许模式；多平台拆卡用独立规划 Review 场景验收。若必须自动证明规划行为，先实现确定性输入模型和规划/校验器，再把该工具加入任务范围。

## P2

### 1. Figma 状态写成“尚未提供”不符合仓库现状

- 位置：[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L24)、[media-capture-capability-contract.md](../tasks/media-capture-capability-contract.md#L84)、[shoppe-main-app-design-context.md](../figma/shoppe-main-app-design-context.md#L5)、[shoppe-main-app-design-context.md](../figma/shoppe-main-app-design-context.md#L26)、[order_review_page.dart](../../app/packages/app_features/lib/feature_orders/pages/order_review_page.dart#L55)
- 影响：仓库已有标准化的 Shoppe Figma 来源，且节点 `66/67` 已归为评价填写/完成状态，订单评价页面也已实现。真正缺少的是“在现有评价流程中加入 Media Capture 的新设计输入”，不是整个评价 Figma。模糊表述会导致重复标准化既有设计，或把不涉及新增拍摄 UI 的 Shoppe 接线一概延期。
- 证据：设计上下文记录了 File Key、读取日期和订单评价节点，但也要求执行前重新读取准确节点；现有 `OrderReviewPage` 只有评分、文本与提交，没有媒体入口。因此不能从既有设计推导拍摄 UI，同时也不能声称设计稿完全不存在。
- 修法：引用现有 `docs/figma/shoppe-main-app-design-context.md`，明确“既有订单评价设计与实现存在，但 Media Capture 入口、预览及附件状态尚无已批准设计”；只有新增 Native UI 和页面视觉/交互等待该增量设计，Core、Contract、Dart Client、平台 Adapter 与非 UI 集成继续不等待 Figma。

### 2. “Flutter Bridge Adapter”同时指 Dart Package 和平台 Adapter，依赖方向仍有歧义

- 位置：[native-harness-architecture-foundation.md](../tasks/native-harness-architecture-foundation.md#L44)、[native-harness-architecture-foundation.md](../tasks/native-harness-architecture-foundation.md#L48)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L49)、[native-harness-agent-standards.md](../tasks/native-harness-agent-standards.md#L100)
- 影响：架构卡先称 Flutter/Dart Adapter 位于 Workspace Package，又称 Flutter Bridge Adapter 依赖 Native Module；Agent 卡随后才区分 Dart Client 与各端 Bridge Adapter。实现者可能把 Dart 层描述成直接依赖 Kotlin/Swift 模块，或无法判断平台 Adapter 位于 Flutter Package、Host 还是原生模块之外。
- 证据：Dart Client、Android Bridge Adapter、iOS Bridge Adapter 具有不同依赖能力，不能共用一句“Adapter 依赖 Native Module”表达；后续任务已经使用三者分拆的术语，基础架构卡应与之统一。
- 修法：在架构任务中固定三段关系：Dart Client 只拥有 Wire Model/Channel 调用；Android/iOS Bridge Adapter 分别依赖对应 Native Module 并做边界映射；Host 只注册 Adapter。再明确聚焦 Workspace Package 是否包含平台子目录，以及原生模块如何从 Host/Plugin 构建图接入。

## 已确认无问题的边界

- 四张卡的当前 frontmatter 值能通过现有 Validator，slug 与 `blockedBy` 没有循环或不存在引用。
- Capability 先定义 transport-neutral 语义，Wire Contract 只能映射既有 Capability；Android/iOS Core 不应读取 Wire Contract。此所有权方向正确。
- Native Consumer 直接依赖 Native Module、Native Module 不 import Flutter、Host 只装配的总体方向正确。
- `native-harness-agent-standards`、`media-capture-capability-contract`、`media-capture-bridge-contract` 标记 `securityReview: required` 合理；纯架构文档任务未改变实际权限或 Agent 能力，不强制 Security Review 合理。
- Figma 延期的原则正确：新增 Native UI 和 Shoppe 页面交互等待增量设计，非 UI Contract/Core/Adapter/集成不应等待。
- Capability 共享文档与未来 Android/iOS 平台详情文档的写入所有权已被区分；本报告的并发问题是当前三张卡共同修改 Harness Validator/Fixture，而不是未来平台详情文档。

## 与旧报告对照

`docs/reviews/review-native-harness-task-plan.md` 的最终结论为 `P0=0、P1=0、P2=0`，并把 Agent 标准与 Capability 并行、Agent 完成后重规划视为完整 Bootstrap。该结论遗漏了：

- 当前阶段 `harness_check.dart`/`test-harness.sh` 的共享写入冲突；
- 平台范围没有结构化输入却要求 Validator 拒绝冲突；
- 重规划可能早于 Capability/Wire 产物完成，且没有批次完成门禁；
- Codex `paths` drift、LLM 规划输出和“版本同时升级”无法由现有 Fixture 观察。

旧报告对 Capability/Wire 所有权、Figma 非 UI 边界、安全标记和未来平台共享文档的修复判断仍成立，但不足以支持其最终零问题结论。

## 验证

- `make harness-check`：通过。
- `make harness-test`：通过，输出 `[harness-test] Harness 配置与失败 Fixture 通过。`
- `git diff --check`：通过。
- 未运行 Android/iOS Build、Flutter Test、Figma MCP 或设备验证；当前审查对象仅为任务规划文档，且任务声明不需要这些环境。

现有门禁通过只说明四张卡符合当前的两 Executor/frontmatter、链接、适配同步和既有失败 Fixture；它不覆盖本报告指出的未来 Executor Schema、任务语义、并发写入和第二阶段编排。

## 剩余风险

- Media Handle 采用 app-owned path、URI 或 opaque identifier 仍需 Capability 任务结合两端沙箱定案；不应由 Wire Contract 决定。
- Camera/麦克风权限、媒体清理、EXIF/位置隐私、进程重启与释放后回调只能在后续实现和平台构建/测试中验证；当前 Contract 任务只能建立可审查边界。
- 第二阶段任务尚不存在，因此 Android/iOS Core、平台 Adapter、Dart Client、独立质量门禁和跨端 Host Build 的最终 DAG 仍需在 Bootstrap 产物完成后重新规划与审查。

## 修复复审（2026-07-27）

### 结论

本轮逐条复核原报告 `P1-1` 至 `P1-5`、`P2-1` 至 `P2-2`，七项均已关闭。当前任务规划为 `P0=0`、`P1=0`、`P2=0`，未发现修复引入新的 P0/P1/P2。

本结论只覆盖五张活动任务卡的可执行性、依赖和验证设计；不表示任务卡中约定的 Schema、Contract、Agent、平台实现或第二阶段任务已经生成或通过运行验证。

### 原问题状态

| 原问题 | 状态 | 复核证据 |
| --- | --- | --- |
| `P1-1` 平台范围无结构化事实 | 已关闭 | `native-harness-agent-standards` 固定了 `platforms`、`workKinds` 的值域、活动任务必填、历史归档兼容、四类 Executor 的允许组合和冲突停止条件；Fixture 也分别覆盖字段、值域、重复值、兼容迁移和 Executor 冲突。正文一致性明确留给 Reviewer，不再要求 Validator 猜测 prose、文件名或 diff。 |
| `P1-2` 并行任务共享 Validator/Fixture 写入 | 已关闭 | DAG 已串行为 `native-harness-architecture-foundation -> native-harness-agent-standards -> media-capture-capability-contract -> media-capture-bridge-contract -> native-harness-bootstrap-gate`。会依次修改 `app/tool/harness_check.dart` 或 `scripts/quality/test-harness.sh` 的任务不再并行。 |
| `P1-3` 第二阶段重规划过早且缺少完成门禁 | 已关闭 | 新增 `native-harness-bootstrap-gate`，只在四张前置卡完成 Review/Security Review、归档且固定产物通过门禁后生成第二阶段任务；生成后的实际任务卡必须再经独立 Reviewer 检查，存在 P0/P1 时 Gate 不得归档且第二阶段不得执行。Agent 和 Wire 任务均明确不得提前重规划。 |
| `P1-4` Contract 路径和版本独立性不可观察 | 已关闭 | Capability Schema/实例固定为 `docs/native/contracts/capability.schema.json`、`docs/infrastructure/contracts/media-capture.capability.json`；Wire Schema/实例固定为 `docs/bridge/contracts/wire.schema.json`、`docs/bridge/contracts/media-capture.wire.json`。Wire 使用独立 `wireVersion` 和非空 `compatibleCapabilityVersions`，Fixture 只校验当前快照中的字段独立性、当前 Capability 版本兼容和稳定 ID 映射，不再从数值相等、Commit 或 Git 历史推断绑定。 |
| `P1-5` 自动化测试超出现有工具能力 | 已关闭 | Codex Adapter Fixture 只验证生成、缺失、过期、description 和只读 sandbox；Skill `paths` 直接在 Claude 事实源上校验；多平台规划拆分移交 Bootstrap Gate 的实际任务卡独立 Review。`make harness-test` 不再被要求执行 LLM Planner。 |
| `P2-1` Figma 状态不准确 | 已关闭 | Capability 卡引用既有 Shoppe 订单评价节点和实现，并准确限定缺失的是 Media Capture 入口、拍摄器、预览和附件状态的增量设计；Core、Contract、Dart Client、平台 Adapter 与非 UI 集成不等待 Figma。Bootstrap Gate 延续了同一边界。 |
| `P2-2` Dart Client/平台 Adapter 术语混用 | 已关闭 | 架构卡明确聚焦 Flutter Plugin Package：`lib/` 是 Dart Client/Wire/Channel，`android/`、`ios/` 是各端 Bridge Adapter；Dart Client 不依赖 Kotlin/Swift Module，只有平台 Adapter 依赖对应 Native Module，Host 只装配和注册。 |

### 当前问题

- P0：无。
- P1：无。
- P2：无。

### 验证

- `make harness-check`：通过；Codex Adapter 同步检查与 Harness 静态检查均成功。
- `make harness-test`：通过，输出 `[harness-test] Harness 配置与失败 Fixture 通过。`
- `git diff --check`：通过。
- 未运行 Android/iOS Build、Flutter Test、Figma MCP、Marionette 或设备验证；本轮仍只审查任务规划文档，五张任务卡也没有要求在当前阶段运行这些环境。

现有 Harness 仍只验证修复前的 Executor/frontmatter 和既有 Fixture；上述新 Schema、Contract 与负例覆盖必须在对应任务执行后才会进入门禁。本次命令通过证明当前规划产物没有破坏现有门禁，不替代未来任务的验收。

### 剩余风险

- `platforms`/`workKinds` 的最终 Validator 实现仍需用完整允许/拒绝矩阵证明多值、空平台、单平台质量门禁、跨 Runtime 集成和历史归档兼容；本次只确认任务卡已给出可机器实现的值域、所有权和测试边界。
- Capability 内部 Schema 结构、稳定 ID 集合、媒体句柄类型和版本初值仍由 Capability 任务结合 Android/iOS 沙箱定案；Wire 任务只能消费其实际产物。
- 第二阶段任务尚未生成。共享 Registry、Host、CI 聚合入口的唯一写入所有者和最终 DAG 必须以 Bootstrap Gate 生成的实际任务卡为准，并再次独立 Review。
- 平台权限、文件清理、释放后回调、原生构建和设备 Camera 行为仍只能由第二阶段实现、平台测试与构建证据证明。
