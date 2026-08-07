---
task: integrate-media-capture-generated-wire-contract
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/integrate-media-capture-generated-wire-contract.md
  - Makefile
  - .github/workflows/ci.yml
  - scripts/git-hooks/pre-push
  - app/lib/src/harness_validator.dart
  - app/test/harness_validator_test.dart
  - docs/bridge/contracts/media-capture.wire.json
  - app/tool/generate_media_capture_wire.dart
  - app/tool/src/media_capture_wire_generation.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_wire.g.dart
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureWire.g.kt
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureWire.generated.swift
  - app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json
  - docs/bridge/README.md
  - docs/bridge/code-generation.md
  - docs/bridge/media-capture.md
  - docs/architecture.md
implementationDigest: 4b0c73d2ba5d01094b17dd002d9851b7ac32f01d763738d3e4d2f18f19dec560
---

# Security Review：集成 Media Capture 三端 Wire 生成链路

## 已检查边界

- Contract、renderer、三端输出、共享 golden 和 Runtime consumer 由 source/implementation digest 双重绑定；
  Harness 拒绝 symlink 输出、marker 缺失、单端再生成及 hand edit，降低生成供应链被局部替换的风险。
- 标准 check/pre-push/CI 只执行 `--check`，不会在审查或 CI 中自动重写源码；写入 generator 是显式独立
  target，路径固定为仓库内普通文件。
- 生成表不拥有相机/麦克风、权限、Native UI、线程/actor、request ownership、transfer store、文件 cleanup、
  日志或错误脱敏；三端手写安全边界和恶意 golden vector 测试继续通过。
- 共享 golden 覆盖 unknown/required/nullable/type/range、signed-64、thumbnail bytes、canonical/malicious file
  URI、handle 和 redaction，三端不能各自维护更宽松的安全表。
- Android/iOS Host build没有增加 Manifest/Info.plist/Entitlements、Photo Library/shared storage 权限、远程
  SwiftPM/Gradle 依赖、本机 framework path、签名、发布、Agent/MCP、commit 或 push 能力。
- CI 使用有界 evidence summary 与 14 天完整脱敏 Artifact；没有新增 secrets 或 workflow write permission。

## 结论

P0/P1/P2 为 0/0/0。生成链路把协议事实收敛到单一 Contract，同时保持平台安全与资源生命周期为手写所有权。
无 Android ready emulator，iOS 真机 Camera/权限/麦克风/中断/性能未验证；这些缺口没有被文本一致性或 Host
编译替代。
