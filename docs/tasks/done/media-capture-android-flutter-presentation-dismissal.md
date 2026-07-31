---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy:
  - media-capture-native-ui-flow-wire-evolution
securityReview: required
---

# 演进 Media Capture Presentation 主动关闭 Wire

## 目标

- 在 Wire V3 增加严格闭合的 `dismiss_capture_flow` Adapter lifecycle method。
- 请求只携带原始 `present_capture_flow` 的 opaque `presentationRequestId`，结果 payload 为空。
- Android 声明 supported；iOS 在后续 Adapter 完成前明确为 unsupported。
- Harness 只允许这一项 Wire-only lifecycle method，并保持 Wire V1/V2 历史投影不变。

## 非目标

- 不增加 Capability operation，不接受 Session/Media handle、路径、URI 或媒体 bytes。
- 不实现 Dart Client、Android/iOS Adapter 或 Feature 生命周期接线。

## 验收

- 合同、Harness 正例和恶意 fixture 覆盖 request ID format、错误 payload 与 iOS 过早支持。
- `make harness-test`、`make harness-check`、`make format`、`make analyze`、`make lint` 和
  `git diff --check` 通过。
