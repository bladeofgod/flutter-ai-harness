---
task: shoppe-product-details-reviews
status: passed
p0: 0
p1: 0
---

# Shoppe 商品详情与评价执行 Review

## P0

无。

## P1

无。

## 已关闭的首轮 P1

1. **根壳装配与 Deep Link**：`ProductApi`、Route 工厂和位置 Helper 已从公共入口导出，同一个 `LocalCatalogApi` 已绑定到 `FeaturesRegistry.productApi`，Product Route 已进入主 Shell 并纳入未登录 Redirect；已登录 Product Deep Link 和 Wishlist 入口测试通过。
2. **Fixture 稳定 ID 与 not-found**：Fixture 现在只接受明确的合法 ID 范围，并在 Product Payload 中保留请求 ID；`product-999999` 返回稳定 not-found，`browse-product-20`、`recommended-1` 保持来源 ID，[`catalog_fixture.dart`](../../app/packages/app_data/lib/src/catalog/catalog_fixture.dart#L29) 与 [`product_detail_data_test.dart`](../../app/packages/app_data/test/catalog/product_detail_data_test.dart#L29)。
3. **Wishlist 保活页面同步**：`LocalWishlistApi` 只在 mutation 成功后发布 snapshot，`WishlistController` 在 `onInit` 订阅并在 `onClose` 取消；跨 Feature mutation 已具备进程内同步路径，[`wishlist_api.dart`](../../app/packages/app_features/lib/api/wishlist_api.dart#L33)、[`local_wishlist_api.dart`](../../app/packages/app_features/lib/feature_wishlist/api/local_wishlist_api.dart#L8) 与 [`wishlist_controller.dart`](../../app/packages/app_features/lib/feature_wishlist/controllers/wishlist_controller.dart#L47)。
4. **Shop 与 Cart 商品入口**：`buildShopRoutes` 与 `buildCartRoutes` 已增加只传稳定 Product ID 的窄导航回调；Shop 推荐商品卡和 Cart 商品图分别转发各自 Domain Product ID，[`routes.dart`](../../app/packages/app_features/lib/feature_catalog/routes.dart#L17)、[`shop_dashboard_page.dart`](../../app/packages/app_features/lib/feature_catalog/pages/shop_dashboard_page.dart#L200)、[`feature_cart/routes.dart`](../../app/packages/app_features/lib/feature_cart/routes.dart#L13) 与 [`cart_page.dart`](../../app/packages/app_features/lib/feature_cart/pages/cart_page.dart#L270)。根 Router 对 Shop、Wishlist、Categories、Cart 统一 `push(productDetailLocation(productId))`，[`demo_router.dart`](../../app/apps/demo/lib/router/demo_router.dart#L81)。Demo Router 测试真实点击 Shop 与 Cart 入口，Shop 详情返回后继续切换到 Cart，并再次进入同一个 Product Route，[`product_router_test.dart`](../../app/apps/demo/test/router/product_router_test.dart#L61)。

## P2

### 1. Wishlist snapshot 仍缺少 Controller/真实 Router 一致性测试

[`wishlist_api_test.dart`](../../app/packages/app_features/test/feature_wishlist/wishlist_api_test.dart#L7) 验证了 Local API 发布成功 mutation，但 [`wishlist_controllers_test.dart`](../../app/packages/app_features/test/feature_wishlist/wishlist_controllers_test.dart#L11) 使用的 Fake 未实现 `WishlistSnapshotSource`，因此没有直接验证“已存活 Wishlist 页面 -> 详情收藏/取消 -> 返回后立即同步”以及失败 mutation 不发布 snapshot。实现路径静态上成立，建议在处理剩余 P1 时补充这条回归测试。

### 2. Product 展示边界测试仍不完整

现有聚焦测试已覆盖普通详情、规格确认/取消、评价列表/空态、详情与评价 Route、Deep Link，以及 Wishlist、Shop、Cart 入口；仍未直接覆盖 Cart 详情返回原来源、Categories 的真实 Router 入口、Sale 原价/标记、Reviews loading/error/retry、320 x 568、横屏、文字缩放、长页末端和关键 Semantics。实现路径与同一 `context.push` 导航契约已静态确认，这些缺口不阻断本卡归档，后续扩展对应页面时建议补齐。

### 3. `stockCount` 仍没有页面消费者

`ProductDetail.stockCount` 已由 Fixture/Mapper 提供，但商品详情 UI 未展示或测试该字段。若 Figma 节点要求库存信息，应数据驱动展示；否则应收窄当前 Domain 字段，避免维护无消费者契约。

## 待确认与残余风险

- Figma Desktop 当前无法读取节点 `0:8785`、`0:8689`、`0:8438`、`0:8314`、`0:8192`，本轮只能依据仓库设计上下文、既有 Token 和本地资源审查，无法确认 Gallery、Sale、规格 Sheet 与评价页的视觉精度。
- 本卡不生成 UI Spec/Audit，也不调用 App Operator；这不影响本轮代码、Route 和状态边界结论。

## 验证摘要

- 仓库证据 [`shoppe-product-details-reviews.log`](./test-evidence/shoppe-product-details-reviews.log) 为 Exit code 0：全量静态分析、19 个 Product/Wishlist 聚焦测试、3 个 Demo Product Router 测试及仓库边界 lint 通过。
- 独立复跑通过：Product Data/Controller/Page/Route、Wishlist API/Controller 共 19 个测试，Demo Product Router 共 3 个测试；`make lint` 与 `git diff --check` 均通过。
- 最终静态 Review：P0 0，P1 0；通过，可以归档。
