---
description: 将一个或多个 Figma 设计拆成符合架构的任务卡，不做实现
argument-hint: "<figma-url>... [feature=feature_name] [额外约束]"
---

把 Figma 设计转换为结构化规划输入，再复用 `plan-tasks` 的唯一 Sprint 与任务卡输出契约。不实现代码，也不修改设计稿。

## 设计输入标准化

1. 确认至少提供一个 Figma URL 或 node-id。
2. 加载 `figma-to-flutter` 和 `flutter-layouts` Skill。
3. 读取 `CLAUDE.md`、`docs/architecture.md`、设计 Token、现有组件、Route、API 和附近测试。
4. 使用项目 `.mcp.json` 中的 `figma` 本地 MCP 读取每个节点；连接不可用时报告 Figma Desktop、Dev Mode 或 Server 前置条件并停止。
5. 提取层级、Auto Layout、尺寸、间距、字体、颜色、组件 Variant、交互、资源和响应式行为。
6. 新增视觉值前，先反查已有代码 Token 和组件。
7. 补齐设计稿无法表达的工程维度：数据归属、状态、导航、加载/错误/空状态、无障碍、埋点、持久化和平台行为。
8. 把设计事实、工程推断、待决问题、节点来源、资源与授权信息整理为 `design-context.md` 的内容；此阶段不创建任务卡。

## 统一规划

1. 完整读取并执行 `plan-tasks` 的“Sprint 分配”和“统一输出契约”，使用 `architect` 确定架构、依赖和任务边界。
2. 将标准化设计内容作为该 Sprint 的输入快照写入 `docs/tasks/sprint-N/.figma-plan/design-context.md`。
3. Overview 和任务卡必须与输入快照位于同一个 `docs/tasks/sprint-N/` 目录树，不得直接写入 `docs/tasks/`，也不得另行定义任务卡格式。
4. 每张卡必须引用准确的 Figma 节点、输入快照和相关代码路径，并区分设计事实与工程推断。

存在设计 Token 时不得写无解释的裸视觉值。资源授权和导出参数未确认前，不得生成正式 Asset。

创建全部产物后运行 `make harness-check`。最后汇报 Sprint 编号、任务顺序、设计缺口、Token/组件新增项和待决问题。停在实现前等待用户 Review。
