---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-shop-home-catalog]
---

# 实现 Shoppe 商品详情、规格与评价

## 背景与输入

- Figma：`0:8785` - `35 Product`、`0:8689` - `36 Product Sale`、`0:8438` - `37 Product Full`、`0:8314` - `38 Product Variations`、`0:8192` - `39 Reviews`。
- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- 已实现的 Catalog、Wishlist、Cart API 与主导航 Shell。

## 目标与非目标

- 实现一个商品详情 Route 的普通/Sale/完整滚动状态、规格选择和评价列表。
- 打通 Shop/Categories/Wishlist/Cart 商品卡到详情，以及详情收藏和 Add to Cart 的公开 API 协作。
- 本卡不实现 Search、Checkout、评价提交、真实库存或远程商品接口。

## 实现要求

1. 重新读取五个节点，确认 35/36/37 的同页关系、图片 Gallery、Sale 标记、价格、描述区段、规格 Overlay 与 Reviews 导航。
2. 在 Catalog Domain 增加 `ProductDetail`、图片、价格/Sale、可选规格、库存展示和评价摘要的当前必要字段；复用 ProductSummary、Money 和稳定 Product ID。
3. 增加窄 `ProductApi`、LocalDataSource、Mapper 与确定性 Fixture。详情请求按 Product ID 返回 Domain 或稳定 not-found 失败，不让 Page 解析 Payload。
4. Product Controller 通过构造函数接收 `ProductApi`、`WishlistApi`、`CartApi`，管理 loading/data/error、Gallery、规格草稿/确认、收藏和 Add to Cart。跨 Feature 只依赖公开 API，不 import 私有 Controller/Widget。
5. `35/36/37` 实现为同一 `/products/:productId` 页面，Sale 由数据驱动，完整内容由单一 Sliver 滚动；不得创建普通、Sale、Full 三个 Route。
6. `38` 按结构化设计实现为 Variation Sheet/Overlay 或子 Route，必须支持选择、确认、取消、缺少必选规格提示和恢复；取消不能修改已确认规格。
7. `39` 建立 `/products/:productId/reviews`，显示确定性 Rating 汇总和评价列表，覆盖 loading/empty/error；本卡不允许提交新评价。
8. Shop、Categories、Wishlist、Cart 的商品点击统一使用 product ID 进入详情；详情 Add to Cart 后 Cart API 状态和底栏角标（如设计存在）一致更新。
9. 复用 shared Catalog 卡片、图片和 Token；产品 Gallery、规格控件等只在真实复用时形成 Feature 私有组件。

## 同批测试与验收

- Domain/Data/API：普通/Sale 商品、规格、not-found、评价、Mapper 和失败边界。
- Controller：规格确认/取消、收藏、加入 Cart、重复操作、错误恢复和释放。
- Widget/Route：35–37 合并、38 生命周期、39 列表、各来源进入详情、Back、长页、多视口与 Semantics。
- 商品详情只有一个真实 Route；收藏/购物车状态跨页面一致，无浮点金额、伪库存或跨 Feature 内部引用。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不接相机、AR、分享 SDK 或远程库存。
- UI 自动化由人工独立安排。
