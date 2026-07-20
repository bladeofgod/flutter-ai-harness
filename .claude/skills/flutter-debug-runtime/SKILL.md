---
name: flutter-debug-runtime
description: "适用：在 App Operator 或 Marionette 验证前，为 Android/iOS 构建、安装并启动 Flutter Debug App，获取 VM Service URI。不适用：Release 构建、签名配置、系统权限自动化、账号登录或测试数据准备。触发词：flutter run、Debug App、设备安装、VM Service URI、App Operator 前置环境。"
paths: ["app/apps/**/lib/main.dart", "app/apps/**/android/**", "app/apps/**/ios/**", ".claude/commands/execute-tasks.md", ".mcp.json", "scripts/flutter-tool.sh"]
---

# Flutter Debug Runtime

为运行态 UI 验证准备 App；完成交接后由 `app-operator` 专注执行 Spec。

## 流程

1. 读取任务卡和 Spec 的 `platforms`，确认本次目标平台。
2. 运行 `bash scripts/flutter-tool.sh devices`，选择用户指定设备；存在多个候选且用户未指定时请求选择。
3. 依赖发生变化时先运行 `bash scripts/dart-tool.sh pub get`。
4. 使用以下入口构建、安装并保持 Debug App 运行：

   ```bash
   TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh run --debug -d <device-id>
   ```

5. 从输出中取得 `ws://.../ws` VM Service URI，只在当前调用中交给 Operator，不写入仓库产物。
6. 确认 App 启动且 Marionette Binding 可连接后完成交接。

不得修改签名、Development Team、应用标识或发布配置。设备不可用、系统权限弹窗阻塞、账号/测试数据缺失或平台工具链需要人工处理时，准确说明阻塞并请求介入，不用伪造状态或产品行为绕过。
