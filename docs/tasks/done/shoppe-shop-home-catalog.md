---
executor: task-executor
blockedBy: [shoppe-profile-dashboard]
---

# 实现 Shoppe Catalog 基础与 Shop 首页

## 背景与输入

节点 [`0:11012` - `15 Shop`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-11012&m=dev) 是主应用 Shop Tab 的完整长页，也是后续 Categories、Search、Product、Wishlist 和 Cart 的 Catalog 数据基础。

- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- [`docs/figma/shoppe-profile-dashboard-design-context.md`](../../figma/shoppe-profile-dashboard-design-context.md)
- [`docs/architecture.md`](../../architecture.md)
- 现有 `ProfileDashboard`、`ProductSummary`、`CategorySummary`、`FlashSale` 和 Profile 商品组件

## 目标与非目标

- 实现确定性 Catalog 数据链路、`/shop` Route 与节点 15 的 Shop 内容。
- 将已经出现两个真实消费者的 Catalog Domain/展示能力从 Profile 专属归属中拆出，Profile 行为不得回归。
- 本卡不实现 Categories、Search、Product Detail、Wishlist、Cart 或主 Tab Shell；Shop 页面不复制一套私有底栏，统一底栏由 `shoppe-main-navigation-shell` 接入。

## 实现要求

1. 实现前重新读取 `0:11012` 的 `get_design_context`、变量和截图，记录 Banner、区段、滚动、字体、颜色、Asset 与交互事实；不得使用上一轮 MCP localhost URL。
2. 在 `app_data/lib/src/catalog/` 一次建立 `Money`、Currency/格式化边界和类型化商品价格，并迁移 `ProductSummary`、`CategorySummary`、`FlashSale` 及实际共享 Value Object。现有 `displayPrice` 只能成为由 Money 派生的展示值，不得继续作为计算来源；`ProfileDashboard`、Fixture 和 Mapper 同批迁移，公共行为保持兼容。
3. 只为节点 15 当前消费字段增加 `ShopDashboard`、Promotion Banner 和必要分组；不得预建商品详情、购物车、库存、订单或支付模型。
4. 先把当前集中在 Auth 文件中的 Fixture 分发重构为可组合的 Feature Handler：Auth、Profile、Catalog 各自拥有请求键、Payload 与状态，`FixtureApiTransport` 接受 Handler 集合并只负责重复键拒绝、请求分发和 Unknown Request。不得使用全局静态注册；Auth/Profile 全量测试必须证明行为未漂移。
5. Catalog Handler、LocalDataSource 和 Mapper 使用稳定请求键返回固定排序、固定 ID、本地 Asset Key 的 Shop 数据。Profile Fixture 与 Shop Fixture 可以复用 Catalog 实体，但保持请求和页面聚合独立；后续并行任务只新增自己的 Handler，不修改 Transport 分发实现。
6. 在 `app_features/lib/api/` 定义窄 `CatalogApi`，在 `feature_catalog/api/` 提供本地实现，并通过 `FeaturesRegistry.local()` 装配。Controller 只接收 `CatalogApi`，覆盖 loading、data、空分组、retryable error 和释放。
7. 使用一个 `CustomScrollView`/Sliver 所有者实现 Big Sale、Categories、Top Products、New Items、Flash Sale、Most Popular、Just For You。横向区段必须有界；双列商品网格不能依赖 375 宽度硬编码。
8. 至少被 Profile 与 Catalog 两个 Feature 消费且业务语义一致的展示组件迁入 `app_features/lib/shared/catalog/`；仅视觉相似或包含页面行为的组件不得强行合并，也不得下沉到 `app_ui`。
9. 创建公开 `/shop` Route。区段操作使用 Controller 状态或显式回调边界，不创建未实现目标 Route、不显示虚假成功反馈；后续任务在目标页面存在时补齐导航。
10. 本地化节点 15 实际使用的 Banner、商品与分类资源并压缩到合理尺寸；所有资源具备来源记录、Bundle 加载与解码验证。
11. 375 x 812 对齐截图首屏，完整内容顺序对齐 375 x 2646 长页；系统状态栏由平台处理，页面本身不绘制底部 App Shell。

## 同批测试与验收

- Domain/Mapper/DataSource/API：Money 精度/格式化、稳定 ID、顺序、共享 Catalog 类型、模块化 Handler、重复请求键、Unknown Request、Payload 错误、空数据和失败映射。
- Controller/Widget：状态、重试、区段顺序、横纵滚动、网格约束、图片占位和多视口无溢出。
- 回归：现有 Profile Fixture、页面视觉结构和测试继续通过，不存在 Profile 专属模型副本或跨 Feature 私有 import。
- `/shop` 可独立渲染真实本地数据；页面没有临时底栏、在线资源、随机 Timer 或不存在的业务结果。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台与后续边界

- 本卡无原生能力，不需要 Android/iOS 宿主修改。
- `01–14` 不重做；Profile 只接受 Catalog 类型/组件迁移所需的最小回归修改。
- UI Spec、Audit 与 App Operator 由人工独立安排。
