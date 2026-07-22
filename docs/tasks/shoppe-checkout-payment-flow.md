---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-cart-tab]
---

# 实现 Shoppe Checkout、Voucher 与本地支付状态

## 背景与输入

- Figma：`0:6830` - `48 Payment`、`0:6638` - `49 Add Voucher`、`0:6503` - `50 Voucher Added`、`0:6289` - `51 Edit Shipping Address`、`0:6124` - `52 Choose Payment Method 1 Card`、`0:5936` - `53 Choose Payment Method 2 Cards`、`0:5767` - `54 Payment in Progress`、`0:5612` - `55 Couldn't Proceed Payment`、`0:5461` - `56 Your Card Been Charged`。
- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- Cart/Money Domain、Cart API 与主导航 Shell。

## 目标与非目标

- 实现从非空 Cart 进入的 Checkout、Voucher、地址、支付方式和成功/失败状态链。
- 使用进程内确定性 Demo 数据，不接支付 SDK、真实银行卡、远程 Voucher、地图或地址服务。
- 本卡不实现订单列表/物流页面；成功只产生稳定 Checkout Receipt，后续 Orders 任务负责接入活动历史。

## 实现要求

1. 重新读取九个节点，确认页面/Overlay 关系、金额摘要、Voucher 状态、地址表单、卡片选择和 54–56 转场/返回行为。
2. 在 `app_data` 定义 CheckoutSession、ShippingAddress、PaymentMethod 摘要、PaymentProfileSnapshot、Voucher、Receipt 和 PaymentState 当前必要字段；金额复用 Money，不保存 CVV、完整真实卡号或 Token。
3. 作为地址/支付方式的首个消费者，在 `app_data` 建立纯 Dart、进程级 `PaymentProfileStore`。它独占不可变地址/支付方式快照、Add/Edit/Remove/Select mutation 和单次状态通知；重建恢复固定 Fixture，不依赖 Flutter、Feature API 或裸共享 Map。
4. `FeaturesRegistry.local()` 只创建一个 PaymentProfileStore，并注入 Checkout Handler/DataSource；后续 Settings 复用同一实例。Checkout Attempt、Voucher 和支付结果仍由 Checkout Handler 拥有，不能放入共享 Store。
5. 增加 Checkout Feature Handler、LocalDataSource、Mapper、稳定请求键与窄 `CheckoutApi`。本地 Fixture 通过 Store 提供固定地址、掩码主卡和第二张掩码卡，并由 Checkout Handler 提供 Voucher/支付场景；主卡的私有 Fixture Outcome 固定成功，第二张卡固定失败，Domain/UI 不显示“失败卡”标签且结果不随机。
6. Checkout Controller 通过构造函数接收已经稳定的 `CartApi` 与 `CheckoutApi`，管理 Session、地址、Voucher、支付方式、提交去重和状态；不得扩展 Cart 契约。空 Cart direct link 必须同步/确定性回到 Cart。
7. `49/50` 是 Voucher 编辑/成功状态，`52/53` 是支付方式数量状态，`54/55/56` 是同一支付尝试的状态机。只为真实页面建立 Route，不按每张状态画板创建 Route。
8. `/checkout`、Voucher、Address、Payment Method 和 Result 子 Route 共享同一 Checkout Scope；Back/Cancel 保留或清理草稿的规则明确，离开整个流程释放敏感输入。
9. Payment in Progress 只存在于异步调用 pending 期间，Fixture 使用固定可测试短延迟且测试 Fake 可控制完成；不得用随机 Timer。主卡成功后生成稳定 Receipt，并按 Checkout Attempt ID 调用 Cart 原子幂等清空；第二张卡失败时保留 Cart/Checkout，用户切换主卡后可重试。
10. 节点 56 保留布局但主文案使用 `Demo payment completed`，辅助文案明确没有真实扣款；设计上下文记录该主动偏离。失败页不得暗示银行真实拒付或产生外部交易。
11. 地址编辑做本地字段校验；Payment Method 只选择 Store 已有掩码 Fixture，本卡不实现 Add/Edit Card。Checkout 订阅 Store 时必须在 Scope 销毁时释放，单次 mutation 只产生一个一致快照。
12. 固定底部操作、键盘 Insets、长地址、错误/重试和多视口下可达；日志、Semantics、Evidence 不包含地址详情以外的敏感支付输入。

## 同批测试与验收

- Domain/Data/API：金额、Voucher、PaymentProfileStore 单一实例/不可变快照/单次通知、地址、主卡成功/第二卡失败映射、Attempt 幂等、Receipt、重建恢复和脱敏。
- Controller/Route：空 Cart Guard、Scope 生命周期、草稿、重复支付、失败重试、成功清 Cart、Back/Cancel。
- Widget：48–56 状态合并、表单键盘、长文本、多视口、加载/错误和 Semantics。
- 跨消费者：同一 Registry 中通过 Settings 侧测试 Adapter 修改 Store 后，Checkout 读取相同快照；新 Registry 恢复固定地址/卡片，证明没有双写或静态泄漏。
- 全流程可本地演示，无支付 SDK、随机结果、真实卡数据或伪远程请求。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不接 Apple Pay、Google Pay、银行卡扫描、地图或定位。
- UI 自动化由人工独立安排。
