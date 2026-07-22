# Shoppe Auth 流程设计上下文

## 来源与范围

- 设计文件：[`Shoppe - eCommerce Clothing Fashion Store Multi Purpose UI Mobile App Design`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-12779&m=dev)
- Figma File Key：`JPP1rxO7ADGjAnECWe2Ndg`
- 初次读取日期：2026-07-21
- 本轮任务拆分复核日期：2026-07-22
- 来源、作者和 CC BY 4.0 许可：[`docs/figma-links.md`](../figma-links.md)
- 本文覆盖注册、登录、错误密码和密码找回入口。登录成功后的 Profile Dashboard 单独记录在 [`shoppe-profile-dashboard-design-context.md`](./shoppe-profile-dashboard-design-context.md)。

结构、尺寸和样式来自 Figma Desktop MCP 的 `get_design_context`、`get_metadata`、`get_variable_defs` 与节点截图。本轮重新读取 `0:12779`、`0:12718`、`0:12584`、`0:12518`、`0:12449` 及截图，未发现影响任务边界的设计漂移。Figma 没有提供表单校验、未知账号、提交中或接口错误 Variant；这些行为在下方作为工程规则单独记录。

## 节点与流程

| 节点 | 名称 | 尺寸 | 流程职责 |
| --- | --- | --- | --- |
| `0:12855` | `01 Start` | 375 x 812 | 已实现的 Welcome 入口 |
| `0:12779` | `02 Create Account` | 375 x 812 | 注册表单 |
| `0:12718` | `03 Login` | 375 x 812 | Email 账号识别 |
| `0:12584` | `05 Password Typing` | 375 x 812 | 已识别用户的密码输入状态 |
| `0:12518` | `06 Wrong Password` | 375 x 812 | 8 位密码错误状态 |
| `0:12449` | `07 Password Recovery` | 375 x 812 | 找回方式选择 UI |

```text
Welcome
├── Let's get started -> Create Account -> Profile Dashboard
└── I already have an account -> Login Email -> Password
                                              ├── correct -> Profile Dashboard
                                              ├── wrong -> Wrong Password
                                              └── forgot -> Password Recovery
```

用户已经确认：注册和登录成功都进入 Profile Dashboard；密码固定为 8 位；密码找回页只实现 UI 可达性，不发送 SMS/Email，也不继续后续业务。

## 设计事实

### Create Account `0:12779`

- 标题 `Create Account` 位于 `x=30, y=122`，Raleway Bold 50，双行高 54。
- 上传头像入口位于 `x=30, y=284`，视觉尺寸 90 x 90，包含 34 x 27.8 相机图形。
- Email、Password、Phone 三个胶囊输入区从 `y=406` 开始，宽 335，高约 52/52/55，间距约 8，圆角 60。
- Password 具有隐藏/显示图标；Phone 具有国旗、下拉箭头、分隔线和号码输入。
- `Done` 按钮位于 `x=20, y=634`，335 x 61，圆角 16；`Cancel` 位于 `y=719`。
- 背景是白色，顶部由浅蓝与主蓝两个大面积 Bubble 构成。

### Login Email `0:12718`

- 顶部和右侧使用蓝色/浅蓝 Bubble；页面下半部分另有浅蓝装饰块。
- 标题 `Login` 位于 `x=20, y=438`，Raleway Bold 52，行高 61。
- 说明 `Good to see you back!` 位于 `y=503`，Nunito Sans Light 19，并带黑色 Heart 图形。
- Email 输入位于 `x=21, y=555.08`，334 x 52.2。
- `Next` 按钮位于 `x=20, y=644`，335 x 61；`Cancel` 位于 `y=719`。

### Password Typing 与 Wrong Password

- 两个节点共享相同的 Bubble、105 x 105 头像底座、用户头像、标题和 8 个 17 x 17 密码圆点。
- 头像底座位于 `x=135, y=149`；标题 `Hello, Romina!!` 位于 `y=282`，Raleway Bold 28；说明 `Type your password` 位于 `y=348`，Nunito Sans Light 19。
- 8 个圆点从 `x=78` 到 `x=298`，间距 12；输入状态使用 `#004BFE` 和 `#E5EBFC`，错误状态全部使用 `#EC4E4E`。
- `0:12584` 展示已输入 5 位、剩余 3 位的中间状态；`0:12518` 展示 8 位错误并在 `y=445` 显示 `Forgot your password?`。
- Figma 画出了 iOS 键盘，但应用必须使用系统键盘，不能复刻键盘、状态栏或 Home Indicator。

### Password Recovery `0:12449`

- 头像和 105 x 105 底座位于 `y=149`；标题 `Password Recovery` 位于 `y=266`。
- 问句 `How you would like to restore your password?` 居中显示在 290 x 57 区域。
- SMS 和 Email 是 199/198 x 40 的单选行，默认选择 SMS；选中态使用蓝色浅底，未选中态使用粉色浅底。
- `Next` 位于 `x=20, y=634`，335 x 61；`Cancel` 位于 `y=719`。
- 用户已明确本页只实现 UI：允许切换 SMS/Email；点击 `Next` 不发送请求、不进入下一页。

## Token 与资源

