# Shoppe Main App Batch 独立审查

## 结论

**未通过。** 本轮未发现 P0；发现 **5 个 P1** 和 **2 个 P2**。静态分析、仓库边界门禁和全量自动化测试虽然全部通过，但现有测试没有覆盖多项跨 Feature、跨 Route 和跨登录会话的真实状态链，因此不能据此归档整个批次。

## 审查范围

- 基线：`HEAD` `78a56bdaaa546f8846b7cc7c3ff2fbbcc84b11f5` 到 2026-07-23 09:19 CST 当前工作树。
- 覆盖 37 个 tracked 变更/删除项，并通过 `git ls-files --others --exclude-standard` 单独覆盖 119 个 untracked 项；没有把 `git diff` 当作完整范围。
- 覆盖 Demo 根装配与认证 Redirect、五分支 `StatefulShellRoute`、Catalog/Product、Categories、Wishlist、Cart、Checkout、Orders、Promotions、Rewards、Search、Settings、Payment/Address、Support、Profile 集成，以及新增 Domain、Fixture Handler、DataSource、Mapper、资源和测试。
- 已读取 14 张本批归档任务卡及已有执行证据；以下结论均重新从生产代码与测试取证，没有沿用已有 Review 的通过结论。
- 本轮只新增本报告，没有修改实现、测试、配置或依赖。

## P0

无。

## P1

### 1. 相同 Product ID 在不同入口代表不同商品，重复加入同一 Cart 行会改写单价

