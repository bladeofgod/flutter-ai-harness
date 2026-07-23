---
task: shoppe-wishlist-recently-viewed
status: passed
p0: 0
p1: 0
---

# Shoppe Wishlist 与 Recently Viewed 独立 Review

## Findings

未发现未解决问题。

## 已确认行为

- Wishlist/Recently Viewed 复用 Catalog 的 `ProductSummary` 和 `Money`，没有复制商品 Entity。
- Fixture 日期固定为 2026-04-19，不读取系统时钟；Handler 实例隔离且重建恢复初始状态。
- Domain、Mapper、LocalDataSource、Feature API、Controller、Page 分层成立，Controller 使用构造函数注入。
- `/wishlist/recently-viewed` 是 `/wishlist` 的 child Route；日历打开时 Back 先取消 pending selection，再次 Back 返回 Wishlist。
- Product/Cart 边界没有反向 import 目标 Feature 内部实现；仓库扫描未发现 `package:app_data/src/` 或跨 Feature 私有 import。
- 任务证据 exit 0，覆盖 Analyze、Data/API/Controller/Widget 聚焦测试和 Repository Boundary lint；Reviewer 另行运行 `git diff --check` 通过。

## 已关闭问题

### 已关闭：并发删除的旧响应覆盖较新的 Wishlist 状态

- [`wishlist_controller.dart`](../../app/packages/app_features/lib/feature_wishlist/controllers/wishlist_controller.dart#L72) 现在记录所有已提交删除的稳定 product ID，并在每个完整响应写回前统一过滤，乱序响应不会重新带回已删除项。
- [`wishlist_controllers_test.dart`](../../app/packages/app_features/test/feature_wishlist/wishlist_controllers_test.dart#L57) 使用两个 `Completer` 逆序完成不同商品的删除响应，并断言最终列表为空。

### 已关闭：空态 `See All` 与推荐商品是空操作

- [`wishlist_page.dart`](../../app/packages/app_features/lib/feature_wishlist/pages/wishlist_page.dart#L93) 将 `See All` 接入公开 `onSeeAllRecommendations` 回调，并为未接目标保留明确 Snackbar；推荐卡通过稳定 product ID 复用 `onOpenProduct` 边界。
- [`wishlist_pages_test.dart`](../../app/packages/app_features/test/feature_wishlist/wishlist_pages_test.dart#L81) 验证两个入口各触发一次并传出正确 product ID。

### 已关闭：Recently Viewed 缺少响应式测试与日期选中语义

- [`wishlist_pages_test.dart`](../../app/packages/app_features/test/feature_wishlist/wishlist_pages_test.dart#L193) 现在在 320 x 568、812 x 375 和 375 x 812 + 1.3 倍文字下进入 Recently Viewed、展开日历并检查无布局异常。
- [`wishlist_components.dart`](../../app/packages/app_features/lib/feature_wishlist/widgets/wishlist_components.dart#L335) 和 [`recently_viewed_calendar.dart`](../../app/packages/app_features/lib/feature_wishlist/widgets/recently_viewed_calendar.dart#L179) 分别为日期 Chip 与 CalendarDay 暴露 button、selected 和完整日期语义；Route 测试校验 Today 与选中日期的语义状态。

## 验证缺口

- 当前证据没有 Android/iOS 真机视觉比对；按项目契约，UI 自动化不属于普通任务默认门禁。
- 最新 [`shoppe-wishlist-recently-viewed.log`](./test-evidence/shoppe-wishlist-recently-viewed.log) 记录 exit 0，覆盖 Analyze、Data 8 项、Feature 14 项和 Repository Boundary lint。
- Reviewer 复跑 `repository-boundaries.sh`、私有 import 扫描与 `git diff --check`：通过。

## 摘要

数据边界、固定 Fixture 日期、Route/Back、mutation 一致性、公开操作边界、响应式布局证据与日期语义均成立。最终 Review 结论为 `passed`，未发现未解决问题。
