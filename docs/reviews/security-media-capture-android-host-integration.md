---
task: media-capture-android-host-integration
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/apps/demo/android/settings.gradle.kts
  - app/apps/demo/android/app/build.gradle.kts
  - app/apps/demo/android/app/src/main/AndroidManifest.xml
  - app/apps/demo/android/app/src/main/kotlin/com/example/demo_app/MainActivity.kt
  - docs/native/media-capture-android-host-verification.md
implementationDigest: efaafd9c393fb26b98f1bfeddcfa124c7c37a8d2a101e6e48249a19954f1c22a
---

# Security Review: Android Media Capture Host Integration

## 结论

Security Review 通过，P0 0、P1 0、P2 0。审查覆盖原生权限、Gradle project 来源、Plugin 自动注册、Host
能力边界、设备安装和证据脱敏。

## 已确认边界

- Host 只声明功能所需的 Camera/Microphone；没有相册、外部存储、广泛媒体读取或导出组件变化。
- 权限不会在 App 启动时请求，实际请求仍由已审查 Adapter/Core 在明确用户拍摄动作中执行。
- Core/UI 使用固定仓库相对 projectDir；前置 Android 专项门禁拒绝模块 symlink、本机路径、动态依赖和
  未批准仓库，并在本任务开始时重新通过。
- 新增 AGP Library 声明与锁定的 8.9.1 相同，没有引入新 Plugin、仓库、下载脚本或依赖版本。
- `GeneratedPluginRegistrant` 注册既定 `MediaCaptureBridgePlugin`；`MainActivity` 没有获得 Wire Map、
  Session、文件、路径、媒体 bytes 或业务状态。
- 安装命令不包含设备 serial，入库 evidence 没有设备标识、用户名、主机路径或真实媒体。

## 验证与剩余风险

最终 APK permission dump、runtime project graph、Registrant bytecode、Debug build、安装、Harness 和 diff
证据均为退出码 0。Camera/Microphone 系统对话框、真实出帧和厂商硬件行为尚未触发，不由本报告推断；
它们必须在后置 Flutter Consumer 接入后用真机验证。
