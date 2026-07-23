---
task: shoppe-orders-activity-reviews
status: passed
p0: 0
p1: 0
---

# Shoppe 订单活动、物流与评价执行 Review

## Findings

未发现 P0 或 P1 问题。

## 已关闭问题

### Checkout 与 Orders 的结算顺序

- [`CheckoutController`](../../app/packages/app_features/lib/feature_checkout/controllers/checkout_controller.dart#L245) 先把成功 Receipt 与结算开始时的 Cart 快照交给注入的 `onReceiptReady`，Orders 接收完成后才清空 Cart。
- Receipt sink 失败会保留 `_pendingSettlement` 和 Cart；[`retry`](../../app/packages/app_features/lib/feature_checkout/controllers/checkout_controller.dart#L186) 使用同一 Receipt/attempt 继续结算，不会再次提交支付。
- Demo 根装配在 [`demo_router.dart`](../../app/apps/demo/lib/router/demo_router.dart#L63) 注入公开回调，并在 [`_acceptReceipt`](../../app/apps/demo/lib/router/demo_router.dart#L187) 把真实 Cart 行映射为 `OrderLine`。Orders 以 Receipt ID 幂等接收，回调成功而 Cart 清理失败时重复调用不会产生重复订单。
- [`checkout_controller_test.dart`](../../app/packages/app_features/test/feature_checkout/checkout_controller_test.dart#L170) 覆盖写入早于清 Cart、真实商品快照、sink 失败保留 Cart、同一成功支付重试和不重复支付；失败支付保留 Cart 的既有回归仍通过。

### Profile My Activity 入口

- [`ProfileDashboardPage`](../../app/packages/app_features/lib/feature_profile/pages/profile_dashboard_page.dart#L44) 暴露独立 `onOpenActivity`，顶部入口使用稳定 Key `profile-open-activity` 并沿 [`buildProfileRoutes`](../../app/packages/app_features/lib/feature_profile/routes.dart#L17) 公开传递。
- Demo 根路由把该回调接到 `/activity`；[`settings_router_test.dart`](../../app/apps/demo/test/router/settings_router_test.dart#L133) 已验证从 Profile 点击后进入 Orders Activity 且离开主导航 Shell。

## 验证

- 已读取证据：[`shoppe-orders-activity-reviews.log`](./test-evidence/shoppe-orders-activity-reviews.log)，记录命令退出码为 0。
- 独立复跑 `app_data` Orders/Profile/Checkout：通过，共 28 项。
- 独立复跑 `app_features` Orders/Profile/Checkout：通过，共 43 项。
- 独立复跑 Demo Discovery/Settings/Checkout 路由：通过，共 11 项。
- `make analyze`、`make lint`、`make harness-check`、`git diff --check`：全部通过。

## P2 与剩余风险

- Demo 根路由对 Receipt 与真实 Cart 行的映射目前由 Controller sink 测试、Orders 幂等测试和装配代码共同覆盖，尚无一条从支付按钮一路断言到 Activity 新订单内容的完整 Widget 测试；这是非阻断测试增强项。
- `FulfillmentStatus.inTransit` 已有 Mapper 和 UI 文案，但固定 Fixture 尚未直接提供该状态，当前没有对该状态的确定性 Widget 映射断言。
- Figma Desktop 未提供目标节点且本地 MCP 曾限流，57–67 的精确视觉、Asset 和标注未在本轮复审中重新逐节点核对。

## 摘要

Orders 的 Domain、Fixture Transport、窄 API、状态驱动路由、通知消费和评价幂等保持自洽。Checkout 与 Orders 的结算一致性、真实商品行传递以及 Profile 主入口均已接通，静态门禁与聚焦回归通过，可以归档。
