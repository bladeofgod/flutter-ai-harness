---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy:
  - media-capture-flutter-presentation-dismiss-integration
  - media-capture-android-host-integration
  - media-capture-dart-client
  - media-capture-flutter-package-registration
securityReview: required
---

# 接入 Shoppe 订单评价媒体拍摄与真实缩略图

## 输入与事实来源

- 已完成类型化 Dart Client、Flutter Package 登记和 Android Host Integration；iOS 最终集成按用户决定后置。
- `order_review_page.dart`、`orders_controller.dart`、Orders API/Route/Registry 及现有测试。
- `app/apps/demo/lib/router/demo_router.dart`、`app/apps/demo/lib/demo_app.dart` 及 Demo Router/App tests；
  Orders route 的实际依赖由 Flutter shell composition 装配。
- `docs/figma/shoppe-main-app-design-context.md` 的订单评价 `66/67`：现有设计没有媒体入口。
- 用户批准：入口沿用 Shoppe 页面语言/Token；拍摄器全屏原生呈现并采用微信式交互，但不复制品牌/
  像素；专用 Figma 不是前置。
- `AppColors.primary = #004CFF`、现有 typography/surface/button 语义。

## 目标

- 在订单评价表单增加 Media Capture 入口，调用类型化 `presentCaptureFlow`，展示由最新 Capability/Wire
  产生的真实、bounded、sanitized thumbnail 和附件状态。
- 通过窄 Feature API/构造注入隔离 plugin 类型，正确管理 route/controller、lease、bytes 和错误生命周期。
- 保留已有星级、评论、提交和完成流程，并用现有 Shoppe Token 完成响应式/无障碍 UI。

## 非目标

- 不改变 Native UI/Core/Adapter/Contract/Host，不实现 Flutter 相机页面或图库 fallback。
- 不上传、保存相册、播放视频、持久化原始媒体或把附件写入 Fixture/远程评价。
- 不在评价完成页宣称媒体已上传；Demo V1 只展示当前评价草稿的一项本地附件。
- 不新增专用 Figma、滤镜、美颜、裁剪、多附件排序或后台上传队列。

## 实现路径与所有权

本任务独占后置 Flutter Consumer 写入：

- `app/packages/app_features/pubspec.yaml`
- `app/packages/app_features/lib/api/**` 中新增的窄 Order Review Media API/Value Object
- `app/packages/app_features/lib/feature_orders/**`
- `app/packages/app_features/lib/features_registry.dart`、`app_features.dart`
- `app/packages/app_features/test/feature_orders/**`
- `app/apps/demo/lib/router/demo_router.dart`
- 必要时 `app/apps/demo/lib/demo_app.dart`
- `app/apps/demo/test/**` 中本任务新增/修改的 Router、DemoApp lifecycle 测试

最终 Integration 不得预写这些业务文件。上述 `app/apps/demo/lib/**` 仅属于 Flutter shell 的业务依赖
composition，不是 `app/apps/demo/android/**`、`app/apps/demo/ios/**` Native Host 或 plugin registry；
本任务不得修改 Bridge Package、`app_data` 订单持久化、Native Host/plugin registry、共享 Capability/
Wire/native docs、root Validator、CI 或 Makefile。

## 实现要求

1. 定义 `OrderReviewMediaApi`（或等价窄接口）与明确 Value Object；具体 Feature 实现包装 Dart Client，
   把 plugin handle/model 隐藏在实现内部。Controller 只通过构造函数接收 API，不接触 PlatformException、
   Map、路径/URI 或 Native 类型。
2. Demo V1 使用一个附件槽：空、launching、ready、failure/retry、removing/released 状态为 sealed/enum
   状态。重复点击 launch、Route dispose、替换、移除、提交成功和异常都不得遗留 Session/lease/
   subscription；替换前先释放旧附件且失败时状态可恢复。
3. 只有用户点击媒体入口时调用全屏 Native flow。confirmed 后立即通过已批准 thumbnail API 获取真实
   bytes；cancelled 回到原表单且不显示错误；typed permission/system/bridge failure 显示简短可重试状态，
   不泄漏 details。
4. Ready 附件显示真实缩略图、照片/视频类型和视频时长（若有），提供熟悉的移除/重拍图标和 tooltip/
   Semantics。缩略图 bytes 先验证长度/content type 后解码，失败进入附件错误状态并释放 lease；不得用
   静态商品图或占位色冒充真实拍摄结果。
5. 入口/附件区域嵌入现有评价表单而非卡中卡；复用 AppColors、Theme 和现有 8px radius/间距语言。
   入口使用相机图标与清晰 label，状态使用进度/错误/重试控件；320x568、375x812、横屏、1.3x 字号、
   键盘和 Safe Area 不溢出/遮挡。
6. Rating/comment validation 和 submit exactly-once 行为保持不变。附件是本地 Demo draft，不改
   `OrdersApi.submitReview`/`ProductReview` 持久化；提交成功前可以展示，成功后释放 lease，并在完成文案
   中不声称上传/保存媒体。
7. `FeaturesRegistry` 创建并拥有一个 Dart Client/Media API 生命周期所有者，提供幂等 `dispose` 关闭
   Channel subscription、pending flow 和本地 lease registry。`demo_router.dart` 必须通过
   `buildOrdersRoutes(..., mediaApi: featuresRegistry.orderReviewMediaApi)`（或等价显式命名参数）把同一
  实例注入 Orders route/controller，禁止 Controller/Route 内自行 new 或服务定位。
8. `DemoApp` 必须区分 Registry 所有权：只有 `widget.featuresRegistry == null` 时由自身创建并在
   `dispose` 调用 Registry dispose；测试/调用方注入的外部 Registry 不得被 DemoApp 越权释放。
   Router rebuild、widget update 和 App dispose 的 exactly-once ownership 用 Demo tests 固定。
9. Feature Registry 与 Demo Router/App 是本后置任务唯一 Flutter 业务 composition 写入，不触碰
   Android/iOS Native Host、GeneratedPluginRegistrant 或 plugin registry。
10. 日志/FlutterError 不包含 thumbnail bytes、handle、payload 或原始异常 details；内存中的 thumbnail
   只保留到 draft/route 生命周期，release 后清空引用。

## 测试与验收

- Controller 单测覆盖 confirmed/cancelled/failure、重复 launch、thumbnail decode failure、remove/
  replace、submit、dispose、late completion 和 lease release exactly once。
- Widget/route 测试覆盖入口、全状态、真实测试 thumbnail bytes、返回页面状态、星级/评论回归、
  320/375/横屏/大字号/键盘和 Semantics；Fake 不冒充 Native Camera。
- API/Registry 测试证明 plugin 类型不泄漏到 Controller/Page，构造注入唯一且 route dispose 清理。
- Demo Router 测试证明 `buildOrdersRoutes` 获得 Registry 的同一 `mediaApi`；DemoApp lifecycle 测试证明
  内部创建 Registry 只 dispose 一次、外部注入 Registry 不被 dispose，Router/App 重建不重复创建 Client。
- `rg`/Review 确认没有 path/URI、原图、上传/持久化或微信品牌资产；页面只使用现有 Token。

## 验证命令

```bash
TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_orders
make format
make analyze
make test
make lint
make harness-check
git diff --check
```

## 环境限制

Widget/Controller 测试使用 Fake Media API，不需要设备。Android 真实全屏 UI、Camera/权限与 thumbnail
由前置 Android Host/平台证据和本任务真机验证负责；iOS 运行接线与验证留给后续跨 Runtime
Integration。若需要独立 UI 自动化，应由用户另行安排 UI Spec/App Operator，不是本任务门禁。
