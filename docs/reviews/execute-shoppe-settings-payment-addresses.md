---
task: shoppe-settings-payment-addresses
status: passed
p0: 0
p1: 0
---

# Shoppe Settings 支付方式与收货地址执行 Review

## Findings

未发现未解决的 P0、P1 或 P2 问题。

首轮 Review 的 4 个 P1 已修复并通过复审：

1. Settings 创建的掩码 Demo 卡现在具有确定性的本地成功结果，内置 secondary 卡继续保留固定失败演示；Data 回归覆盖 Add、Select、Checkout submit 和 Receipt 的支付方式一致性。
2. Checkout 不再丢弃 load、mutation 或 payment 忙碌期间的 Store 通知。Controller 保存最新 `PaymentProfileSnapshot`，并在各异步流程的 `finally` 中消费；可控 pending payment 测试证明连续通知最终收敛到最后一份快照。
3. Settings Payment Mapper 在边界统一捕获 `FormatException` 和 `ArgumentError`，保留 stack trace 并转换为 `SettingsPaymentFailureCode.invalidResponse`；畸形 overview、卡尾号和 Receipt 日期均有回归。
4. Card number 与 CVV 改用原生 obscured `TextFormField`，不再通过 `ExcludeSemantics` 删除操作能力；测试同时验证完整数字不进入 Semantics，且节点仍具有 `setText`/`tap` 动作。

首轮 Review 的 2 个 P2 也已关闭：

- Settings Payment Controller 测试断言 `onDelete` 后 profile stream listener 归零。
- 根 Router 测试覆盖 Payment/Address 根路径及 Add/Edit 子 Deep Link 的未登录守卫，并验证已登录无效 Edit ID 稳定显示 `Item not found`。

## 架构与行为结论

- `FeaturesRegistry.local()` 只创建一个 `PaymentProfileStore`，Checkout 与 Settings Handler/DataSource 注入同一实例；没有第二份地址或支付方式状态。
- Settings 使用独立请求键和窄 `SettingsPaymentAddressApi`，未 import Checkout Feature 私有实现；跨 Feature 只共享 `app_data` Domain 和根装配回调。
- Store mutation 每次发布一个不可变快照，Checkout/Settings Controller 均通过构造函数接收 API，并在 Scope 销毁时释放订阅。
- Receipt history 只由成功 Checkout 的根 settlement 回调幂等写入；新增卡、地址和历史均为进程内 Fixture，新 Registry 恢复固定初始状态。
- 完整卡号和 CVV 不进入 Domain、Fixture、日志、Evidence 或公共 API；表单提交后及销毁时清空输入，没有接入真实支付、Token、SecureStorage 或数据库。
- `/settings/payment-methods`、Add/Edit Card、`/settings/addresses`、Add/Edit Address 均通过公开 Route 接入，认证前缀守卫覆盖全部子路径。

## 验证

- 证据：[`shoppe-settings-payment-addresses.log`](test-evidence/shoppe-settings-payment-addresses.log)。日志保留修复过程中的失败尝试，最后一轮聚焦测试和所有门禁均为 Exit code 0。
- 入库证据最终覆盖 Settings Payment Data、Settings/Checkout Controller、Settings Route、根 Account Services Router、`make analyze`、`make lint`、`make harness-check` 与 `git diff --check`。
- 独立复审重跑 `app_data/test/settings_payment` 与 `app_data/test/checkout`，17 个测试通过。
- 独立复审重跑 Settings Payment Controller/Route 与 Checkout Controller，20 个测试通过。
- 独立复审重跑 Demo Account Services、Checkout、Settings Router，14 个测试通过。

## 残余风险

- Figma Desktop MCP 在本批执行中受本地文件可用性/限流影响，节点 `0:1206`、`0:1113`、`0:980`、`0:862`、`0:722`、`0:632`、`0:547` 未能逐节点重新核对。本报告不宣称 Add Card Overlay、Payment History、卡片数量状态和地址表单已达到像素级一致。
- 本卡未生成 UI Spec/Audit，也未调用 App Operator；这符合普通任务执行边界。

## 摘要

单一 Payment Profile 状态、Settings/Checkout 即时一致、Receipt history、敏感输入生命周期、Route Scope、Deep Link 守卫和壳层接线均已闭合。当前满足归档条件。
