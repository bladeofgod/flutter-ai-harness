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
implementationDigest: bf4c366826848669ee60f48c14c00bac16d86512cc46b01860ec314e39c83617
---

# Security Review：Order Review Media Capture

独立 Security Review 通过，P0/P1/P2 均为 0。Feature 只持有窄 typed API、bounded thumbnail 与 opaque
lease；路径、URI、handle 和异常 details 不进入 Controller/UI。Route close 可主动 dismiss，提交与替换
按 exactly-once 清理，过期 lease 可收敛。

## 跨 Runtime 集成影响

最终集成只更新共享 lockfile、Host、golden、Harness 与状态文档，没有修改订单评价媒体实现。根 `xml`
仅服务 Harness plist 校验；独立安全复审为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。

## Session Reset 生命周期影响

`DemoApp` 现在持有并在卸载时解除自己的 Session Reset 注册，外部 Registry 在已登出 Coordinator 下
重新挂载时会先清理会话状态。reset 回调失败会脱敏上报且不阻断后续清理或登出，因此订单评价草稿
不会因其它注册失败而跳过 reset。本轮未改变订单评价媒体的 lease、release 或 dispose 语义。

## Workspace 消费检查器影响

共享 lockfile 只把既有 `analyzer 10.0.1` 从传递依赖提升为根工具直接 dev dependency，版本、来源与
SHA-256 未变。订单评价媒体生产代码、Bridge lease 和 cleanup 语义未修改。

## Workspace 冗余依赖清理影响

`app_features` 仅移除空的 `app_im` 依赖，订单评价仍直接消费 Media 与 Bridge；共享 lockfile 没有新增
版本或来源。订单草稿、opaque lease、release 与 dispose 语义未改，P0/P1/P2 维持 0/0/0。

## Wire Formatter 工具依赖影响

共享 lockfile 新增精确固定的 `dart_style 3.1.7` direct dev dependency，仅供 Wire generator 内存格式化，
不进入订单评价或 Bridge Runtime。订单草稿、opaque lease、release 与 dispose 语义均未修改，
P0/P1/P2 维持 0/0/0。
