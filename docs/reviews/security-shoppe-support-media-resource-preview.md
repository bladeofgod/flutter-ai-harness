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
implementationDigest: f7b52945c9121a5b1bd6f7eac79fd23f7777f3492bafdc123814c103a9e476f2
---

# Security Review：Support Media Resource Preview

独立 Security Review 通过，P0/P1/P2 均为 0。消息只持有 validated `MediaResourceId` 与轻量元数据；路径、
URI、native/export handle 和原始 bytes 不进入 Fixture、日志、Semantics 或 `toString`。Store commit 在
release export/native lease 之前；会话接纳、reset、dispose 串行且失败保留 cleanup ownership。
