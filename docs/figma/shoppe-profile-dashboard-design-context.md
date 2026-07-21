# Shoppe Profile Dashboard 设计上下文

## 来源与节点关系

- 首屏节点：[`0:11956` - `13 Profile`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-11956&m=dev)，375 x 812。
- 完整内容节点：[`0:11472` - `14 Full Profile`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-11472&m=dev)，375 x 2909。
- Figma File Key：`JPP1rxO7ADGjAnECWe2Ndg`
- 读取日期：2026-07-21
- 来源、作者和 CC BY 4.0 许可：[`docs/figma-links.md`](../figma-links.md)

两个节点描述同一个 Profile Dashboard。`0:11956` 是 375 x 812 首屏视觉基准；`0:11472` 是完整纵向内容来源，不应实现为第二个 Route 或一张缩放长图。

## 页面结构

完整内容的主要区段如下：

| 区段 | Figma 位置/尺寸 | 实现形态 |
| --- | --- | --- |
| 顶部用户与操作 | `y=71..167` | 当前用户头像、My Activity、Voucher、消息、设置、Greeting |
| Announcement | `x=20, y=179, 335 x 70` | 只读公告行 |
| Recently viewed | 标题 `y=267`，内容 `y=309, 335 x 60` | 横向头像列表 |
| My Orders | `x=20, y=394, 335 x 77` | To Pay / To Receive / To Review 状态按钮 |
| Stories | `x=20, y=499, 434 x 216` | 横向 104 x 175 Story 卡片 |
| New Items | `x=20, y=740, 432 x 247` | 横向商品卡片 |
| Most Popular | `x=20, y=1009, 434 x 183` | 横向商品卡片 |
| Categories | `x=20, y=1216, 335 x 433` | 分类拼图网格 |
| Flash Sale | `x=20, y=1675, 335 x 276` | 标题、静态 Fixture 倒计时和商品网格 |
| Top Products | `x=20, y=1986, 335 x 109` | 横向圆形分类商品 |
| Just for You | `x=20, y=2129, 335 x 727` | 双列推荐商品网格 |
| Bottom Navigation | 首屏 `y=728` | 固定在安全区底部，不随 2909 内容滚到末尾 |

首屏基准显示 `Hello, Romina!`、公告、最近浏览、订单和 Stories 顶部，并保持 Profile Tab 激活。完整节点提供后续商品区段的顺序与内容密度。

## 数据与会话边界

- 登录 Fixture 用户使用设计中的 `Romina` 名称与头像；注册用户使用当前用户可观察契约提供的名称和所选/默认头像。
- Greeting 和头像由壳工程 `AuthStateCoordinator` 实现的 `CurrentUserProvider` 注入 Feature；Profile 不 import 或查找 `apps/demo` 的 Coordinator、`AuthService` 或 `UserService`。页面其他内容来自只读 `ProfileDashboardApi`，由 `app_data` 的确定性 Fixture、LocalDataSource 和 Mapper 提供。
- Dashboard 数据只定义当前页面实际消费的公告、最近浏览、订单摘要、Story、商品、分类和 Flash Sale 展示字段，不预建 Cart、Wishlist、Order Detail 或 Checkout 模型。
- Flash Sale 时间是确定性展示 Fixture，不启动依赖墙钟时间的无限 Timer；后续出现真实倒计时产品规则时再引入 Clock 和并发生命周期。
- 页面加载需要覆盖 loading、data 和 retryable error；各区段允许空列表并保持布局稳定，不使用随机内容或在线图片。

## 交互范围

- 本任务的产品目标是 Auth 成功后的可到达 Profile Dashboard。
- 当前没有提供 Shop、Wishlist、Categories、Cart、Message、Settings、Order、Story 或商品详情目标节点。相关图标和卡片保持设计外观，但不得虚构 Route、业务结果或成功反馈；只有 Profile Tab 标记为当前选中。
- Dashboard 主内容支持纵向滚动，Stories/New Items/Most Popular/Top Products 支持有界横向滚动；Bottom Navigation 使用 `Scaffold.bottomNavigationBar` 或等价固定结构。
- 页面 Route 使用 `/profile`。`AuthStateCoordinator` 是 GoRouter 唯一的刷新 `Listenable`，并以同一次一致状态通知驱动 `CurrentUserProvider`：未登录直接访问 Profile 时返回 Welcome，已登录访问 Welcome/Auth 时进入 Profile，登出时返回 Welcome。任何可观察通知都满足登录 Session 与当前用户同时存在且 ID 匹配，或二者同时为空。登录成功使用 `context.go` 替换 Auth 栈，系统返回键不能回到密码页。

## Token、组件与资源

- 复用现有字体与 `AppColors`。页面反复使用 `#F8F8F8`、`#E5EBFC`、`#004CFF`、`#202020`；Auth 任务建立的表单/浅色 Surface Token 可复用，页面专属尺寸留在 Feature 内。
- 重复的 section header、圆形缩略图、横向商品卡、状态 pill 和商品网格卡应在 `feature_profile/widgets/` 内形成真实复用组件，不提升为全局 UI 原语。
- 商品、Story、头像和分类图片必须本地化并按实际显示尺寸压缩；不得把完整 2909 高页面截图作为运行时资源，不得保留 MCP 临时 URL。
- 设计文件许可已登记。图片若存在独立来源且授权无法确认，使用许可明确或生成的同类替代图，并在视觉 Review 中记录偏离。

## 响应式与测试

- 使用单一 `CustomScrollView`/Sliver 所有者组织长页面，横向列表只在横轴滚动；不得使用 2909 高固定 `Stack`。
- 在 375 x 812 对齐首屏，在窄屏、短屏、横屏和 1.3 倍文字下保持无溢出；Bottom Navigation 不遮挡最后一组推荐商品。
- 图片容器使用固定宽高或 `AspectRatio`，加载/错误占位不能改变卡片尺寸。
- Widget 测试覆盖首屏结构、完整 section 顺序、横纵滚动、当前用户切换、loading/empty/error、认证 Redirect 和 Profile Tab 语义。
- 页面视觉以 Figma 截图人工核对；UI 自动化仍由人工在任务流程外独立安排。