- 复用现有 `AppColors.primary #004CFF`、`background #FFFFFF`、`textPrimary #202020`、`textOnPrimary #F3F3F3` 和已入库的 Raleway/Nunito Sans。
- Figma 的注册表单实例 `4:14080`、`4:14081`、`4:14082` 使用 Poppins Medium，字号约 13.8、行高 1.4。这是设计事实，不能无记录地替换为现有字体；实现应从可追溯的官方来源加入 Poppins `w500` 本地字体和 OFL 许可，并增加 AssetBundle 测试。
- Figma Variables 在注册/登录表单中提供：`Grey/20 #D2D2D2`、`Background/Grey #F8F8F8`、`Grey/100 #1F1F1F`。这些值在多个 Auth 控件中有真实消费者，应以表单背景、占位文字和强文字的语义名称加入 `app_ui`。
- Figma 中装饰 Bubble 与密码圆点使用 `#004BFE`，按钮使用 `#004CFF`。Flutter 控件统一使用现有主色；需要导出的 Bubble 资源保留设计原始填充，记录该 1 个 RGB 级别的已知差异。
- Bubble、相机、Heart、头像底座、Check 等设计图形必须从 Figma 本地化，不得保留 MCP `localhost` URL。简单标准图标优先使用 Flutter/Lucide 等现有图标能力；复杂 Bubble 和头像装饰优先导出为透明 Raster Asset 并提供密度 Variant。
- Profile/Login 使用的 Romina 头像和注册默认头像沿用设计稿来源登记；若单项图片无法确认授权，则使用许可明确或生成的替代头像，不阻塞表单结构实现。

## 用户确认的产品规则

- Welcome 的两个入口分别进入注册和登录；注册或登录成功后都进入 `/profile`。
- 注册头像支持系统图片选择；国家区号使用由 Demo 提供的少量主要国家，不需要完整全球清单。
- 用户注册并选择头像后，注册成功的当前会话与 Profile 必须展示该头像；无需跨 App 重启保存。
- 密码固定为 8 位。
- `Forgot your password?` 进入 Password Recovery；Recovery 只实现 UI 可达性，不发送 SMS/Email，也不进入后续页面。

## Demo 工程默认

下列规则是为了让当前 Figma 流程可执行而采用的可替换 Demo 默认，不是 Figma 或用户原话直接表达的产品事实。后续产品输入可以替换它们，但不能破坏 Auth API、Session 和 Route 边界。

- Route 使用 `/auth/register`、`/auth/login`、`/auth/password`、`/auth/recovery`；Welcome 与 Auth Feature 不互相 import 页面，通过各自公开 Route 工厂与根 `createDemoRouter` 完成装配。
- `WelcomePage` 保留页面级按钮回调，但 `DemoApp` 不暴露 `onGetStarted`、`onSignIn` 等 Welcome 专属参数。根 Router 把两个按钮事件分别映射到公开的注册和登录 Route。
- 注册/登录成功只把 `AuthResult` 交给根装配回调；根回调调用唯一的 `AuthStateCoordinator.authenticate`。GoRouter 随 Coordinator 通知执行现有 Redirect 并进入 `/profile`，Auth 页面和 Controller 不额外调用 `go('/profile')`，避免双重导航。
- `Cancel` 返回 Welcome 并清空当前流程的输入与错误状态。
- 注册头像可选；点击后使用系统图片选择器，选择结果只在内存中预览和随当前 User 保存，不申请摄像头能力、不做裁剪编辑、不跨重启持久化。Picker 请求限制为最大 1024 x 1024、质量 85；读取后最多接受 2 MiB，超限时保持原状态并显示非敏感错误。
- 国家选择器默认 United Kingdom `+44`，使用底部单选列表提供 United Kingdom、United States、Canada、China、Japan、South Korea、India、Australia、Germany、France；不增加搜索、远程国家数据或完整全球清单。
- 注册 Email、Password、Phone 必填；Email 做基本格式校验，Password 必须恰好 8 位，Phone 按所选区号接受 6 至 15 位数字。头像不必填。
- 设计没有姓名字段。`romina@example.com` 显示 `Romina`；其他注册或登录用户的显示名由 Email `@` 前部分确定性转为可读名称。
- 登录 Email `Next` 接受任意格式有效的 Email，并确定性生成使用默认头像和公开 Demo 电话信息的用户，不依赖注册记录或账号数据库。
- 密码输入满 8 位或键盘 `Go` 时提交；`00000000` 固定触发错误密码状态以演示 Wrong Password 与 Recovery，其他 8 位密码登录成功。错误时清空真实输入值并显示 8 个红点，下一次输入恢复普通状态。
- Auth API 保持异步但不加入随机延迟。提交中禁止重复操作；错误通过 Controller 状态呈现，不由 `AuthService` 显示 Dialog/Snackbar。
- 注册不保存账号；注册接口只返回包含当次资料和所选头像的 `AuthResult`，由当前内存 Session/User 使用。App 重启后恢复未登录状态，后续独立登录使用合成用户的默认头像，不引入 SecureStorage、Drift、Dio 或 Proto。

## 布局与验证边界

- 所有页面使用 `SafeArea`、约束布局和键盘 Insets；短屏或文字放大时内容可滚动，主操作不得被键盘遮挡。
- 页面宽度以 375 为参考上限，窄屏保持至少 20 水平边距；不得连续按屏幕宽度缩放字体。
- 头像、密码圆点、单选项、表单字段、密码可见性和按钮需要准确 Semantics；密码不得写入日志、错误文本、测试证据或 Semantics value。
- Widget 测试覆盖 375 x 812、320 x 568、横屏、1.3 倍文字、键盘 Insets、校验、重复提交、错误恢复与 Route 跳转。
- UI Spec、Audit 和 App Operator 不属于普通任务规划或完成门禁，只有人工另行安排时才执行。
