---
executor: android-engineer
platforms: [android]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-android-bridge-adapter
  - media-capture-presentation-dismiss-dart-client
  - media-capture-android-flutter-presentation-dismissal
securityReview: required
---

# 实现 Android Presentation 主动关闭 Bridge Adapter

## 目标

- Android Controller 按原 presentation request ID 精确 dismiss 当前原生拍摄页。
- 已展示 UI 与权限预检中的请求都在 main dispatcher 完成取消，原请求返回 cancelled。
- 未知、重复或已完成 target 幂等成功，不影响其它 presentation。
- Flutter success callback 抛错后执行 late cleanup，保持资源 exactly-once。

## 非目标

- 不实现 iOS Adapter，不修改 Camera Core/UI 样式或 Feature Controller。
- 不把 request ID 写入日志、错误 details 或持久状态。

## 验收

- Android 测试覆盖展示中、权限预检中、未知/重复 target、callback failure 与 exactly-once。
- Android Debug/Release tests、lint、专项 gate、Demo Debug APK 和 `git diff --check` 通过。
