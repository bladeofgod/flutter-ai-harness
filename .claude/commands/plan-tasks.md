---
description: 将产品或技术输入拆成按依赖排序的任务卡，不做实现
argument-hint: "[需求、文档路径和额外约束]"
---

使用 `architect` 角色创建实现计划，不编写应用代码。

## 输入

读取 `$ARGUMENTS`、`CLAUDE.md`、`docs/architecture.md`、相关 App 文档、协议定义和现有代码。需求包含设计链接时，加载 `figma-to-flutter` 并读取对应节点。

不得编造无法从产品输入、设计、协议或代码推导出的需求。未确定的产品决策必须显式记录。

## 输出

创建：

- `docs/tasks/00-overview.md`：范围、依赖、里程碑和风险。
- `docs/tasks/sprint-N/SN-XXX-<topic>.md`：可独立执行的任务卡。

每张任务卡必须包含：

- `executor` frontmatter：`task-executor` 或 `bridge-engineer`。
- 依赖和阻塞项。
- 输入和事实来源。
- 目标和非目标。
- 精确实现要求。
- 与实现同时编写的测试。
- 验收标准和验证命令。
- 平台或环境限制。

适用时按以下顺序安排基础契约与消费者：协议或持久化 Adapter、Domain Entity、Mapper、API、Controller、装配、Route、UI、集成验证。

最后汇报创建路径、依赖顺序、待决事项和第一张可执行任务卡。停在实现前，等待用户 Review。
