---
task: media-capture-android-flutter-presentation-dismissal
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/bridge/contracts/media-capture.wire.json
  - docs/bridge/media-capture.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: 9cdf5814d50b19c4b5971b19a679b1d1164cdf8fbfbc26682e33abdaf2925575
---

# Security Review：Presentation Dismiss Wire

独立 Security Review 通过，P0/P1/P2 均为 0。请求只接受原 presentation request ID，不接受 Session、
Media、路径、URI 或自由文本；错误和日志不回显 ID。Harness 精确拒绝错误 format、错误 payload 与
Android/iOS 支持矩阵回退。

后续 iOS Adapter 前置契约把 iOS support 提升为 `supported`，没有改变 Android 已审查的 request
correlation、幂等 dismiss、exactly-once 或 redaction。独立 Security Reviewer 确认 P0 0、P1 0、P2 0，
摘要已绑定当前共享文件；iOS Runtime 可发布性仍由后续 Adapter 与 Quality Gate 证明。

## 跨 Runtime 集成影响

最终集成只修正 Wire current method 计数并把 dismiss 纳入三端 current set，没有改变 Android presentation
终态或 owner cleanup。独立安全复审为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。
