---
task: media-capture-android-host-integration
status: passed
p0: 0
p1: 0
---

# Review: Android Media Capture Host Integration

## 结论

最终 P0 0、P1 0。Host 只承担 Gradle include、工具链统一、权限和标准 Plugin registration，没有把
Wire、拍摄状态、资源租约或业务导航写入 `MainActivity`。

## 已确认实现

- 根 settings 统一声明 application/library AGP 8.9.1 和 Kotlin 2.1.0，并以仓库相对路径 include
  `media_capture_core`、`media_capture_ui`。
- Adapter 由 Flutter plugin loader 接入；生成 `GeneratedPluginRegistrant` 明确构造并注册
  `MediaCaptureBridgePlugin`，Host 没有手工注册或直接调用 Client。
- App 最低 SDK 取 Flutter 默认值与 23 的较大值，满足三个原生 Library module，不与 Flutter 工具迁移
  反复冲突。
- 主 Manifest 只新增 Camera/Microphone。最终 APK 的权限清单没有 Photo Library、外部存储或媒体读取。
- `MainActivity` 仍是空的 `FlutterActivity` 子类。

## 构建修复

首轮真实 APK 构建发现 Library plugin 已在 Flutter classpath 但版本未知。修复只在 Host settings 增加
同工具链 `com.android.library` 8.9.1 `apply false`；随后 Debug runtime graph、APK build、Registrant 和
Manifest 合并全部通过，没有修改 Core/UI/Adapter。

## 验证与剩余边界

证据见 `docs/reviews/test-evidence/media-capture-android-host-integration.log`：Android 专项门禁、Debug APK、
runtime dependency graph、APK permission dump、Registrant bytecode、物理设备安装、Harness 和 diff 检查
均通过。日志保留首轮构建失败，后续成功命令代表最终状态。

本任务没有 Flutter Consumer，不能把 APK 安装表述为 Camera 已运行；真实拍摄、权限交互、缩略图和 lease
cleanup 留给 `shoppe-order-review-media-capture`。
