---
description: 将产品或技术输入拆成按依赖排序的任务卡，不做实现
argument-hint: "[需求、文档路径和额外约束]"
---

使用 `architect` 角色创建实现计划，不编写应用代码。

## 输入

读取 `$ARGUMENTS`、`CLAUDE.md`、`docs/architecture.md`、相关 App 文档、协议定义和现有代码。

需求包含 Figma URL 或 node-id 时，只复用 `plan-figma` 的“设计输入标准化”阶段读取节点，再返回本命令继续统一规划；不得让两个命令分别生成任务卡。

不得编造无法从产品输入、设计、协议或代码推导出的需求。未确定的产品决策必须显式记录。

## 任务命名与位置

1. 未完成任务直接写入 `docs/tasks/<task-slug>.md`；完成后由 `execute-tasks` 移入 `docs/tasks/done/`。
2. `task-slug` 使用 lowercase kebab-case，必须准确概括任务内容，并在活动与归档任务中全局唯一；文件 basename 同时作为依赖、Review、证据和 UI Spec 使用的任务标识。
3. 写入前计算本次全部目标路径，并扫描 `docs/tasks/*.md` 与 `docs/tasks/done/*.md` 检查重名；任一目标已存在时停止并报告冲突，不覆盖、不合并，也不添加无语义编号规避冲突。
4. `docs/tasks/` 下只允许 `done/` 子目录，不创建 Overview、批次目录、输入快照目录或其他任务分组目录。

## 统一输出契约

创建：

- `docs/tasks/<task-slug>.md`：可独立执行的任务卡。
- `docs/figma/<context-slug>-design-context.md`：仅在有 Figma 输入时由 `plan-figma` 生成，并由相关任务卡显式引用。

每张任务卡必须包含：

- 准确概括任务内容的一级标题。
- `executor` frontmatter，只允许 `task-executor` 或 `bridge-engineer`。
- `blockedBy` frontmatter，使用任务 slug 列表，无依赖时为 `[]`；禁止重复、自依赖和循环依赖，全部任务必须构成可拓扑排序的 DAG。
- `uiSpec` frontmatter：完整用户流程或需要运行态交互验收时为 required，否则为 not-required。
- 输入和事实来源。
- 目标和非目标。
- 精确实现要求。
- 与实现同时编写的测试。
- 验收标准和验证命令。
- 平台或环境限制。

适用时按以下顺序安排基础契约与消费者：协议或持久化 Adapter、Domain Entity、Mapper、API、Controller、装配、Route、UI、集成验证。

uiSpec 为 required 的任务必须在用户批准任务卡后、执行实现前通过 `/plan-spec` 生成；机器校验通过且没有待决问题时状态为 ready。

写入前再次确认全部目标文件不存在；创建规划产物后运行 `make harness-check`。最后汇报创建路径、依赖顺序、待决事项和第一张可执行任务卡。停在实现前，等待用户 Review。
