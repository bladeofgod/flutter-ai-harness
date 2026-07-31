# Android Media Capture Host 验证

> 当前状态：2026-07-29 已完成 Demo Debug Host 接线、APK 构建和物理设备安装；订单评价入口与真实
> Camera 行为仍由后置 Flutter Consumer 任务验证。

[返回原生架构](../native-architecture.md) ·
[Android 单平台门禁](media-capture-android-verification.md) ·
[Android Bridge Adapter](../bridge/media-capture-android.md)

## Host 接线

Demo Android Host 通过 Flutter 标准 plugin loader 构建并注册 `app_media_capture_bridge`。Host
`settings.gradle.kts` 以仓库相对路径 include `media_capture_core` 和 `media_capture_ui`，统一声明与三个
Library module 相同的 AGP 8.9.1；App 最低 SDK 使用 `maxOf(flutter.minSdkVersion, 23)`，满足原生模块
边界且继续跟随 Flutter 工具链。

`MainActivity` 仍是空的 `FlutterActivity` 子类，没有 Channel、Wire、权限请求、Session、文件或业务状态。
主 Manifest 只增加：

- `android.permission.CAMERA`
- `android.permission.RECORD_AUDIO`

没有增加 Photo Library、外部存储或媒体读取权限，App 启动时也不会主动请求权限。

## 构建证据

完整输出见 `docs/reviews/test-evidence/media-capture-android-host-integration.log`。最终结果：

| 层级 | 状态 | 证明范围 |
| --- | --- | --- |
| Android 专项门禁 | 通过 | Core/UI/Adapter 双变体测试、lint、契约和可复现依赖仍成立 |
| Demo Debug APK | 通过 | Flutter Host、Adapter、Core/UI 和 Manifest 进入同一真实 Gradle 图 |
| Debug runtime graph | 通过 | `app_media_capture_bridge -> media_capture_core + media_capture_ui -> media_capture_core` |
| Plugin registrant | 通过 | 生成的 `GeneratedPluginRegistrant` 构造并注册 `MediaCaptureBridgePlugin` |
| APK permissions | 通过 | 最终 APK 只有既有 Internet、Camera、Microphone 和 AndroidX 动态 Receiver 权限 |
| 物理设备安装 | 通过 | Debug APK 可安装；证据不记录设备标识 |

Host 初次构建暴露 Library plugin 未在根 settings 声明的问题；最终由 Host 统一增加
`com.android.library` 8.9.1 `apply false` 关闭，不修改平台 Core/UI/Adapter 的独立 Gradle 配置。

## 未验证范围

当前 Flutter 页面尚未调用 `present_capture_flow`，因此“安装成功”不能证明以下行为：

- Camera/Microphone 权限允许、拒绝和永久拒绝。
- 前后摄真实出帧、点击拍照、长按录像、滑动缩放、对焦、闪光、切镜头和 60 秒自动停止。
- 确认/取消/失败三终态、真实缩略图、lease release 和 Activity 中断清理。
- 厂商 CameraX 编码兼容性、内存峰值和性能。

这些行为在 Shoppe 订单评价入口接线后使用同一 Debug Host 真机验证；iOS Host 和跨 Runtime 汇总仍保持
后置，不由本报告推断为通过。
