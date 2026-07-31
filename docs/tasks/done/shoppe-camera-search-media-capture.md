---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy:
  - media-capture-android-host-integration
  - media-capture-dart-client
  - media-capture-flutter-package-registration
securityReview: required
---

# 接入 Search 图片来源选择

## 目标

- 移除 Categories/Shop 页头部相机图标，避免目录页直接申请相机权限。
- Search 的 `Choose a photo` 和图片搜索入口先让用户选择拍摄或系统相册。
- 拍照确认后读取受限、去敏 JPEG 缩略图，立即释放原生媒体租约，再进入现有图片识别流程。
- 相机选择只允许拍照，不允许视频；相册选择继续使用既有系统 Picker。

## 实现边界

- Search 定义自己的 Picker 协议和稳定错误码，不依赖订单评价业务 API，也不接触 handle、路径、URI、
  `PlatformException` 或 Wire Map。
- Flutter Router 不携带自动拍摄 query intent；只有用户在来源弹窗明确选择拍摄后才调用相机。
- `FeaturesRegistry` 创建并拥有 Search Picker，logout 清理遗留租约，App dispose 幂等释放 Picker/Client。
- 不修改原生 Core/UI/Bridge/Host，不上传或持久化拍摄媒体，不把图片、设备标识或 Figma 信息写入文档。

## 文件范围

- `app/packages/app_features/lib/feature_categories/**`
- `app/packages/app_features/lib/feature_search/**`
- `app/packages/app_features/lib/api/search_image_picker.dart`
- `app/packages/app_features/lib/features_registry.dart`
- `app/packages/app_features/lib/app_features.dart`
- `app/packages/app_features/pubspec.yaml`
- `app/packages/app_features/test/feature_categories/**`
- `app/packages/app_features/test/feature_search/**`
- `app/packages/app_features/test/features_registry_test.dart`
- `app/apps/demo/lib/router/demo_router.dart`
- `app/apps/demo/test/router/demo_router_test.dart`

## 验收

- Shop 页头不再渲染相机按钮；Search route 不再支持进入页面时自动拍摄。
- `Choose a photo` 弹出拍摄/相册/取消选择；取消保持初始态，确认后沿用现有识别/结果状态机。
- 单测覆盖 photo-only 配置、thumbnail 校验、失败映射、release/clear/dispose 和晚到结果。
- 运行相关 Flutter tests、`make format`、`make analyze`、`make lint`、`make harness-check` 和
  `git diff --check`；按用户要求不再代替用户执行真机交互调试。

## 执行结果

- Flutter 来源选择、Consumer、Registry 生命周期和测试已完成；Shop 直达相机与自动拍摄路由已移除。
- 普通 Review 与 Security Review 的 P0/P1 均为 0，Security P2 为 0。
- 真机交互按用户要求留给用户自行调试。
