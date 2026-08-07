---
task: generate-media-capture-android-wire-codec
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/generate-media-capture-android-wire-codec.md
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureWire.g.kt
  - app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/MediaCaptureGeneratedWireTest.kt
  - scripts/quality/media-capture-android.sh
  - docs/bridge/media-capture-android.md
  - app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json
implementationDigest: 9b594f271223391a6fd00193c77e9583af3f25288c5478b084a647ab62bc9c28
---

# Security Review：迁移 Android Media Capture Wire 生成代码

## 已检查边界

- Dart Channel payload 继续按不可信输入处理；生成 Kotlin primitive 对 unknown key、nullable、Int64、
  ByteArray、闭合 enum 和 envelope 结构 fail-closed，不从 enum name 或对象 description 推导 wire 值。
- Capability Failure mapping、main-thread callback、request/owner generation、Engine/Activity lifecycle、transfer
  store、presentation 和 exactly-once completion 均留在手写 Adapter/Native Module，并由既有回归矩阵覆盖。
- 没有修改 CameraX、Manifest、相机/麦克风权限、Native 私有文件目录、Host 注册、依赖来源、签名、网络、
  凭据、CI/Agent/MCP 或发布能力。
- 错误与日志继续脱敏，不回显原始 URI、handle、bytes、路径或平台异常 description。

## 结论

P0/P1/P2 为 0/0/0。JVM/Robolectric、lint 和 AAR 门禁已通过；无 ready emulator，因此设备生命周期和真实
权限仍是明确未验证项，不由静态/JVM 结果替代。

## 2026-08-07 Android Transfer 发布兼容性增量复审

共享 Android Transfer Store 从 hard-link/no-replace 发布改为最终路径 exclusive create；独立报告
`security-media-capture-android-transfer-publish-compatibility-correction.md` 结论为 P0/P1/P2 0/0/0。
生成 Wire codec、Host、权限、Channel 路径暴露和依赖来源边界未扩大；本报告摘要按当前
implementationFiles 重新绑定。无 ready emulator 的设备矩阵缺口保持明确记录。