- 位置：[catalog_fixture.dart](../../app/packages/app_data/lib/src/catalog/catalog_fixture.dart#L110)、[cart_fixture_handler.dart](../../app/packages/app_data/lib/src/cart/cart_fixture_handler.dart#L43)、[wishlist_fixture.dart](../../app/packages/app_data/lib/src/wishlist/wishlist_fixture.dart#L53)、[search_fixture.dart](../../app/packages/app_data/lib/src/search/search_fixture.dart#L145)
- 影响：稳定 Product ID 没有形成 canonical 商品事实。同一商品从 Shop、Search、Wishlist 或 Cart 进入详情时，标题、图片和价格会变化；从详情用相同 Variation 再次加入 Cart 时，不只是数量增加，已有行的商品快照和单价也会被替换，导致总价跳变。
- 证据：
  - Cart Fixture 的 `cart-product-1` 是 `$17.00`，图片为 2000 x 2000 的 `cart_item_01.png`（[cart_fixture_handler.dart](../../app/packages/app_data/lib/src/cart/cart_fixture_handler.dart#L181)）。
  - Product Detail 只取 ID 末尾数字并重新计算 `1700 + (number % 4) * 300`；因此同一个 `cart-product-1` 在详情中变成 `$20.00`，图片也被替换成另一张 Profile 资源（[catalog_fixture.dart](../../app/packages/app_data/lib/src/catalog/catalog_fixture.dart#L110)）。
  - Cart `upsert` 命中相同行 ID 后使用新输入的 `product` 重建整行，只从旧行继承数量（[cart_fixture_handler.dart](../../app/packages/app_data/lib/src/cart/cart_fixture_handler.dart#L43)）。所以原 `$17 x 1` 行从详情添加一次相同 Pink/M 后会成为 `$20 x 2`，而不是 `$17 x 2`。
  - Wishlist 的 add 请求同样丢弃传入的 ProductSummary，只保存 ID，随后按数字后缀重新拼标题、图片和价格（[wishlist_fixture.dart](../../app/packages/app_data/lib/src/wishlist/wishlist_fixture.dart#L53)、[wishlist_fixture.dart](../../app/packages/app_data/lib/src/wishlist/wishlist_fixture.dart#L207)）。Search 中 `product-1` 又是独立的标题/图片/价格（[search_fixture.dart](../../app/packages/app_data/lib/src/search/search_fixture.dart#L145)）。
  - 根 Product Router 测试只断言目标页面存在，没有比较来源卡片与详情的 ProductSummary，也没有验证已有 Cart 行重复添加后的单价（[product_router_test.dart](../../app/apps/demo/test/router/product_router_test.dart#L35)）。
- 修法：在 `app_data` 建立按稳定 ID 索引的 canonical Catalog Fixture/record，让 Shop、Categories、Search、Wishlist、Cart、Promotions 与 Product Detail 都引用同一 ProductSummary；详情只扩展该摘要，不按 ID 后缀重新造商品。Cart upsert 对已存在行必须保留/校验 canonical 单价和商品快照。增加跨入口测试：来源摘要等于详情摘要；相同 Variation 重复加入只增加数量且单价不变；收藏后 Wishlist 仍显示同一标题、图片和价格。

### 2. Wishlist 的可见 Add to Cart 操作在真实 App 中仍未接线

- 位置：[demo_router.dart](../../app/apps/demo/lib/router/demo_router.dart#L142)、[wishlist_page.dart](../../app/packages/app_features/lib/feature_wishlist/pages/wishlist_page.dart#L135)、[wishlist_api.dart](../../app/packages/app_features/lib/api/wishlist_api.dart#L5)
- 影响：Cart、Product 和 Wishlist 均已完成，但用户点击 Wishlist 商品的购物袋按钮不会修改 Cart，只会看到 `Cart is not available in this demo yet.`。这与完整主应用的可操作入口以及跨 Feature 状态一致性要求冲突。
- 证据：根装配调用 `buildWishlistRoutes` 时只传入 `openProduct` 和 Recently Viewed 导航，没有传 `WishlistProductActions.onAddToCart`（[demo_router.dart](../../app/apps/demo/lib/router/demo_router.dart#L142)）；页面在该回调为空时明确走不可用 SnackBar（[wishlist_page.dart](../../app/packages/app_features/lib/feature_wishlist/pages/wishlist_page.dart#L135)）。当前 action 还只携带 Product ID，丢失 WishlistItem 已有的 color/size，无法形成 Cart 稳定行输入（[wishlist_api.dart](../../app/packages/app_features/lib/api/wishlist_api.dart#L5)）。Widget 测试只是注入一个记录 ID 的假回调，并未通过真实 Router/Registry 证明 Cart 发生 mutation（[wishlist_pages_test.dart](../../app/packages/app_features/test/feature_wishlist/wishlist_pages_test.dart#L13)）。
- 修法：把 WishlistItem 的 ProductSummary + ProductVariation 转成类型化 `CartLineInput`，由 Wishlist Controller 构造注入窄 `CartApi`（或等价窄跨 Feature API）执行 mutation；根 Route 只做装配，不在 Widget 中查找服务。补根级测试：点击真实 Wishlist Add to Cart，切到 Cart 后出现对应稳定行；重复点击增加数量；失败时显示可重试错误而不是“功能不可用”。

### 3. 订单评价完成后返回的是持有旧 Order 的父详情页

- 位置：[routes.dart](../../app/packages/app_features/lib/feature_orders/routes.dart#L41)、[orders_controller.dart](../../app/packages/app_features/lib/feature_orders/controllers/orders_controller.dart#L189)、[order_review_page.dart](../../app/packages/app_features/lib/feature_orders/pages/order_review_page.dart#L152)
- 影响：从已送达订单详情进入评价、提交成功并点击 Done 后，父详情页仍持有提交前的 `Order(review: null)`，继续显示 `Review order`，而不是刚保存的评价。用户会看到同一流程前后状态矛盾，并可再次进入已完成评价页面。
- 证据：父 `/orders/:orderId` 和子 `review` Route 分别创建独立 `OrdersController.order`（[routes.dart](../../app/packages/app_features/lib/feature_orders/routes.dart#L41)）；提交只更新子 Controller 的 `_viewState`（[orders_controller.dart](../../app/packages/app_features/lib/feature_orders/controllers/orders_controller.dart#L189)）；完成按钮仅 `context.pop()`，没有把更新后的 Order 返回或触发父 Controller reload（[routes.dart](../../app/packages/app_features/lib/feature_orders/routes.dart#L118)）。现有测试在看到完成页后即结束，没有点击 Done 并断言父详情（[orders_routes_test.dart](../../app/packages/app_features/test/feature_orders/orders_routes_test.dart#L93)）。
- 修法：为订单详情与评价建立共享 Route scope/controller，或让子 Route `pop(updatedOrder)` 并由父 Route await 结果后刷新/应用返回值。增加从详情开始的完整测试：提交、Done、返回详情后 `Review order` 消失且显示 `Your review`；Back/re-enter 仍保持一致。

### 4. logout/delete account 只清 Auth，下一次登录会继承上一会话的全部业务状态

- 位置：[auth_state.dart](../../app/apps/demo/lib/auth/auth_state.dart#L80)、[demo_app.dart](../../app/apps/demo/lib/demo_app.dart#L27)、[features_registry.dart](../../app/packages/app_features/lib/features_registry.dart#L51)
- 影响：同一 App 进程中删除账号或登出后再次登录，Cart、Wishlist、订单/评价、Rewards 提醒、Settings 偏好、地址/支付方式和 Payment History 都保留上一会话的数据。即使是 Demo 数据，这也违反“登出恢复固定 Fixture”的任务契约，并造成明显的跨用户状态泄漏。
- 证据：`DemoApp` 在 `initState` 只创建一次 Registry 和 Router（[demo_app.dart](../../app/apps/demo/lib/demo_app.dart#L27)）；Registry 持有同一批可变 Handler 和唯一 PaymentProfileStore（[features_registry.dart](../../app/packages/app_features/lib/features_registry.dart#L51)）；`AuthStateCoordinator.logout()` 只把 session/user 设为 null 并通知 Router（[auth_state.dart](../../app/apps/demo/lib/auth/auth_state.dart#L80)），没有 reset/dispose 任何业务状态。实际可变状态分别保存在 Cart map、Orders list、Wishlist IDs、Settings preferences、Rewards consumed IDs、PaymentProfileStore 和 receipt list 中。现有 logout 测试只断言 Redirect/页面文案，没有 mutate -> logout -> re-login -> defaults 的断言（[demo_router_test.dart](../../app/apps/demo/test/router/demo_router_test.dart#L346)）。
- 修法：建立由壳工程拥有的 authenticated session scope。普通 logout 和 Delete Account 都应先原子 reset/dispose 所有用户态 Handler/Store/Stream，再发布 logged-out 快照；可选择重建 session Registry/Router，或为 Registry 提供明确的 session reset 生命周期。补一个同 `DemoApp`/同进程测试：先修改 Cart、Wishlist、Settings、Payment、Orders/Review，logout 后重新登录，验证全部恢复固定 Fixture，且旧 subscription 已关闭。

### 5. Cart 的删除/增减数量控件对屏幕阅读器不可辨识，触控区域也只有 30 x 30

- 位置：[cart_page.dart](../../app/packages/app_features/lib/feature_cart/pages/cart_page.dart#L270)、[cart_page_test.dart](../../app/packages/app_features/test/feature_cart/cart_page_test.dart#L45)
- 影响：Cart 的核心操作都是没有 label/tooltip 的图标按钮；辅助技术只能得到无名称的 button，无法区分删除、减量和增量。强制 30 x 30 的点击区域也显著小于常规 44/48dp 可访问目标，影响运动障碍和小屏用户。
- 证据：三个动作均复用 `_RoundAction`，但组件只接收 icon/onPressed，内部 `IconButton` 没有 `tooltip` 或语义标签，并被 `SizedBox.square(dimension: 30)` 限死（[cart_page.dart](../../app/packages/app_features/lib/feature_cart/pages/cart_page.dart#L327)、[cart_page.dart](../../app/packages/app_features/lib/feature_cart/pages/cart_page.dart#L400)）。Cart 测试仅按 ValueKey 点击并断言金额/空态，没有启用 Semantics 或验证可访问名称和目标尺寸（[cart_page_test.dart](../../app/packages/app_features/test/feature_cart/cart_page_test.dart#L45)）。
- 修法：让 `_RoundAction` 强制接收面向商品的 semantic label/tooltip，例如 `Remove <title>`、`Decrease <title> quantity`、`Increase <title> quantity`；保持 30px 视觉圆形时，用至少 44/48dp 的透明交互/语义容器承载。新增 Semantics 测试及 tap-target 尺寸断言，并让数量变化通过 live region 或合并后的行语义可感知。

## P2

### 1. 两张 Cart 小缩略图造成约 4.6 MB 包体和约 25.4 MiB 全尺寸解码

- 位置：[cart_fixture_handler.dart](../../app/packages/app_data/lib/src/cart/cart_fixture_handler.dart#L181)、[catalog_asset_image.dart](../../app/packages/app_features/lib/shared/catalog/catalog_asset_image.dart#L14)
- 影响：`cart_item_01.png` 为 2000 x 2000 / 1,941,815 bytes，`cart_item_02.png` 为 2000 x 1333 / 2,673,157 bytes；页面只以约 126dp 宽显示，却会把两张原图打入包并按完整像素解码。仅这两张资源就增加约 4.6 MB 压缩包体，RGBA 解码约占 25.4 MiB，低内存设备进入 Cart 时会产生不必要的内存与栅格开销。
- 证据：Cart 固定使用这两张资源，而通用 `CatalogAssetImage` 的 `Image.asset` 没有 `cacheWidth/cacheHeight`（[catalog_asset_image.dart](../../app/packages/app_features/lib/shared/catalog/catalog_asset_image.dart#L14)）；本批全部 app_features 资源合计 12,219,890 bytes。
- 修法：把源图离线缩放到目标最大物理尺寸（按最高支持 DPR 留足 2x/3x）并用合适的 PNG/WebP 压缩；必要时让图片组件按布局尺寸和 DPR 提供 decode cacheWidth。加入单资源和总资源预算门禁，而不仅是“可解码”测试。

### 2. iOS Photo Library 用途文案仍只声明头像用途

- 位置：[Info.plist](../../app/apps/demo/ios/Runner/Info.plist#L27)、[search_image_picker.dart](../../app/packages/app_features/lib/feature_search/media/search_image_picker.dart#L11)
- 影响：Search 已复用系统图库做商品图片搜索，但 iOS 权限弹窗仍只说明“choose a profile picture”。用户授权说明与实际用途不一致，真实发版时存在隐私披露和审核风险。
- 证据：Search 的生产 Adapter 明确调用共享 Gallery picker（[search_image_picker.dart](../../app/packages/app_features/lib/feature_search/media/search_image_picker.dart#L11)），而 plist 文案只覆盖 profile picture（[Info.plist](../../app/apps/demo/ios/Runner/Info.plist#L27)）。
- 修法：把用途文案改为同时准确覆盖头像与本地商品图片搜索，不声称上传或 ML；在 iOS 真机验证首次授权、拒绝、受限、取消和成功选择。

## 验证

本轮实际运行：

- `make analyze`：通过，`No issues found!`
- `make lint`：通过，Workspace 依赖矩阵与仓库边界检查通过
- `make harness-check`：通过
- `make test`：通过；demo 51、app_core 12、app_data 137、app_features 249、app_ui 2
- `git diff --check HEAD`：通过
- 资源引用存在性、PNG 尺寸/字节数、pubspec asset 声明：只读检查完成

未在本轮重跑平台构建或 App Operator。已有批次证据显示 Android Debug APK 构建通过；iOS no-codesign Debug Build 因本机缺少 iOS 26.5 Platform 失败。该环境失败不是本轮新增代码缺陷的直接证据，但 iOS 宿主编译和系统图库运行行为仍是发布验证缺口；也没有 Release/Profile 包体与真机内存数据。

## 摘要

包依赖、Feature 私有 import、Controller 构造注入、主 Redirect、五分支 Shell、Fixture Handler 分发和绝大多数局部 loading/error/retry/lifecycle 路径未发现新的阻断问题。当前阻断集中在单卡测试难以发现的集成层：canonical Product 缺失、真实 Wishlist -> Cart 未装配、Orders 父子 Route 状态不同步、认证会话未拥有业务状态生命周期，以及 Cart 核心操作的无障碍缺口。

## 修复复审

2026-07-23 完成独立修复复审，见 [`review-shoppe-main-app-batch-r2.md`](./review-shoppe-main-app-batch-r2.md)。原报告 7 项发现已全部闭环，结论为 `P0=0`、`P1=0`；Feed 商品 rail 点击、canonical 商品摘要、Wishlist 加购、订单评价回跳、会话重置、Cart 可访问性、资源尺寸和 iOS 权限文案均有实现与测试证据。剩余风险仅为未执行 App Operator、原生平台构建和 iOS 真机图库流程。
