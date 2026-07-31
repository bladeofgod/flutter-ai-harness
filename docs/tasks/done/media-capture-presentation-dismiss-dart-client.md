---
executor: task-executor
platforms: [flutter]
workKinds: [dart-client]
blockedBy:
  - media-capture-dart-client
  - media-capture-android-flutter-presentation-dismissal
securityReview: required
---

# 实现 Media Capture Presentation 主动关闭 Dart Client

## 目标

- Client 在 presentation request reservation 后记录内部 request ID，完成后清空。
- 同一 Client 只允许一个 presentation slot；并发请求本地返回 typed conflict，不覆盖 dismiss target。
- `dismissActivePresentation()` 只关闭本 Client 的活动请求，重复调用幂等。
- `dispose()` 先 dismiss，再等待 pending；late confirmed media 仍按既有规则释放。

## 非目标

- 不向 Feature 暴露 request ID、Wire Map 或 PlatformException。
- 不修改 Native Adapter、Feature Controller 或 UI。

## 验收

- 测试覆盖精确关联、并发 present、本地 conflict、cancelled terminal、重复 dismiss 和 dispose-before-wait。
- Bridge Package 全量测试、`make format`、`make analyze`、`make test`、`make lint` 和
  `git diff --check` 通过。
