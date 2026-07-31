---
task: media-capture-android-native-ui
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/android/media_capture_ui/build.gradle.kts
  - app/native/android/media_capture_ui/settings.gradle.kts
  - app/native/android/media_capture_ui/gradle.properties
  - app/native/android/media_capture_ui/consumer-rules.pro
  - app/native/android/media_capture_ui/src/main/AndroidManifest.xml
  - app/native/android/media_capture_ui/src/main/kotlin/com/example/mediacapture/ui/CaptureGestureController.kt
  - app/native/android/media_capture_ui/src/main/kotlin/com/example/mediacapture/ui/MediaCaptureChromeView.kt
  - app/native/android/media_capture_ui/src/main/kotlin/com/example/mediacapture/ui/MediaCaptureFlowCoordinator.kt
  - app/native/android/media_capture_ui/src/main/kotlin/com/example/mediacapture/ui/MediaCaptureLeaseCleanupOwner.kt
  - app/native/android/media_capture_ui/src/main/kotlin/com/example/mediacapture/ui/MediaCaptureUiModels.kt
  - app/native/android/media_capture_ui/src/main/kotlin/com/example/mediacapture/ui/MediaCaptureUiPresenter.kt
  - app/native/android/media_capture_ui/src/main/res/values/strings.xml
  - app/native/android/media_capture_ui/src/main/res/values-zh-rCN/strings.xml
  - docs/native/media-capture-android-ui.md
implementationDigest: b066aecbd5adc2965428ac6ce4658032dee52cc02dfe7b6c4c2f5980529fb9d1
---

# Security Review: Android Media Capture Native UI

## 最终结论

独立 Security Review 的首轮问题已经关闭，最终 P0 0、P1 0、P2 0。审查覆盖 presentation ownership、
Activity/owner lifecycle、Camera/Microphone Session、confirmed lease、surface generation、Manifest、日志、
依赖来源和 Flutter/Wire 隔离。

## 已关闭问题

- 同一 Activity 的不同 Fragment/view LifecycleOwner 不能绕过 presentation gate；严格 identity 不受自定义
  `equals/hashCode` 影响，Activity destroy 总有独立回调进入 terminal cleanup。
- owner destroy、dismiss、后台失败和 concurrent terminal 会先关闭 action gate；晚到 Session 必须 cancel，
  surface/session/action 未确认 settle 时不会开放新 presentation。
- confirm commit/cancel 的 handle 不会因 `ConfirmedMedia` 未返回而丢失；短重试失败后由独立模块 scope 持有，
  不记录 handle，不把 cleanup 生命周期交给已经销毁的 Activity scope。
- surface mutation 检查 scope/generation/lifecycle，UI 只持有 Core concrete render view；没有 source、provider、
  path、URI、descriptor、media bytes、SDK description 或 raw exception 输出与日志。
- 模块 Manifest 没有权限、Activity、Service 或 exported component；AGP、Kotlin、AndroidX、Coroutine、JUnit
  与 Robolectric 均固定版本，只使用标准公开仓库。

## 验证缺口

Debug/Release 各 41 个 JVM/Robolectric 测试和 lint 已通过。Fake Core 不能替代真机权限、CameraX、编码器、
硬件中断和性能验证；这些风险明确留给 Android Quality Gate。

## 当前实现复审

独立只读复审重新检查 Activity identity 单槽、主线程 present、owner destroy/system interrupted、
confirmed late lease release、surface generation 替换与前后台 reattach。当前实现未发现 P0、P1 或
P2，摘要可同步到当前文件集合。Android UI/local tests 与真实预览帧、权限框、旋转和硬件表现未在
本轮复审中执行。
