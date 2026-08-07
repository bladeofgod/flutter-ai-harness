---
task: shoppe-support-media-resource-preview
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_core/lib/value/media_resource_id.dart
  - app/packages/app_data/lib/src/support/support_models.dart
  - app/packages/app_data/lib/src/support/support_mapper.dart
  - app/packages/app_data/lib/src/support/support_local.dart
  - app/packages/app_data/lib/src/support/support_fixture_handler.dart
  - app/packages/app_features/lib/api/support_chat_api.dart
  - app/packages/app_features/lib/api/support_media_picker.dart
  - app/packages/app_features/lib/feature_support/api/local_support_chat_api.dart
  - app/packages/app_features/lib/feature_support/api/native_support_media_picker.dart
  - app/packages/app_features/lib/feature_support/controllers/support_chat_controller.dart
  - app/packages/app_features/lib/feature_support/pages/support_chat_page.dart
  - app/packages/app_features/lib/feature_support/routes.dart
  - app/packages/app_features/lib/features_registry.dart
  - app/packages/app_features/lib/app_features.dart
  - app/apps/demo/lib/demo_app.dart
  - app/apps/demo/lib/router/demo_router.dart
  - app/packages/app_features/pubspec.yaml
  - app/pubspec.lock
implementationDigest: 9442b9f36b8619421eaac00fdc220cbc75bff05edd8fc331aab658fee6aca038
---

# Security Review：Support Media Resource Preview

独立 Security Review 通过，P0/P1/P2 均为 0。消息只持有 validated `MediaResourceId` 与轻量元数据；路径、
URI、native/export handle 和原始 bytes 不进入 Fixture、日志、Semantics 或 `toString`。Store commit 在
release export/native lease 之前；会话接纳、reset、dispose 串行且失败保留 cleanup ownership。

## 跨 Runtime 集成影响

最终集成只更新共享 lockfile、Host、golden、Harness 与状态文档，没有修改 Support 生产消息、resource ID
或 cleanup。根 `xml` 仍是 Harness dev dependency；独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。

## iOS 综合修正后的影响复审

本轮没有修改 Support 消息模型、`MediaResourceId`、Store adoption 或预览 cleanup。变化限于 iOS Core、
Rendering、UI、共享 Gate/golden 与说明文档；独立 Security Reviewer 复核跨 Runtime 边界后确认
P0/P1/P2 0/0/0，本报告按当前实现文件重新绑定摘要。

## Session Reset 生命周期影响

`DemoApp` 现在持有并在卸载时解除自己的 Session Reset 注册，外部 Registry 在已登出 Coordinator 下
重新挂载时会先清理会话状态。reset 回调失败会脱敏上报且不阻断后续清理或登出，因此 Support 消息、
媒体草稿和资源租约不会因其它注册失败而跳过 reset。本轮未改变 Support 的资源标识或 cleanup ownership。

## Workspace 消费检查器影响

共享 lockfile 只把既有 `analyzer 10.0.1` 从传递依赖提升为根工具直接 dev dependency，版本、来源与
SHA-256 未变。Support 生产代码和依赖未修改；新工具只读解析 Workspace 源码，不接触媒体内容或资源定位。

## Workspace 冗余依赖清理影响

`app_features` 仅移除未被任何源码消费的 `app_im` 占位依赖，共享 lockfile 没有新增来源或版本。Support
消息、媒体资源 ID、lease 与 cleanup ownership 均未修改；依赖消费门禁、Android Debug 与 iOS 无签名
Debug 构建确认 Bridge 仍通过 `app_features` 传递发现并注册。P0/P1/P2 维持 0/0/0。

## Wire Formatter 工具依赖影响

共享 lockfile 新增精确固定的 `dart_style 3.1.7` direct dev dependency，仅由 Wire generator 在内存中
格式化生成源码；Support 生产依赖、消息、资源 ID、lease 与 cleanup ownership 均未修改。该依赖不进入
Runtime package，P0/P1/P2 维持 0/0/0。
