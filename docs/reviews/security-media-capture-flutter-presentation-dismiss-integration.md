---
task: media-capture-flutter-presentation-dismiss-integration
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_features/lib/feature_orders/api/native_order_review_media_api.dart
  - app/packages/app_features/lib/feature_orders/controllers/orders_controller.dart
  - app/packages/app_features/lib/feature_search/api/native_search_camera_media_picker.dart
  - app/packages/app_features/lib/feature_search/controllers/search_controller.dart
  - app/packages/app_features/lib/feature_support/api/local_support_chat_api.dart
  - app/packages/app_features/lib/feature_support/api/native_support_media_picker.dart
  - app/packages/app_features/lib/feature_support/controllers/support_chat_controller.dart
  - app/packages/app_features/lib/features_registry.dart
implementationDigest: f7f4f9f07582d492dde2a62ca7660d29c18407cf7205e10b4706f4dad15502e6
---

# Security Review：Flutter Presentation Dismiss Integration

独立 Security Review 通过，P0/P1/P2 均为 0。Search、Order、Support 不接触 request ID；reset、Route close
和 dispose 会先 dismiss，再等待 pending。Support send/reset/dispose 通过 FIFO 串行，cleanup failure 保留
所有权并显示稳定可重试错误，过期 handle 按清理已收敛处理。

## iOS 综合修正后的影响复审

本轮没有修改 Flutter Search、Order、Support 的 dismiss、pending、FIFO 或 cleanup ownership；变化限于
iOS Core、Rendering、UI、共享 Gate/golden 与说明文档。独立 Security Reviewer 复核跨 Runtime 边界后
确认 P0/P1/P2 0/0/0，本报告按当前实现文件重新绑定摘要。
