# Shoppe 主应用设计上下文

## 来源与采用范围

- 完整设计 Page：[`0:1` - `Design`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-1&m=dev)
- Figma File Key：`JPP1rxO7ADGjAnECWe2Ndg`
- 规划读取日期：2026-07-22
- 来源、作者与 CC BY 4.0 许可：[`docs/figma-links.md`](../figma-links.md)
- 已完成且排除：`01–12` Auth 页面不再规划或实现；`13–14` Profile Dashboard 已实现，不重做布局和数据主体。后续只允许主导航底栏迁移，以及节点 `62`、`81`、`85` 和 Settings/Support 等已有图标目标所需的局部入口、Badge 或摘要接线，并必须保持原结构回归。
- 本轮范围：`15–101`，共 87 张顶层画板。

Figma Desktop MCP 已读取 `0:1` 的 101 张顶层画板元数据，并完整读取、截图核对 `0:11012`。其余画板在对应任务执行前必须重新读取准确节点的 `get_design_context`、变量与截图；不得只按本索引或画板名称猜测内部布局。

## 画板分组

| 范围 | 节点 | 设计含义 | 规划归属 |
| --- | --- | --- | --- |
| 15 | `0:11012` | Shop 完整长页 | Shop/Catalog 基础 |
| 16–24 | `0:10857`, `0:10722`, `0:10483`, `0:10403`, `0:10327`, `0:10243`, `0:10163`, `0:10069`, `0:9985` | Flash Sale、Live、Story 状态与内容样式 | Promotions/Stories |
| 25–27 | `0:9794`, `0:9662`, `0:9526` | Clothing 商品列表、滚动状态与分类筛选 | Categories Tab |
| 28–34 | `0:9375`, `0:9246`, `0:9233`, `0:9221`, `0:9191`, `0:9074`, `0:8870` | 文本搜索、图片搜索、识别状态、结果与筛选 | Search |
| 35–39 | `0:8785`, `0:8689`, `0:8438`, `0:8314`, `0:8192` | 商品详情、Sale、完整长页、规格与评价 | Product |
| 40–44 | `0:7998`, `0:7844`, `0:7709`, `0:7498`, `0:7363` | Wishlist 有数据/空态与 Recently Viewed 日期筛选 | Wishlist |
| 45–47 | `0:7209`, `0:7085`, `0:6969` | Cart 有数据与两种推荐来源空态 | Cart Tab |
| 48–56 | `0:6830`, `0:6638`, `0:6503`, `0:6289`, `0:6124`, `0:5936`, `0:5767`, `0:5612`, `0:5461` | Checkout、Voucher、地址、支付方式和支付结果 | Checkout |
| 57–67 | `0:5267`, `0:5015`, `0:4764`, `0:4882`, `0:4602`, `0:4445`, `0:4312`, `0:4135`, `0:3996`, `0:3807`, `0:3628` | 收货、物流、通知、历史和评价 | Orders/Activity |
| 68–80 | `0:3542`, `0:3456`, `0:3341`, `0:3238`, `0:3140`, `0:3036`, `0:2930`, `0:2805`, `0:2695`, `0:2501`, `0:2598`, `0:2400`, `0:2280` | 客服问题选择、连接、对话、Voucher 与服务评价 | Support Chat |
| 81–85 | `0:2120`, `0:2004`, `0:1873`, `0:1731`, `0:1565` | Reward、Voucher 列表、过期提醒与进度 | Rewards |
| 86–101 | `0:1460`, `0:1358`, `0:1271`, `0:1206`, `0:1113`, `0:980`, `0:862`, `0:722`, `0:632`, `0:547`, `0:476`, `0:394`, `0:312`, `0:234`, `0:119`, `0:51` | Settings、资料、卡片、地址、偏好、删除账号与 About | Settings |

## 页面与状态合并

87 张画板不得实现为 87 个 Route。当前可由顶层结构确定的合并关系如下，具体交互仍以执行时节点上下文为准：

