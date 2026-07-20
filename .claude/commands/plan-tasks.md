---
description: 将产品或技术输入拆成按依赖排序的任务卡，不做实现
argument-hint: "[需求、文档路径和额外约束]"
---

使用 `architect` 角色创建实现计划，不编写应用代码。

## 输入

读取 `$ARGUMENTS`、`CLAUDE.md`、`docs/architecture.md`、相关 App 文档、协议定义和现有代码。

需求包含 Figma URL 或 node-id 时，只复用 `plan-figma` 的“设计输入标准化”阶段读取节点，再返回本命令继续统一规划；不得让两个命令分别生成任务卡。

不得编造无法从产品输入、设计、协议或代码推导出的需求。未确定的产品决策必须显式记录。

## Sprint 分配

1. 用户提供 `sprint=N` 时使用该正整数；未提供时，扫描 `docs/tasks/sprint-*` 和 `docs/tasks/done/SN-*`，取已存在最大编号加一，完全没有历史时从 1 开始。
2. 输出目录固定为 `docs/tasks/sprint-N/`。写入前先计算本次全部目标路径；目录或任一目标文件已经存在时停止并报告冲突，不覆盖、不合并，也不自行改号。
3. 任务 ID 固定为 `SN-XXX`，其中 `N` 必须与目录一致，`XXX` 从 `001` 连续递增。文件名固定为 `SN-XXX-<kebab-topic>.md`。
4. 同一 Sprint 的 Overview、任务卡和可选输入快照必须保存在同一目录树中。根目录 `docs/tasks/` 不直接存放 Overview 或任务卡。

## 统一输出契约

创建：

- `docs/tasks/sprint-N/00-overview.md`：范围、输入、依赖、里程碑、风险和待决事项。
- `docs/tasks/sprint-N/SN-XXX-<kebab-topic>.md`：可独立执行的任务卡。
- `docs/tasks/sprint-N/.figma-plan/design-context.md`：仅在有 Figma 输入时由 `plan-figma` 设计输入标准化阶段生成。

每张任务卡必须包含：

- 与文件名一致的 `SN-XXX` 标题和任务 ID。
- `executor` frontmatter，只允许 `task-executor` 或 `bridge-engineer`。
- `blockedBy` frontmatter，使用任务 ID 列表，无依赖时为 `[]`。
- `uiSpec` frontmatter：完整用户流程或需要运行态交互验收时为 required，否则为 not-required。
- 输入和事实来源。
- 目标和非目标。
- 精确实现要求。
- 与实现同时编写的测试。
- 验收标准和验证命令。
- 平台或环境限制。

适用时按以下顺序安排基础契约与消费者：协议或持久化 Adapter、Domain Entity、Mapper、API、Controller、装配、Route、UI、集成验证。

uiSpec 为 required 的任务必须在用户批准任务卡后、执行实现前通过 `/plan-spec` 生成并 Review ready Spec。

写入前再次确认目标目录不存在；创建目录和全部规划产物后运行 `make harness-check`。最后汇报 Sprint 编号、创建路径、依赖顺序、待决事项和第一张可执行任务卡。停在实现前，等待用户 Review。
