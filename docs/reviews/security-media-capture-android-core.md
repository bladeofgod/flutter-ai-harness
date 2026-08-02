---
task: media-capture-android-core
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/android/media_capture/build.gradle.kts
  - app/native/android/media_capture/settings.gradle.kts
  - app/native/android/media_capture/gradle.properties
  - app/native/android/media_capture/consumer-rules.pro
  - app/native/android/media_capture/src/main/AndroidManifest.xml
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/api/AndroidMediaCaptureFactory.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/api/MediaCaptureModels.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/core/MediaCaptureCore.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/framework/AndroidStorageAndThumbnail.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/framework/CameraXCaptureFramework.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/framework/FrameworkContracts.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/rendering/MediaCaptureRenderView.kt
  - docs/infrastructure/media-capture-android.md
implementationDigest: 1d64c68c30d0d93dbb036bf1a79861b709da82ad1e936e8609a684d19ffec1cf
---

# Security Review: Android Media Capture Native Core

## 最终结论

独立 Security Review 通过，P0 0、P1 0、P2 0。审查覆盖 Camera/Microphone 权限、opaque handle、
App 私有媒体、callback-scoped read、metadata/thumbnail、Capability V3 render surface、异步错误、日志和
CameraX 依赖来源。

## 信任边界复核

首轮审查把同进程 Native consumer 通过 `ViewGroup` 遍历 concrete surface child 作为候选 P1。第二位独立
Security Reviewer 按项目威胁模型复核后确认，它没有外部攻击者可控入口：能调用 child traversal 的代码
已经在同一 App 进程内执行并持有 public surface；若恶意依赖已经取得同进程代码执行，View traversal 不是
获得用户画面的必要入口，也不能由一个 View 子类提供机密性隔离。

该关注属于 API 所有权与平台 UI 树可见性的架构说明，不是 Security finding。平台文档已明确：模块不会
通过类型化 API、Channel、callback 或日志交付 source、provider、path、binding 或 backing target；Native
consumer 不得依赖实现 child。同进程 View 树、截屏和反射由 Host 供应链与进程完整性边界负责。

## 已确认边界

- Camera 只在显式 start 触发；Microphone 只在启用音频的录像动作触发；模块 Manifest 不声明 Host 权限，
  Photo Library 不请求。
- Session/Media handle 由平台 CSPRNG 生成，module-instance scoped、不可复用，只做 strict registry lookup，
  不参与路径派生或拼接。
- 媒体只写 App 私有 cache；公共结果不返回路径、URI、descriptor、CameraX 对象或原始媒体。confirmed read
  只在 callback scope 内有效，release/expiry/restart 会撤销、关闭并删除。
- 照片 metadata 净化，thumbnail 受尺寸、字节、并发和内存预算约束，输出重新编码且不保留 EXIF/GPS。
- render source、mount endpoint、binding 和 player/provider 保持 module-internal；generation/identity/lifecycle
  gate 阻止 stale mutation。VideoView error 不传播 `what/extra`，只撤销当前 binding。
- 模块无 render diagnostic 日志，不记录 handle、路径、媒体内容、SDK description 或 raw exception。
- AGP、Kotlin、CameraX、ExifInterface、Coroutine 和测试依赖固定版本，只从 `google()`、`mavenCentral()` 与
  Gradle Plugin Portal 解析；Manifest 无 exported component。

## 验证缺口

证据显示 Debug/Release 各 63 个测试、lint、双 AAR、仓库 lint/harness/diff 均通过。JVM/Robolectric 不能
证明真机权限框、CameraX 实际出帧、MediaPlayer 厂商错误时序、硬件中断、编码器和性能；这些留给 Android
Quality Gate。

## 当前实现复审

独立只读复审重新检查 16-byte CSPRNG handle、App 私有 cache、EXIF 去敏、JPEG thumbnail
canonicalization、active lease 复核、release/expiry cleanup，以及 CameraX/PreviewView 不进入公共 API
的边界。当前实现未发现 P0、P1 或 P2，摘要可同步到当前文件集合。Gradle、Robolectric 与真机权限、
拍照和录像验证未在本轮复审中执行。

## Capability V4 Export 对齐

后续 `media-capture-android-export-core` 在相同公共 API、Core、Framework contract 和 Android 说明中增加
typed sink 流式导出，并把复制区段显式调度到 Factory 注入的 IO dispatcher。该扩展不改变旧任务的
权限、CSPRNG handle、App 私有存储、metadata 净化、render surface 或供应链边界；新增 export 的资源
预算、source lease、sink callback 和取消清理由后续任务的独立 Security Review 负责。本报告据此同步
原 implementationFiles 的当前摘要。

## 跨 Runtime 集成影响

最终集成只更新 Android 状态文档和跨 Runtime consumer test，没有修改 Core 生产代码。JVM/Robolectric、
APK 与设备验证边界已准确区分，独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。
