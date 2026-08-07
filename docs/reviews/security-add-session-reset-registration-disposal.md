---
task: add-session-reset-registration-disposal
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/apps/demo/lib/auth/auth_state.dart
  - app/apps/demo/lib/demo_app.dart
  - app/apps/demo/test/auth/auth_state_test.dart
  - app/apps/demo/test/demo_app_test.dart
  - docs/infrastructure/session.md
implementationDigest: aa62aa1eaf52fefc15deb0458e88c69a02f4fc6e050aa553dcbdcc01c0973b9c
---

# Security Review：为 Session Reset 注册增加解除生命周期

## 首轮问题

### P1：卸载期间 logout 后复用外部 Registry 可能保留上一用户数据

- 资产：购物车、Wishlist、支付设置、客服消息和媒体草稿等会话数据。
- 路径：App 卸载后必须解除自己的注册且不得再触碰外部 Registry；若外部 Coordinator 此时 logout，
  同一 Registry 重新挂载前需要补做会话清理。
- 修法：外部 Registry 使用已登出 Coordinator 挂载时，在注册新 reset 前主动清理一次；测试覆盖
  卸载、外部 logout、同一 Registry 重挂载的完整路径。

### P1：Reset 异常或重入可能阻断登出

- 资产：认证 Session、当前 User 与后续 Feature 清理回调。
- 路径：同步 reset 在认证状态清空前执行，异常会跳过剩余清理，重入 logout 会递归分发。
- 修法：增加 logout 进行中保护；逐个捕获 reset 异常并保存脱敏 `FlutterErrorDetails`，完成全部 reset、
  状态清空和通知后再上报。

## 修复与安全复审

- 卸载期间的 logout 仍不会调用已解除的旧 Registry，保持对象所有权边界；重挂载安全默认值会清除
  保留 Registry 的旧会话数据。
- Reset 失败只上报 `SessionResetFailure(<redacted>)`，不携带原始异常文本；后续 reset、认证清空和通知
  继续执行。
- `_isLoggingOut` 在 `finally` 中复位，回调重入不会递归，也不会改变通知次数。
- 未增加网络、文件、凭据、原生能力、Agent 或 MCP 边界；外部 Coordinator/Registry 仍不由 App dispose。
- 两份绑定 `DemoApp` 的历史媒体安全报告已完成影响复审并更新摘要。

最终 P0/P1/P2 为 0/0/0。完整验收输出记录于本任务证据文件。
