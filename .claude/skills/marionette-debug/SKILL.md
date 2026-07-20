---
name: marionette-debug
description: "适用：通过仓库 Marionette MCP 连接运行中的 Flutter App，执行临时诊断或由 app-operator 严格按 Spec 回归。不适用：构建/安装 App、操作原生系统 UI、在 Profile/Release 中启用 Binding 或修改代码。触发词：App 卡住、黑屏、路由错误、检查 UI、Marionette、VM Service、App Operator、Spec 回归。"
paths: ["app/apps/**/lib/main.dart", ".mcp.json", ".claude/agents/app-operator.md", "Makefile"]
---

# Marionette 运行时

仓库已提供 `.mcp.json` 和 Demo App Binding。首次 Clone 仍需运行 `make marionette-install` 并批准项目级 MCP Server；不可用时准确报告缺失前置，并改用普通 Flutter 日志/Debugger。

## 公共流程

1. 从调用方获取 `flutter run` 输出中的 `ws://.../ws` VM Service URI。
2. 使用 `marionette` MCP 的 `connect` 连接并确认目标 Flutter Isolate/Binding。
3. 优先使用稳定 Key、Semantics 或稳定文本定位元素，不使用坐标。
4. 任务结束或失败后使用 `disconnect` 断开连接。

Marionette 只操作 Flutter Widget Tree，不操作系统权限弹窗等原生 UI。不得记录 VM Service URI、凭据、设备标识、主机名、用户名或真实用户数据；日志和截图入库前必须脱敏。不得 hot reload 或修改代码。

## 诊断模式

没有行为 Spec、目标是临时定位问题时：

1. 获取当前交互元素，并在支持时截图。
2. 拉取最近日志，与可见状态对照。
3. 只执行复现问题所需的最少交互，不探索无关页面或修改无关 App 数据。
4. 汇报可见状态、日志、复现位置和下一步诊断，不仅凭截图宣称根因。

诊断模式不得自行生成回归通过结论；需要回归验证时交给 `app-operator`。

## Operator 模式

由 `app-operator` 调用且已有 ready Spec、passed Audit 和明确平台时：

1. 行为契约、操作顺序和 Assertion 以 Spec 为唯一依据。
2. 只执行 Spec 的 Step、Assertion 和 Teardown，不做探索动作。
3. 首次失败时采集脱敏截图和最近日志；条件允许时仍执行 Teardown。
4. 按 `ui-behavior-spec` 写入该平台的结构化运行报告，不把临时诊断结果冒充 Spec 通过。
