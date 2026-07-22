---
executor: task-executor
blockedBy: [shoppe-settings-profile-preferences, shoppe-checkout-payment-flow]
---

# 实现 Shoppe Settings 支付方式与收货地址

## 背景与输入

- Figma：`0:1206` - `89 Settings Add Card`、`0:1113` - `90 Settings Add Card Pop-Up`、`0:980` - `91 Edit Card`、`0:862` - `92 Payment Methods + History`、`0:722` - `93 Payment Methods + History 2 Cards`、`0:632` - `94 Shipping Address`、`0:547` - `95 Edit Shipping Address`。
- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- Settings 根 Route、Checkout 的 ShippingAddress/PaymentMethod/Receipt 契约。

## 目标与非目标

- 实现 Settings 内 Add/Edit Card、Payment Methods/History、Shipping Address 列表与编辑。
- 复用 Checkout 公共 Domain 和 Registry 提供的唯一 PaymentProfileStore，不建立第二套地址、支付方式或历史模型。
- 本卡不接真实银行卡、支付 SDK、地址服务、SecureStorage 或数据库。

## 实现要求

1. 重新读取七个节点，确认 89/90、92/93 的页面/状态/Overlay 关系、Card 字段、History 结构和 94/95 地址流程。
2. 扩展 Settings API 或增加窄 Settings Payment/Address API，复用 Checkout ShippingAddress、PaymentMethod、PaymentProfileSnapshot 与 Receipt。Card 输入使用显式脱敏 Value Object，诊断不得展开完整号码、CVV 或绝对用户数据。
3. `FeaturesRegistry.local()` 把 Checkout 已创建的同一个 PaymentProfileStore 注入 Settings Payment/Address Handler/DataSource。Settings Handler 只拥有自己的请求键和 Payload，不保存第二份卡片/地址状态，也不得通过 Checkout Feature 私有 API 修改数据。
4. Add/Edit/Remove/Select 全部委托 Store mutation；每次成功 mutation 只发布一个不可变一致快照。Checkout 正在观察时同步获得同一状态，新 Registry 恢复固定 Fixture；禁止双写、裸 Map 或全局静态 Store。
5. 建立 `/settings/payment-methods`、Add/Edit Card、`/settings/addresses`、Edit Address 子 Route，并从 Settings 根列表接入；壳工程/Feature 只使用公开入口。
6. `89/90` 是 Add Card 与确认/结果 Overlay，`92/93` 是卡片数量状态，不创建重复 Route。支付历史只展示本地 Checkout Receipt，不伪造银行交易。
7. Card Add/Edit 做 Demo 格式校验、掩码显示和提交去重；敏感输入离开流程即清空，不写日志、Semantics 或 Evidence。没有真实 Token 化或扣款能力。
8. Address Add/Edit 复用 Checkout 校验和 Domain；更新后 Cart/Checkout/Settings 的地址摘要一致，不通过跨 Feature 私有 import 同步。
9. Controller/页面对 Store/API 的订阅必须在销毁时释放；表单键盘 Insets、错误、长地址、空列表、Back/Cancel、窄屏和文字放大状态可达。

## 同批测试与验收

- Data/API/Controller：唯一 Store 实例、不可变快照/单次通知、Card 脱敏、Add/Edit/Remove、Address、Receipt History、跨 Checkout 即时一致、重建恢复和失败。
- Widget/Route：89–95 状态合并、Settings 入口、Overlay、表单、Cancel/Back、键盘、多视口和 Semantics 脱敏。
- Checkout/Settings 使用同一公共契约，无真实支付、持久化、重复 Entity 或敏感诊断。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不接银行卡扫描、Apple Pay、Google Pay、Keychain/Keystore、地图或定位。
- UI 自动化由人工独立安排。
