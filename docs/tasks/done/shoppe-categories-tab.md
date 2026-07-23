---
executor: task-executor
blockedBy: [shoppe-shop-home-catalog]
---

# 实现 Shoppe Categories 商品列表与筛选

## 背景与输入

- Figma：[`0:9794` - `25 Shop — Clothing`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-9794&m=dev)、`0:9662` - `26 Shop — Clothing on Scroll`、`0:9526` - `27 Categories Filter`。
- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- `shoppe-shop-home-catalog` 提供的 Catalog Domain、API、Fixture、资源和共享展示组件。

## 目标与非目标

- 实现 `/categories` Tab 根页面、分类切换、商品列表滚动和节点 27 的筛选状态。
- `25/26` 是同一页面的滚动状态，不建立两个 Route。
- 本卡不实现商品详情、文本/图片搜索、Wishlist 或主导航 Shell；商品点击目标由后续 Product 任务接线。

## 实现要求

1. 实现前重新读取三个节点的结构化上下文、变量和截图，确认分类 Chip、商品密度、滚动后 Header 行为、筛选控件和 Overlay/页面关系。
2. 仅在 Catalog Domain 中增加列表真实消费的查询、分类、排序和筛选 Value Object；不得把 UI 选中状态或 Fixture Payload 写入 Domain Entity。
3. 扩展 `CatalogApi` 或增加同属 Catalog 的窄查询接口，支持固定本地分类、商品结果和确定性筛选。筛选不随机、不读系统时间，切换条件可以复位。
4. Categories Controller 管理当前分类、筛选草稿/已应用条件、加载/空/错误与滚动相关 UI 状态；通过构造函数接收 API，不持有 Router 或 BuildContext。
5. 使用有界 Header、分类选择和惰性商品列表；节点 25/26 的视觉变化由同一页面随滚动产生，不能用固定长 Stack 或重复 Page。
6. 节点 27 若是 Overlay/Sheet，使用稳定 Route/Overlay 生命周期并支持 Apply、Reset、Cancel/Back；若结构化设计证明是页面，则按设计建立子 Route。不得仅凭截图决定。
7. 创建 `/categories` Route 和公开 Route 工厂。商品项只暴露稳定 product ID 回调；Product Route 存在前不伪造导航结果。
8. 复用 Catalog Token、Asset 和共享商品组件；只有真实新增语义才扩展 Token。

## 同批测试与验收

- 查询/Controller：分类切换、筛选应用/复位、空/错误/重试、并发去重和释放。
- Widget/Route：节点 25 首屏、滚动后状态、筛选生命周期、Back/Cancel、长列表、多视口和文字放大。
- `/categories` 使用真实 Catalog Fixture；25/26 合并为一个页面，27 可操作且不会污染取消前状态。
- Profile 与 Shop 首页回归通过，无重复 Product/Category Entity 或跨 Feature 私有引用。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 无原生能力，不接远程筛选或分析服务。
- UI 自动化由人工独立安排。
