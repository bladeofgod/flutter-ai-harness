---
executor: task-executor
blockedBy: []
---

# 实现 Shoppe 欢迎起始页

## 背景

Demo 的第一个真实 UI 输入是 Shoppe Figma 节点 `0:12855`（`01 Start`）。当前 `app_ui`、`app_features` 和 Demo 根路由仍是中立占位，仓库尚无 Theme、字体、设计资源或 Feature 页面。

本任务实现欢迎起始页，并以真实消费者为依据建立最小 UI 基础。页面只表达两个后续导航意图；注册和登录目标页将在用户提供独立 Figma 节点后实现，当前不得猜测页面内容。

## 输入与事实来源

- `CLAUDE.md`
- [`docs/architecture.md`](../../architecture.md)
- [`docs/figma-links.md`](../../figma-links.md)
- [`docs/figma/shoppe-welcome-start-design-context.md`](../../figma/shoppe-welcome-start-design-context.md)
- [Figma `0:12855` - `01 Start`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-12855&m=dev)
- 本仓库 `app_ui` 与 Feature 分层约束

执行前加载 `figma-to-flutter`、`flutter-layouts`、`dart-coding-standards`、`go-router` 和 `testing-strategy` Skill。

## 目标

- 将 Shoppe 欢迎页作为 Demo 根路由 `/` 的首屏，并在 375 x 812 参考视口对齐 Figma。
- 在 `app_ui` 中建立确定为全 App 事实的最小品牌颜色、字体注册和 Theme。
- 在 `app_features` 中建立无状态 Welcome Feature、私有 Widget 和公开 Route 工厂。
- 从 Figma 导出并本地化欢迎页品牌 PNG，确保授权、来源和运行时加载可复现。
- 为两个操作提供明确回调边界和无障碍语义。
- 覆盖参考视口、窄短视口、增大字体、回调和壳工程装配测试。

## 非目标

- 不实现注册页、登录页、启动动画、Splash、Onboarding、多语言或深色模式。
- 不创建 Controller、GetX 状态、Domain Entity、业务 API、ApiClient、AuthService、UserService、Fixture 或持久化。
- 不引入 Dio、Proto、Freezed、Drift 或其他与静态欢迎页无关的依赖。
- 不绘制 Figma 中的 iOS 状态栏、时间、电量、信号或 Home Indicator。
- 不把按钮、箭头或整页截图作为图片资源入库。
- 不扩建没有当前消费者的完整组件库，也不复制参考工程的业务 Token。

## 具体要求

1. 重新通过 Figma Desktop MCP 读取节点 `0:12855`，并以设计上下文中的节点 ID、尺寸和样式为基线；实现不得依赖 MCP 的临时 `localhost` Asset URL。
2. 在 `app_ui/lib/theme/` 创建品牌颜色、字体注册和亮色 Theme 文件，由 `app_ui.dart` 公开导出。只把 `#FFFFFF`、`#202020`、`#004CFF`、`#F3F3F3` 以及 Raleway/Nunito Sans 字体族作为全 App 事实；当前单页的字号、行高、尺寸、间距与圆角保留在 Welcome Feature 私有样式中，后续出现第二个真实消费者后再提升共享 Token。
3. `MaterialApp.router` 使用 `app_ui` 提供的亮色 Theme，保持 Material 3、白色 Scaffold 背景、主色和深色系统栏图标。Theme 不包含 Welcome 业务文案或 Feature 专属规则。
4. 从许可清晰、可追溯的公开来源取得 Raleway Bold 与 Nunito Sans Light 字体文件，在 `app_ui` 声明本地字体并保存许可文本。字体只声明实际需要的 `w700` 与 `w300`；无法确认来源或许可时停止，不得静默回退为相似字体。
5. 从 Figma 把节点 `0:12906` 与 `8:4768` 的圆形底座、阴影和购物袋合成为一张透明品牌 PNG，按 Flutter Asset Variant 导出 `1x/2x/3x` 并放入 `app_features` 的 Welcome 资源目录。基准资源使用 150 x 150 完整视觉边界，内部圆形保持 134 x 134；不得裁整页截图，不引入 `flutter_svg`。
6. 在 `app_features/lib/feature_welcome/` 创建路由级 `WelcomePage`、必要的私有品牌图形 Widget 和 Route 工厂。页面保持无状态，通过必填的 `VoidCallback onGetStarted` 与 `VoidCallback onSignIn` 接收两个意图，不使用服务定位器或 Overlay。
7. `app_features.dart` 只公开壳工程需要的 Route 常量/工厂，不公开 Feature 私有 Widget。`apps/demo` 用公共入口把 Welcome Route 注册为 `/`，不得直接 import `feature_welcome/pages/`。
8. 用户已确认本阶段两个按钮暂不产生页面变化。`DemoApp` 允许测试或后续页面任务注入两个回调；当前默认处理器安全消费点击并留在欢迎页，不创建占位注册/登录页面、不抛异常，也不伪造成功反馈。后续真实 Route 接入任务再替换该临时边界。
9. 参考视口必须保持：150 x 150 品牌 PNG 视觉边界（内部 134 x 134 圆形和 81.4 x 92 购物袋）、52 号标题、19 号两行说明、335 x 61 主按钮、16 圆角以及 30 x 30 次操作箭头。品牌标题 `letterSpacing` 固定为 0，不复刻 Figma 的负字距。
10. 使用 `SafeArea`、`LayoutBuilder`、约束布局和必要的 `SingleChildScrollView` 处理平台 Insets 与高度变化。不得用只适配 375 x 812 的整页绝对定位；宽屏内容以 375 为参考上限居中，窄屏保留 20 水平边距。
11. 主操作使用 Flutter 按钮/表面能力实现；次操作使用熟悉的右箭头 Icon，整行至少提供 48 高的点击区域，可见圆形箭头保持 30 x 30。两个操作不能因点击态、字体或资源加载而改变整体布局尺寸。
12. 为两个操作提供准确 Semantics，品牌 PNG 从语义树排除，避免重复朗读。不为尚未由人安排的 UI 自动化添加测试专用 Key；后续真实自动化需要稳定选择器时单独评估公开语义是否足够。
13. 更新现有 `demo_app_test.dart`，移除中立壳文案断言；新增 `app_ui` 与 `app_features` 的对应测试目录和测试文件。不得为测试暴露 Feature 私有实现。

