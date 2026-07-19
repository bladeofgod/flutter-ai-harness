---
name: marionette-debug
description: "适用：通过仓库 Marionette MCP 临时诊断运行中的 Flutter App，包括日志、截图和交互元素。不适用：执行回归 Spec 或修改代码；脚本回归使用 app-operator。触发词：App 卡住、黑屏、路由错误、检查 UI、Marionette、VM Service。"
paths: ["app/apps/**/lib/main.dart", ".mcp.json", ".claude/agents/app-operator.md", "Makefile"]
---

# Marionette 运行时诊断

仓库已提供 `.mcp.json` 和 Demo App Binding。首次 Clone 仍需运行 `make marionette-install` 并批准项目级 MCP Server；不可用时准确报告缺失前置，并改用普通 Flutter 日志/Debugger。

## 流程

1. 从调用方获取 `flutter run` 输出中的 `ws://.../ws` VM Service URI。
2. 使用 `marionette` MCP 的 `connect` 连接并确认目标 Flutter Isolate/Binding。
3. 获取当前交互元素，并在支持时截图。
4. 拉取最近日志，与可见状态对照。
5. 只执行复现问题所需的最少交互。
6. 使用 `disconnect` 断开连接，汇报状态、日志、复现位置和下一步诊断。

不得探索无关页面、修改 App 数据、执行 Spec、hot reload，也不得仅凭截图宣称根因。存在稳定文本/Key 时避免坐标操作。
