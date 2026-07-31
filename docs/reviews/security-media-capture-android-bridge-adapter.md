---
task: media-capture-android-bridge-adapter
status: passed
p0: 0
p1: 0
implementationFiles:
  - app/packages/app_media_capture_bridge/android/build.gradle.kts
  - app/packages/app_media_capture_bridge/android/settings.gradle.kts
  - app/packages/app_media_capture_bridge/android/gradle.properties
  - app/packages/app_media_capture_bridge/android/consumer-rules.pro
  - app/packages/app_media_capture_bridge/android/src/main/AndroidManifest.xml
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureBridgeController.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureBridgePlugin.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCapturePermissionDelegate.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt
  - docs/bridge/media-capture-android.md
implementationDigest: 286554d4fe5129d92f88fb3099d6fa469b4ecc96d6e93ea660547d52f5b3bc53
---

# Security Review: Android Media Capture Bridge Adapter

## 权限预检增量审查

为解决进入拍摄器后才申请权限的问题，Bridge 新增了 `present_capture_flow` 权限预检。独立安全审查确认
该增量当前为 P0 0、P1 2、P2 0，安全门禁重新标记为失败：

1. 匹配本模块 pending `requestCode` 的空权限回调会在长度校验处直接返回，既不移除 pending，也不完成
   等待者。当前拍摄请求和 presentation slot 因此可能永久悬挂，后续入口持续返回冲突。修复必须原子消费
   该空回调并完成稳定失败，同时覆盖恰好一次完成和失败后可重试。
2. 权限预检完成后的 owner 检查与真正 `present`/session 登记分属不同调度阶段；Activity 或 Engine 可在
   两者之间 detach，导致旧 presenter 仍向失效 Activity 创建敏感 UI。修复必须在 Android main/lifecycle
   协调区间内串行化最终 owner/slot 检查、`present` 与 session 登记，并在 detach 开始时先禁止 delegate
   发起新权限请求。

已确认权限预检只影响 `present_capture_flow`；Camera 始终申请，Microphone 只在视频且启用音频时申请；
Manifest 权限范围没有扩大，稳定错误不包含路径、媒体、异常或权限数据。真实系统权限弹窗、旋转、后台
切换和硬件能力仍需要真机验证。

## 复审

两个权限预检 P1 均已关闭，复审结论为 P0 0、P1 0，没有新增 P2；原报告中的 fail-closed P2 继续保留，
安全门禁通过。

- 匹配 pending `requestCode` 的双空数组回调现在会被原子消费并完成稳定拒绝；重复回调不会二次完成，
  后续请求可以使用新的 request code 重试。
- 权限 delegate 新增立即失效阶段。Activity/Engine detach 在异步 cleanup 前先关闭 owner/engine generation
  并使 delegate 失效，等待中的权限请求不能抢赢已经开始的生命周期 boundary。
- 最终 request、owner、presentation slot 和平台生命周期检查、`present()` 与 session 登记已在 Android
  main dispatcher 和 Controller lock 的同一非挂起区间线性化，旧 Activity 不会在最终检查后创建 UI。
- 回归测试覆盖空回调 exactly-once、失败后重试、照片/静音视频不申请麦克风、预检前 Activity detach、
  权限返回后 present 前 Activity detach，以及预检期间 Engine detach。

调用方强制重跑 Debug/Release 各 45 项测试与 `lintDebug`，并成功构建 Demo Debug APK。Robolectric 与
构建证据仍不能替代首次授权、普通拒绝、永久拒绝、弹框期间旋转/退后台、Activity 重建和 CameraX 硬件
启动的真机验证。

## 历史基线结论

独立 Security Review 最终为 P0 0、P1 0、P2 1，任务安全门禁通过。审查覆盖攻击者可控 Channel 输入、
Camera/Microphone 权限、Session/Preview/lease/thumbnail、Activity/Engine boundary、错误/日志脱敏、Manifest
和依赖来源。

首轮 P1 6、P2 2 与后续 settling-handle P2 均已关闭：

- command 65536 bytes、event control 4096 bytes 在 Map 解码前拒绝；payload、error details、requestId、
  handle、路径、URI、bytes 和异常均不回显或记录；
- opaque handle 只检查 1 至 128 字符，不解析为路径；active/preview/settling registry 防止跨 Core 同名
  handle 污染，旧 `media_read_revoked` 不会投递为新 owner 的 revoke；
- late Session/lease/thumbnail 与 cleanup failure 都保留清理所有权；Engine closing 的 late lease 不等待已
  关闭 Event sink，Core/event collector/Engine scope 可完成退出；
- 权限 delegate 只请求 CAMERA/RECORD_AUDIO，回调必须匹配 request code、权限名与单元素结果；Manifest
  没有权限、Activity、Service 或 exported component；
- 原始 thumbnail copy 在编码后清零，传输 copy 在同步 StandardMethodCodec 编码后清零；JPEG 拒绝
  EXIF/APP1-APP15/COM、错误 marker order、维度不符和非 canonical JFIF；
- Android Event handler 不使用会自动取消旧 sink 的平台 EventChannel wrapper，第二个 listen 返回
  `listener_already_active` 且不替换 coordinator 中的旧 generation。

## 剩余 P2

若已归档的 Native UI 违反其 terminal 契约，`dismiss()` 后永久不完成 `awaitResult()`，Adapter 会保持旧
owner 的 `boundaryCleanupInProgress` 并拒绝新 capture。这是对未确认相机/lease cleanup 的 fail-closed
策略；不能用 Adapter 超时后强行开放 slot，否则会允许新旧 Camera Session 重叠。Native UI 已有 bounded
terminal/poisoned cleanup 测试，Android Quality Gate 继续用真实三层接线验证这一依赖契约。

## 验证缺口

Debug/Release 各 35 个 JVM/Robolectric 测试和 lint 已强制重跑并通过。真实 Host 注册、Activity 重建、系统
权限框、CameraX frame、硬件录像/中断和设备性能仍需 Android Quality Gate、Host 与真机证据。

Android 平台 Gate 后续确认并移除了没有生产消费者的 `activity-ktx` 直接依赖；该变更只缩小依赖面，最终
实现摘要和 35/35 强制重跑 evidence 已按移除后的 build graph 刷新。
