---
task: media-capture-cross-runtime-integration
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - .github/workflows/ci.yml
  - Makefile
  - README.md
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/apps/demo/pubspec.yaml
  - app/apps/demo/ios/Podfile.lock
  - app/apps/demo/ios/Runner.xcodeproj/project.pbxproj
  - app/apps/demo/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
  - app/apps/demo/ios/Runner/Info.plist
  - app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt
  - app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json
  - app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift
  - docs/bridge/contracts/media-capture.wire.json
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
  - scripts/quality/media-capture-android.sh
  - scripts/quality/media-capture-ios.sh
  - docs/README.zh-CN.md
  - docs/architecture.md
  - docs/bridge/media-capture.md
  - docs/bridge/media-capture-android.md
  - docs/bridge/media-capture-ios.md
  - docs/infrastructure-modules.md
  - docs/infrastructure/media-capture.md
  - docs/infrastructure/media-capture-android.md
  - docs/infrastructure/media-capture-ios.md
  - docs/infrastructure/media-resources.md
  - docs/native-architecture.md
implementationDigest: c2e9b00c219bb6666b8d2f37c4950a96eb68086a650fbeb24da799a87276668b
---

# Security Review：Media Capture 跨 Runtime 最终集成

## 结论

独立 Security Review 与修复复审通过，P0 0、P1 0、P2 0。Security Reviewer 未依赖普通 Review 结论，
只读核对 Host 权限与依赖边界、外部媒体输入、transfer/store ownership、跨 Runtime golden、CI、Harness、
文档和 evidence，没有修改实现。

## 已确认边界

- Android/iOS Host 只负责权限声明、模块装配和标准 Plugin 注册，不解析 Wire、不保存媒体 locator，也没有
  增加 Photo Library/shared storage 权限、Entitlement、CocoaPods fallback 或本机 framework path。
- 外部 picker/Camera 结果进入平台私有 transfer root 后才通过 scoped handle 暴露；URI canonicalization、
  symlink/traversal、MIME、长度、配额、TTL、tombstone、restart/detach/late cleanup 和无路径日志均由三端
  vectors、平台 Gate 与 Harness 交叉约束。
- Store commit 后释放 transfer/source lease，消息只持有 `MediaResourceId`；会话 reset、消息删除和 Registry
  dispose 按 owner 顺序卸载 Thumbnail/Viewer 并释放最终资源，没有把临时路径作为消息身份传播。
- golden 绑定 Dart/Kotlin/Swift 消费者的路径和实现摘要；Harness 对契约与消费者漂移失败关闭，防止只保留
  测试文件名或局部断言造成伪通过。
- Info.plist 使用结构化 XML 校验唯一、非空字符串权限说明；CI 与证据脚本不记录真实媒体、URI、handle、
  设备 ID、主机路径、公司设计信息或凭据，也没有增加签名、发布、commit 或 push 能力。

## 剩余边界

Android API 23 instrumented、Camera/Gallery 主动流程和 iOS 真机 Camera/Microphone、系统权限 UI、硬件中断、
真实帧及性能仍需人工设备验收。现有构建、Simulator 与静态门禁只证明可编译、契约和软件层行为，不把这些
结果提升为硬件能力已通过。
