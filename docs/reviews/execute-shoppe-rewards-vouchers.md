---
task: shoppe-rewards-vouchers
status: passed
p0: 0
p1: 0
---

# Shoppe Rewards 与 Vouchers 最终 Review

## Findings

### P2：Checkout Voucher 输入页仍手写 Demo Voucher 提示

- 影响：业务校验和 Rewards 展示已经共用 canonical Voucher，但 Checkout 输入页仍独立写死 `SHOPPE5` 与 `$10`。以后调整 canonical Fixture 时，实际规则和帮助文案可能出现低风险展示漂移。
- 证据：[voucher_page.dart:82](../../app/packages/app_features/lib/feature_checkout/pages/voucher_page.dart#L82) 写死输入提示，[voucher_page.dart:95](../../app/packages/app_features/lib/feature_checkout/pages/voucher_page.dart#L95) 写死 code 和最低消费；真正的事实源位于 [shoppe_voucher_fixture.dart:5](../../app/packages/app_data/lib/src/fixture/shoppe_voucher_fixture.dart#L5)。
- 建议：后续让 Checkout 的公共只读会话/配置提供 Demo Voucher 提示，或改为不包含具体 code 与门槛的通用帮助文案。该文案不参与校验，不阻断本任务归档。

## 原 Findings 复审

### Profile 只读摘要与实时更新：已修复

- [rewards_api.dart:4](../../app/packages/app_features/lib/api/rewards_api.dart#L4) 拆出只读 `RewardsSummaryApi`，Profile 不再获得提醒 mutation 能力。
- [profile_rewards_summary_controller.dart:45](../../app/packages/app_features/lib/feature_profile/controllers/profile_rewards_summary_controller.dart#L45) 订阅摘要更新；revision 防止较慢的初始 load 覆盖较新的 mutation，[profile_rewards_summary_controller.dart:89](../../app/packages/app_features/lib/feature_profile/controllers/profile_rewards_summary_controller.dart#L89) 在 `onClose` 取消订阅。
- [profile_rewards_summary_controller_test.dart:8](../../app/packages/app_features/test/feature_profile/profile_rewards_summary_controller_test.dart#L8) 覆盖更新与订阅释放；[account_services_router_test.dart:37](../../app/apps/demo/test/router/account_services_router_test.dart#L37) 覆盖 `Profile -> Rewards -> 消费提醒 -> Back -> Profile 摘要更新` 的根路由链路。

### Voucher canonical 事实源：已修复

- [shoppe_voucher_fixture.dart:4](../../app/packages/app_data/lib/src/fixture/shoppe_voucher_fixture.dart#L4) 成为 Shoppe $5 Voucher 的唯一生产 Fixture。
- Checkout 在 [checkout_fixture_handler.dart:90](../../app/packages/app_data/lib/src/checkout/checkout_fixture_handler.dart#L90) 使用该对象校验 code、ID、币种和最低消费；Rewards 在 [rewards_fixture_handler.dart:76](../../app/packages/app_data/lib/src/rewards/rewards_fixture_handler.dart#L76) 从同一对象生成 Payload，只追加 lifecycle、到期日与提醒状态。
- [rewards_local_data_source_test.dart:40](../../app/packages/app_data/test/rewards/rewards_local_data_source_test.dart#L40) 直接以 Rewards 返回的 ID 调用 Checkout `applyVoucherById`，覆盖共享规则链路。

### 严格提醒消费失败：已修复

- [rewards_fixture_handler.dart:40](../../app/packages/app_data/lib/src/rewards/rewards_fixture_handler.dart#L40) 对非 expiring 或已消费提醒返回稳定 `rewards.reminder_unavailable`；DataSource 映射为 `RewardsFailureCode.reminderUnavailable`。
- [rewards_local_data_source_test.dart:91](../../app/packages/app_data/test/rewards/rewards_local_data_source_test.dart#L91) 覆盖重复消费和两个非 expiring Voucher。

### Unexpected Error 可重试状态：已修复

- [rewards_controller.dart:146](../../app/packages/app_features/lib/feature_rewards/controllers/rewards_controller.dart#L146) 将意外异常发布为 `RewardsError(unexpected)`，同时保留 Flutter 错误诊断。
- [rewards_controller_test.dart:51](../../app/packages/app_features/test/feature_rewards/rewards_controller_test.dart#L51) 验证错误态、诊断上报和后续 retry 恢复。

## 验证

- Reviewer 在当前工作树重跑 Rewards/Checkout Data 测试：16 项通过。
- Reviewer 重跑 Rewards、Profile 摘要/Profile 页面、Checkout Controller/Route 测试：41 项通过。
- Reviewer 重跑 Demo 根 account services Router 测试：6 项通过。
- `make analyze`、`make lint`、`make harness-check`、`git diff --check`：全部通过。
- 最新落盘证据见 [shoppe-rewards-vouchers.log](./test-evidence/shoppe-rewards-vouchers.log)；最后一组聚焦测试和全部仓库门禁均为 `Exit code: 0`。

## 剩余视觉风险

- Figma Desktop MCP 对 `0:2120`、`0:2004`、`0:1873`、`0:1731`、`0:1565` 返回当日 rate limit，因此本轮无法对当前实现进行逐节点像素与交互复核。这是视觉验证缺口，不作为代码行为通过或失败的推断依据。
- 未运行 App Operator；符合任务卡约定，UI 自动化由人工独立安排，不是本任务归档门禁。

## 结论

原 2 个 P1 与 2 个 P2 均已修复。公共 Voucher 契约、`voucherId -> Checkout`、Profile 只读摘要更新、Controller 生命周期、Route guard 和测试证据逻辑自洽；当前 P0/P1 为 0，可以归档任务卡。
