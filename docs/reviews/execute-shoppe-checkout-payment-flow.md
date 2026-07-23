---
task: shoppe-checkout-payment-flow
status: passed
p0: 0
p1: 0
---

# Shoppe Checkout 与本地支付状态执行 Review

## P0

无。

## P1

无。首轮独立 Review 的 3 个 P1 已修复并通过最终复审：

1. Checkout 已从公共 barrel、`FeaturesRegistry.local()` 和根 Router 接入。Registry 只创建一个 `PaymentProfileStore` 并把同一实例注入 Checkout Handler/DataSource；`/checkout` 位于主 Shell 外，Cart 入口、认证 Deep Link 和 Shell 隔离已有 Demo Router 测试。
2. Attempt ID 改由进程级 `CheckoutFixtureHandler` 通过独立请求确定性分配。不同 Scope 获得不同 ID；同一次成功支付后的 Cart settlement 重试继续使用原 Attempt ID 和 Receipt。
3. Payment pending 与待 Cart settlement 状态使用 `PopScope(canPop: false)`，同时隐藏 AppBar Back。系统 Back 回归测试证明 pending 不会离开 Result Route；完成后才允许进入成功/失败后续状态。

## P2

无未解决 P2：

- `CheckoutApi` 已移除 Checkout UI 不消费的卡片增删与地址删除能力；完整 mutation 仍由 `PaymentProfileStore`/DataSource 持有，后续 Settings 使用自己的 API 边界。
- Widget 测试已补真实非零键盘 Insets、窄屏/横屏/文字缩放下的内容末端几何与固定操作可达性，以及总额、按钮、支付方式 selected 和进度 live-region Semantics。

## 残余风险

- Figma Desktop 当前无法读取节点 `0:6830`、`0:6638`、`0:6503`、`0:6289`、`0:6124`、`0:5936`、`0:5767`、`0:5612`、`0:5461`。本次依据任务卡、已入库设计上下文与现有 Token 实现，尚不能逐节点复核 Overlay、间距和视觉细节。
- 本卡未生成 UI Spec/Audit，也未调用 App Operator；这符合普通任务执行边界。

## 验证摘要

- 证据：[`test-evidence/shoppe-checkout-payment-flow.log`](test-evidence/shoppe-checkout-payment-flow.log)，Exit code 0。
- `make analyze` 通过。
- `app_data/test/checkout` 9 个测试通过。
- `app_features/test/feature_checkout` 16 个测试通过。
- `apps/demo/test/router/checkout_router_test.dart` 3 个测试通过。
- 最终独立复审重新执行以上 28 个聚焦测试，全部通过。
- `make lint`、`make harness-check` 与 `git diff --check` 通过。
