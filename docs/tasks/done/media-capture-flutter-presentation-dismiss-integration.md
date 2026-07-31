---
executor: task-executor
platforms: [flutter]
workKinds: [integration]
blockedBy:
  - media-capture-android-presentation-dismiss-bridge-adapter
  - media-capture-presentation-dismiss-dart-client
securityReview: required
---

# 接入 Flutter Feature Presentation 主动关闭生命周期

## 目标

- Search、Order Review、Support gateway 暴露窄 `dismissActivePresentation()`。
- reset、Route close 与 dispose 在等待 pending capture 前主动 dismiss。
- Support 新会话启动前结束 pending media pick；cleanup failure 进入稳定错误态并可重试。
- 已自然过期的 media/export handle 按清理已收敛处理，不永久阻断后续拍摄。

## 非目标

- Feature 不接触 request ID、Wire Map、PlatformException 或 Native 类型。
- 不改变拍摄 UI、消息模型、上传行为或 iOS Adapter。

## 验收

- Search/Order/Support 测试覆盖 pending presentation 的 reset/close/dispose、并发发送与会话清理。
- `app_features` 全量测试、`make format`、`make analyze`、`make test`、`make lint` 和
  `git diff --check` 通过。
