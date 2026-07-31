---
task: shoppe-order-review-media-capture
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_features/lib/api/order_review_media_api.dart
  - app/packages/app_features/lib/feature_orders/api/native_order_review_media_api.dart
  - app/packages/app_features/lib/feature_orders/controllers/orders_controller.dart
  - app/packages/app_features/lib/feature_orders/pages/order_review_page.dart
  - app/packages/app_features/lib/feature_orders/routes.dart
  - app/packages/app_features/lib/features_registry.dart
  - app/packages/app_features/lib/app_features.dart
  - app/apps/demo/lib/demo_app.dart
  - app/apps/demo/lib/router/demo_router.dart
  - app/packages/app_features/pubspec.yaml
  - app/pubspec.lock
implementationDigest: 185a877e0efbdf7e3a2b9a3389816cbbf81aa47fc5852793bc6088408c239a10
---

# Security Review：Order Review Media Capture

独立 Security Review 通过，P0/P1/P2 均为 0。Feature 只持有窄 typed API、bounded thumbnail 与 opaque
lease；路径、URI、handle 和异常 details 不进入 Controller/UI。Route close 可主动 dismiss，提交与替换
按 exactly-once 清理，过期 lease 可收敛。
