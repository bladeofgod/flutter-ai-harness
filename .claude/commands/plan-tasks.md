---
description: 将产品或技术输入拆成按依赖排序的任务卡，不做实现
argument-hint: "[需求、文档路径和额外约束]"
---

使用 `architect` 角色创建实现计划，不编写应用代码。

本命令是任务拆解的便捷入口，不是任务卡的唯一生产方式。已有任务卡无论由谁创建，只要符合 `CLAUDE.md` 的文档生命周期和仓库门禁，都可以进入后续执行流程。

## 输入

读取 `$ARGUMENTS`、`CLAUDE.md`、`docs/architecture.md`、相关 App 文档、协议定义和现有代码。

需求包含 Figma URL 或 node-id 时，只复用 `plan-figma` 的“设计输入标准化”阶段读取节点，再返回本命令继续统一规划；不得让两个命令分别生成任务卡。

不得编造无法从产品输入、设计、协议或代码推导出的需求。未确定的产品决策必须显式记录。

## 规划规则

1. 遵守 `CLAUDE.md` 的任务卡生命周期、命名和必要元数据约定。
2. 写入前扫描活动与归档任务，确保名称能区分当前任务且没有冲突；发生重名时使用更清晰的业务范围命名，无法区分时停止并报告。
3. 文件 basename 同时作为依赖、Review、证据和 UI Spec 使用的任务标识。

## 本命令输出

创建：

- `docs/tasks/<task-slug>.md`：可独立执行的任务卡。
- `docs/figma/<context-slug>-design-context.md`：仅在需要标准化 Figma 输入时生成，并由相关任务卡显式引用。

每张任务卡必须包含：

- 准确概括任务内容的一级标题。
- `executor` frontmatter，只允许 `task-executor` 或 `bridge-engineer`。
- `blockedBy` frontmatter，使用任务 slug 列表，无依赖时为 `[]`；禁止重复、自依赖和循环依赖，全部任务必须构成可拓扑排序的 DAG。
- 可选 `securityReview: required` frontmatter。任务引入或改变认证/授权、敏感数据、网络或文件等外部输入、Deep Link/WebView、不可信输入反序列化、平台通道或原生权限、第三方依赖与执行脚本，或者 CI/MCP/Agent 的权限与执行能力时必须声明；普通 DTO 序列化、UI、文案、格式化、纯描述修正和不改变能力或行为的重构不声明。
- 输入和事实来源。
- 目标和非目标。
- 精确实现要求。
- 与实现同时编写的测试。
- 验收标准和验证命令。
- 平台或环境限制。

适用时按以下顺序安排基础契约与消费者：协议或持久化 Adapter、Domain Entity、Mapper、API、Controller、装配、Route、UI、集成验证。

任务卡不得声明 `uiSpec`，也不得默认安排 Spec Auditor 或 App Operator。UI 自动化由人在普通任务流程之外单独调用 `/plan-spec` 与 `/execute-ui-spec`。

`securityReview` 是按风险触发的只读工程门禁，不是 UI 自动化，也不要求低风险任务或每个测试脚本接受人工审批。执行阶段仍会按实际 diff 兜底识别遗漏。

写入前再次确认全部目标文件没有冲突；创建规划产物后运行 `make harness-check`。最后汇报创建路径、依赖顺序、待决事项和第一张可执行任务卡。停在实现前，等待用户 Review。
