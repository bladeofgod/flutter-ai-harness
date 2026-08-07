---
task: generate-media-capture-ios-wire-codec
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/generate-media-capture-ios-wire-codec.md
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeController.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeModels.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureWireCodec.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureWire.generated.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift
  - app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh
  - docs/bridge/media-capture-ios.md
  - app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json
implementationDigest: 846a32aa9710b4b2856ff31ac6700deace2661cb7e971dc18bffd48208458419
---

# Security Review：迁移 iOS Media Capture Wire 生成代码

## 已检查边界

- Flutter Channel payload 继续是不可信输入；生成 Swift primitive 严格区分 NSNumber/Bool、Int64、NSNull、
  Data/Flutter bytes、nullable、unknown key 和闭合 enum，错误不回显 payload 或平台对象 description。
- Capability mapping、MainActor callback、owner generation、ViewController lifecycle、transfer store、
  presentation、文件 cleanup 与 exactly-once completion 保持手写，并由 229 个 Simulator tests 覆盖。
- 未修改 AVFoundation/UIKit Native Capability、Info.plist、Entitlements、相机/麦克风权限、Host、依赖来源、
  签名、网络、凭据、CI/Agent/MCP 或发布能力。
- 临时 Host 在权限受限目录中执行，safe-copy 和前后摘要确认真实 Demo Host及用户 Flutter 配置未变；完整
  私有 build output 未入库。

## 结论

P0/P1/P2 为 0/0/0。Simulator/compile/Host discovery 已通过，但 live camera、系统权限 UI、麦克风、硬件中断
和性能仍需真机验证；生成迁移没有扩大这些原生能力边界。
