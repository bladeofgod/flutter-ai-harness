---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-checkout-payment-flow, shoppe-profile-dashboard]
---

# 实现 Shoppe Rewards 与 Vouchers

## 背景与输入

- Figma：`0:2120` - `81 Profile Reward`、`0:2004` - `82 My Vouchers`、`0:1873` - `83 Voucher is Gonna Expire`、`0:1731` - `84 Rewards Progress`、`0:1565` - `85 Profile Voucher Reminder`。
- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- Profile Dashboard、Checkout Voucher Domain 与主导航 Shell。

## 目标与非目标

- 实现 Rewards 概览、进度、Voucher 列表和 Profile 提醒状态，并与 Checkout Voucher 选择使用同一 Domain 契约。
- 使用固定本地积分、门槛和到期日期；不接会员系统、推送或墙钟倒计时。
- 本卡不重新实现 Profile 页面或 Checkout Voucher 输入流程。

## 实现要求

1. 重新读取五个节点，确认 81/85 的 Profile 状态差异、82/83 Voucher 状态和 84 Progress 的层级/交互。
2. 在 `app_data` 增加 RewardBalance、RewardTier/Progress 和 Voucher 生命周期当前必要字段；复用 Checkout Voucher 标识、金额/折扣规则，不创建第二套 Voucher。
3. 增加 Rewards LocalDataSource、Mapper、稳定请求键和窄 `RewardsApi`。所有到期日、余额和进度固定且可测试，不使用当前日期自动变化。
4. Rewards Controller 管理 loading/data/empty/error、Voucher 选择/查看和提醒消费；不持有 Profile Controller 或 Checkout 实现。
5. 建立 `/rewards`、`/vouchers` 等最小 Route。81/84 可按结构合并概览与详情；83/85 使用数据状态或 Overlay/Badge，不按画板创建重复页面。
6. Profile Header/Voucher/Reminder 通过公开 Route 与只读摘要 API 接线；Checkout 通过 Voucher ID 使用相同 Fixture，Feature 之间只依赖公共 API/Domain。
7. 进度条、到期提示和 Voucher Card 在窄屏、长文案和文字放大下稳定，颜色先反查现有 Token。

## 同批测试与验收

- Data/API/Controller：余额、进度、Voucher 状态、固定日期、提醒消费、空/错误和重建恢复。
- Widget/Route：81–85 状态合并、Profile 入口、Voucher/Progress 导航、Back、多视口与 Semantics。
- Rewards 与 Checkout 使用同一 Voucher 契约，无实时积分、通知或重复 Entity；Profile 内容不重做。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不接钱包、推送、日历或后台任务。
- UI 自动化由人工独立安排。
