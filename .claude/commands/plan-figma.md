---
description: 将一个或多个 Figma 设计拆成符合架构的任务卡，不做实现
argument-hint: "<figma-url>... [feature=feature_name] [额外约束]"
---

把 Figma 设计转为可执行任务卡，不实现代码，也不修改设计稿。

## 流程

1. 确认至少提供一个 Figma URL 或 node-id。
2. 加载 `figma-to-flutter` 和 `flutter-layouts` Skill。
3. 读取 `CLAUDE.md`、`docs/architecture.md`、设计 Token、现有组件、Route、API 和附近测试。
4. 使用项目 `.mcp.json` 中的 `figma` 本地 MCP 读取每个节点；连接不可用时报告 Figma Desktop、Dev Mode 或 Server 前置条件并停止。
5. 提取层级、Auto Layout、尺寸、间距、字体、颜色、组件 Variant、交互、资源和响应式行为。
6. 新增视觉值前，先反查已有代码 Token 和组件。
7. 补齐设计稿无法表达的工程维度：数据归属、状态、导航、加载/错误/空状态、无障碍、埋点、持久化和平台行为。
8. 使用 `architect` 确定架构和任务边界。

## 产物

在 `docs/tasks/.figma-plan/` 写入输入快照，在 `docs/tasks/` 写入任务卡。每张卡必须引用准确的 Figma 节点和相关代码路径，列出测试，并区分设计事实与工程推断。

存在设计 Token 时不得写无解释的裸视觉值。资源授权和导出参数未确认前，不得生成正式 Asset。

最后汇报任务顺序、设计缺口、Token/组件新增项和待决问题。停在实现前等待用户 Review。
