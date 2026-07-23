---
task: shoppe-support-chat
status: passed
p0: 0
p1: 0
---

# Shoppe Support Chat 执行审查

## 问题

未发现剩余 P0、P1 或 P2 问题。

## 复审已解决

- 原 P1 已解决：[`support_fixture_handler.dart`](../../app/packages/app_data/lib/src/support/support_fixture_handler.dart#L184) 现在直接序列化 canonical `shoppeFiveVoucherFixture`；Support Data 测试断言 `voucher-shoppe-five` / `SHOPPE5`，根路由测试从 Chat CTA 进入 `/vouchers` 后能找到同一个 ID。
- 原 P2 已解决：[`support_routes_test.dart`](../../app/packages/app_features/test/feature_support/support_routes_test.dart#L41) 使用角色前缀匹配合并后的完整可访问名称，并比较客户与客服 Bubble 的横向中心；测试现已通过。

## 已确认

- Support 使用 `SupportConversation`、`SupportMessageContent` 和公共 `Voucher` Domain Entity，未复制 Voucher 类型。
- `SupportFixtureHandler`、`SupportLocalDataSource`、Mapper 与窄 `SupportChatApi` 的依赖方向正确；未发现网络、AI、WebSocket、Push 或 `app_im` 实现。
- Controller 使用有限、可注入延迟推进确定性脚本；问题选择、发送和评价都有重复操作保护，`onClose` 通过 generation 使待执行转场失效并清空草稿。
- `/support` 由 Profile 的公开回调进入，Support Feature 未 import Profile 私有实现；根 redirect 已保护未登录深链。
- 消息列表使用 `ListView.builder`，ScrollController 与输入 Focus/Text Controller 都会释放；已有测试覆盖键盘 Insets、横屏/文字缩放、长历史回到底部和 Back 后新会话。

## 验证

- `TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_support`：独立复跑通过，9 项测试。
- 证据中的 `TOOL_WORKDIR=app/packages/app_data bash scripts/dart-tool.sh test test/support test/rewards`：通过，12 项测试。
- `TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/router/account_services_router_test.dart`：通过，6 项测试。
- `git diff --check`：通过。
- 已读取 `docs/reviews/test-evidence/shoppe-support-chat.log`；最新追加的 Support Feature 聚焦测试为 Exit 0，静态分析、边界 lint、`make analyze`、`make harness-check` 和 `git diff --check` 也均为 Exit 0。

## 验证缺口与剩余风险

- Figma Desktop MCP 对节点 `0:3542` 的 `get_design_context` 返回 `Rate limit exceeded, please try again tomorrow`，因此十三张画板的像素、字体、间距和完整视觉一致性本轮无法独立复核；本报告不把绿色静态/Widget 测试等同于 Figma 视觉验收。
- 本轮没有运行 Android/iOS 宿主构建；任务改动是纯 Dart/Flutter 且证据中的全仓静态门禁通过，但平台编译仍由最终批次验收覆盖。

## 摘要

共享 Voucher、根路由、状态机生命周期、消息方向与 Semantics 覆盖均已闭环；当前 P0/P1 为零，任务实现通过独立 Review。
