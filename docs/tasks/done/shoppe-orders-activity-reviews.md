---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-checkout-payment-flow]
---

# 实现 Shoppe 订单活动、物流与评价流程

## 背景与输入

- Figma：`0:5267` - `57 To Receive`、`0:5015` - `58 Review Option`、`0:4764` - `59 To Receive Progress`、`0:4882` - `60 To Receive Attempt Is Not Successful`、`0:4602` - `61 Delivery Attempt Notification`、`0:4445` - `62 Profile To Receive Notification`、`0:4312` - `63 Delivered`、`0:4135` - `64 My Activity`、`0:3996` - `65 History`、`0:3807` - `66 Review`、`0:3628` - `67 Review Done`。
- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- Checkout Receipt、Product/Money、Profile 当前用户与主导航 Shell。

## 目标与非目标

- 实现 My Activity、订单详情/物流状态、历史和本地评价提交。
- Checkout 成功 Receipt 可进入当前进程订单列表；固定 Fixture 同时覆盖设计中的其他物流状态。
- 本卡不接物流服务、推送、后台任务或远程评价系统。

## 实现要求

1. 重新读取十一节点，确认 57–63 的同订单状态关系、61/62 通知呈现、64/65 Tab/筛选和 66/67 评价提交关系。
2. 把 Profile Domain 已有的 `OrderStatus`、`OrderStatusSummary`、`OrderSummary` 迁入/扩展为共享 Orders Domain，并保持 Profile Mapper、API 和 UI 兼容；再增加 Order、OrderLine、FulfillmentStep、ActivityFilter 和 ProductReview 当前必要字段。复用 ProductSummary、Money、Address 摘要与 Checkout Receipt，不重新定义同名状态。
3. 增加 Orders LocalDataSource、Mapper、稳定请求键与窄 `OrdersApi`，提供固定订单状态和接收 Checkout Receipt 的进程内入口；不得使用时间推进或随机状态变化。
4. Orders/Activity Controller 通过构造函数接收 `OrdersApi`，管理状态筛选、详情、通知 Overlay、评价草稿/提交、空/错误和重复操作。
5. `/activity` 显示 64/65 的活动与历史状态；`/orders/:orderId` 依据 Domain 状态渲染 57–63，不为每个物流状态创建 Route。
6. 61/62 若为通知 Overlay/Badge，使用单一可消费状态并测试关闭/重复显示；不申请系统通知权限，不伪造推送到达。
7. `66/67` 使用 `/orders/:orderId/review` 的表单与完成状态，提交只写入内存 Orders API；敏感文本不写日志，重复提交有稳定行为。
8. Profile 的 My Activity、To Receive、To Review 等现有入口通过公开 Route/API 接线；不得让 Profile import Orders 私有实现。
9. Checkout 成功后由公开 API/根装配把 Receipt 加入 Orders；失败支付不创建订单，登出/重启按 Demo 规则恢复固定 Fixture。

## 同批测试与验收

- Data/API：固定状态、Receipt 转订单、筛选、通知消费、评价、重建恢复和 Mapper 失败。
- Controller/Widget/Route：57–67 状态映射、Profile 入口、Activity/History、通知、评价提交、Back、多视口和空/错误。
- 不存在十一条重复 Route、系统通知或自动物流推进；Checkout、Profile、Product 回归通过。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不申请通知、后台刷新、定位或物流权限。
- UI 自动化由人工独立安排。
