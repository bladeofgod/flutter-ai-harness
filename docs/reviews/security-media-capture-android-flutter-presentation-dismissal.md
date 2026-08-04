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
implementationDigest: ac33dee5a57dd8bc1ac07b3fd8862967f20ae28a25fed39584c450d0495edfcb
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

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。