- `25/26` 是同一商品列表的首屏与滚动状态；`27` 是筛选状态。
- `35/36/37` 是商品详情普通、Sale 和完整长页；`38` 是规格选择；`39` 是评价列表。
- `40/41` 是 Wishlist 有数据与空态；`42/43/44` 是 Recently Viewed 与日期选择状态。
- `45/46/47` 是 Cart 有数据和不同推荐来源的空态，不创建三个购物车 Route。
- `49/50` 是 Voucher 输入和成功状态；`52/53` 是支付卡数量状态；`54/55/56` 是支付中、失败和成功结果。
- `57–63` 是订单/物流状态链；`66/67` 是评价填写和完成状态。
- `68–80` 是一条客服会话状态机，不创建十三个独立页面。
- `86/87` 是 Settings 首屏与完整滚动内容；`89/90` 是 Add Card 与弹窗；`92/93` 是支付方式数量状态；`100` 是删除确认 Overlay。

## 主导航与布局事实

- 节点 `0:11012` 是 375 x 2646 的 Shop 长页，包含 Big Sale Banner、Categories、Top Products、New Items、Flash Sale、Most Popular 和 Just For You。
- 主应用底栏有 Shop、Wishlist、Categories、Cart、Profile 五个目的地。Profile 现有实现中的静态底栏只是上一阶段占位，最终必须由根 App Shell 统一拥有。
- 长页面使用一个纵向 `CustomScrollView`/Sliver 所有者；商品横轨和分类横轨只在横轴滚动。底栏固定在安全区，不随长内容滚动。
- Tab 根页面保持各自导航栈与滚动位置，规划采用 `StatefulShellRoute.indexedStack` 或等价结构；壳工程继续拥有根 GoRouter 和认证 Redirect。
- 认证成功仍按已确认行为进入 `/profile`。主导航接入不改变 `01–12` Auth 页面或登录成功目标。

## 节点 15 实施记录

- 2026-07-22 重新读取 `0:11012` 的结构化上下文、截图和变量；画板为 375 x 2646，变量接口未返回可复用 Variable，颜色与字体已映射到现有 `app_ui` Token 或 Catalog Feature 局部样式。
- 首屏结构为 28px `Shop` 标题、248 x 36 搜索框和 335 x 130 Big Sale Banner；完整区段顺序为 Categories、Top Products、New Items、Flash Sale、Most Popular、Just For You。
- Categories 使用两列四图拼贴卡；Top Products、New Items、Most Popular 是有界横轨；Flash Sale 与 Just For You 使用响应式网格。Shop 页面只拥有一个纵向 `CustomScrollView`，本阶段不绘制主导航底栏。
- Big Sale 原始位图从当前 Figma 节点导出、裁切并压缩为 `app/packages/app_features/assets/images/catalog/big_sale.png`（1005 x 390）；设计归属和 CC BY 4.0 署名沿用 [`docs/figma-links.md`](../figma-links.md)。运行时代码未保留 MCP 临时地址。
- 商品和分类预览优先复用同一设计文件已本地化的 `assets/images/profile/product_01.png` 至 `product_20.png`。Categories 中未覆盖的 Shoes、Lingerie、Watch 和 Hoodies 原图已从节点 `8:5190` 本地化到 `assets/images/catalog/categories/`，最长边压缩到 300px；Top Products、New Items、Flash Sale、Most Popular 和 Just For You 缺失的 6 张原图已本地化到 `assets/images/catalog/products/`，最长边压缩到 400px。这些都是节点当前消费资源，不保留 MCP 地址或复制已有同源图片。

## 数据与组件边界

- `Money`、Currency、类型化价格、`ProductSummary`、`CategorySummary`、`FlashSale` 等跨页面 Domain 类型必须在首个 Catalog 任务中一次建立或迁入 `app_data/src/catalog/`；Profile Dashboard 同批迁移 Mapper 并继续组合这些类型。Cart、Product 和 Checkout 只能消费该金额契约，不得二次迁移或继续使用展示字符串参与计算。
- Catalog 只读数据使用确定性 Fixture。Wishlist、Recently Viewed、Cart、Checkout 和后续订单状态使用进程内状态，App 重启后恢复初始 Demo 数据。
- 通用颜色、字体和无业务 UI 原语继续使用 `app_ui`。至少被 Profile 与 Catalog 两个 Feature 消费的商品/分类展示组件可进入 `app_features/lib/shared/catalog/`；仍带页面业务规则的 Widget 留在所属 Feature。
- 每个 Feature 继续遵循 `Domain -> Mapper -> LocalDataSource -> ApiClient -> FixtureApiTransport -> API -> Controller -> Page`，不得让 Fixture Payload、Plugin 类型或 Feature 私有实现越界。
- 图片必须从 Figma 本地化或使用许可明确的替代资源；不得保留 MCP localhost URL，也不得把完整页面截图作为运行时 Asset。