## 同时编写的测试

- `app_ui`：验证品牌颜色、字体族/字重、Theme 主色和 Scaffold 背景。
- `app_features`：验证 Welcome 私有文字样式的字号、字重、行高、颜色和零字距。
- `app_features`：在 375 x 812 下验证全部文案、品牌 PNG、主按钮和次操作存在，两个回调各只触发一次。
- `app_features`：在 320 x 568、375 x 812、横屏约束以及至少 1.3 倍文字缩放下使用有界 `pump`，结合 `tester.takeException()` 和几何断言确认无 RenderFlex overflow，页面可滚动且两个操作可到达。
- `app_features`：验证按钮语义和品牌图形不产生重复语义。
- `apps/demo`：验证根路由显示 Welcome 页面，注入回调可从壳工程到达页面，未注入时点击不抛异常且保持当前 Route。
- 资源测试：验证 `1x/2x/3x` 品牌 PNG 能从 `app_features` Package AssetBundle 加载、解码并选择正确密度资源。

Widget 测试只验证结构、行为和约束，不以脆弱的全屏像素 Golden 代替针对 Figma 的人工视觉比对。

## 验收标准

- Demo 启动后首屏是 Shoppe 欢迎页，不再显示 `Flutter AI Harness` 占位文案。
- 375 x 812 参考视口的应用内容与 Figma 节点 `0:12855` 对齐；系统状态栏与 Home Indicator 不由 Flutter 伪造。
- 页面在 Android/iOS、窄短视口和增大字体时无溢出、遮挡、不可点击区域或布局跳动。
- 两个入口具有正确 Semantics，回调边界可测试，且没有虚构后续页面。
- `app_ui` 只包含真实消费的最小 Token/Theme，`app_features` 保持 Feature 内聚，壳工程只通过公共 Route 工厂装配。
- 字体与 PNG 均为本地可复现资源，来源和许可可追溯，仓库中不存在 MCP 临时 URL。
- 全部格式、分析、架构边界、Harness 和测试门禁通过。

## 验证命令

```bash
make bootstrap
make format
make analyze
make harness-check
make test
make check
git diff --check
```

## 平台或环境限制

- Figma 资源导出依赖 Figma Desktop 已打开目标文件、Dev Mode 和本地 MCP Server。
- Android 与 iOS 都是验收平台；Figma 只提供 iPhone 375 x 812 参考画板，Android 的系统栏差异不算视觉缺陷。
- 字体和 PNG 必须入库，运行时不得依赖网络、Figma Desktop 或本机字体安装状态。
- 不读取 `.env*`，不手工编辑生成文件或任何依赖锁文件；依赖声明变更后由 `make bootstrap`/Pub 工具更新 Workspace `pubspec.lock`。

## 风险与后续边界

- 两个按钮的真实目标 Route 尚未提供；用户已批准本阶段使用无页面变化的默认回调。注册/登录页任务拿到独立 Figma 节点后再完成导航闭环。
- Figma 未提供响应式 Variant，非 375 x 812 布局属于本文明确记录的工程推断，需要通过多视口测试和运行态截图核验。
- 字体文件可能影响文本测量和截图差异，必须在布局定稿前完成字体加载与许可核验，不能在最后阶段替换。

## 执行结果

- 已在 `app_ui` 建立 Shoppe 亮色 Theme、品牌颜色和 Raleway/Nunito Sans 本地字体声明，并保存字体许可文本。
- 已在 `app_features` 实现 Welcome Feature、公开 Route 工厂以及 `1x/2x/3x` 品牌 PNG；Demo 根路由已切换为 Shoppe 欢迎页。
- 两个按钮按用户确认保持无页面变化，未创建虚构注册/登录页面，也未把 App Operator 或 UI Spec 嵌入本任务流程。
- Widget 测试已覆盖设计基准几何、文字样式、回调边界、Semantics、响应式布局、资源解码与 3x 密度选择。
- Android 16 真机 `ATLSVB3C23019536` 已完成 Debug APK 构建、安装、启动和截图核验，用户确认视觉效果通过；iOS 未单独进行运行态截图。
- 测试证据见 [`docs/reviews/test-evidence/shoppe-welcome-start-screen.log`](../../reviews/test-evidence/shoppe-welcome-start-screen.log)，执行审查见 [`docs/reviews/execute-shoppe-welcome-start-screen.md`](../../reviews/execute-shoppe-welcome-start-screen.md)。