## Fixture 与并行实施边界

- 首个 Catalog 任务先把当前集中在 Auth 文件中的 Fixture 分发重构为可组合的 Feature Handler：每个 Handler 自有请求键、Payload、状态与映射边界，`FixtureApiTransport` 只负责唯一键校验、分发和 Unknown Request。
- `FixtureApiTransport` 接受 Handler 集合；不得依赖全局静态注册或让并行任务继续修改一个巨型 `switch`。Auth/Profile 行为在重构中必须完整回归。
- Handler 自有请求键、Payload 与 Feature 专属状态，但不得复制跨 Feature 的可变聚合。Checkout 首次引入地址/支付方式时建立进程级 `PaymentProfileStore`：Registry 只创建一个实例，并注入 Checkout 与后续 Settings DataSource/Handler；Store 独占不可变快照、mutation 和单次通知，Checkout Attempt 留在 Checkout Handler，Settings Preferences 留在 Settings Handler。
- `PaymentProfileStore` 是纯 Dart `app_data` 状态对象，不依赖 Flutter、页面或 Feature API。App 重建恢复固定 Fixture；Settings 修改后 Checkout 读取同一快照，禁止共享裸 Map、双写或通过跨 Feature 私有实现同步。
- 任务卡的“可并行”指 Feature 私有 Domain/Data/API/Controller/Page/Widget/测试与 Asset 可以并行。共享工作树中以下热点只由主执行器串行修改和验证：`app_data.dart`、Transport 组合入口、`app_features.dart`、`FeaturesRegistry`、根 `demo_router.dart`、共享 Catalog 文件和 Profile 页面。
- 并行子 Agent 不直接编辑上述热点。它们产出各自 Handler、LocalDataSource、本地 API、Route 工厂和测试；主执行器在同一任务批次按依赖统一更新 barrel、Registry、Handler 列表、根 Router 与 Profile 局部接线。

## Demo 工程默认与待 Review 决策

以下是为了让设计流程在无真实后端时可执行的规划默认。用户接受任务卡后视为本轮 Demo 规则；如需改变，应在执行对应任务前调整卡片。

- Search、Catalog、Product 使用固定本地商品数据；筛选只作用于当前内存列表。
- 图片搜索使用系统图库选择，随后按 Figma 展示确定性的 Recognizing、Recognized 和 Results 状态；不接摄像头、上传或 ML 识别引擎。Search 作为第二个图库消费者时，允许把 Auth 已验证的图库读取、限制和脱敏代码迁入共享非 UI Media Adapter；Auth 页面、Controller、Route 和产品行为不得重做。
- Checkout、Payment、Voucher、物流和评价使用确定性的本地状态机；不接支付 SDK、真实银行卡、地址服务或推送。运行时默认掩码主卡支付成功，第二张掩码 Fixture 卡支付失败；进度页只反映可控异步调用。失败后保留 Cart/Checkout 并允许切换主卡重试，成功后生成 Receipt 并原子清空 Cart。
- 节点 `56 Your Card Been Charged` 在 Demo 中保留视觉结构，但主文案改为 `Demo payment completed`，辅助文案明确没有真实扣款。这是主动产品文案偏离，不能宣称发生真实银行卡交易。
- Support Chat 使用本地脚本式会话，不连接客服、网络或 AI；本任务不为了占位强行实现 IM Engine。未来需要真实 IM 时再由明确消费者创建聚焦 Package。
- 删除账号只清理当前内存 Auth 状态并返回 Welcome，不调用远程删除；其他 Settings 偏好只在当前进程内生效。
- UI Spec、Audit 和 App Operator 不属于普通任务实现或归档门禁，仍由人工独立安排。

## 验证基线

- 每个节点实现前重新读取结构化上下文、变量和截图；新视觉值先反查 `app_ui` Token。
- Widget 测试覆盖 375 x 812、320 x 568、横屏、1.3 倍文字、空/加载/错误/状态切换和滚动可达性。
- 主 Tab、详情页、Overlay、Back/Cancel、认证 Redirect 和状态复位需要 Route/Controller 测试。
- 资源需要 AssetBundle 加载与解码测试；所有任务最终运行静态分析、完整测试、仓库边界和 Harness 门禁。
