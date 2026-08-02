---
task: media-capture-ios-native-ui
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/ios/MediaCaptureUI/Package.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/CaptureGestureController.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureChromeView.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureFlowCoordinator.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureLeaseCleanupOwner.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureServicing.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureUiModels.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureUiPresenter.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureViewController.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/Resources/en.lproj/Localizable.strings
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/Resources/zh-Hans.lproj/Localizable.strings
  - docs/native/media-capture-ios-ui.md
implementationDigest: adf89123b6d1636409a649bca6ac126acb9b487dbdf152127cb0f1e9945cb025
---

# Security Review: iOS Media Capture Native UI

## 结论

最终独立只读 Security Re-review 通过，P0 0、P1 0、P2 0。审查覆盖 Camera/Microphone lifecycle、
unconfirmed/confirmed lease、late cleanup、transaction admission、Scene/owner/surface generation、输入钳制、
敏感信息、依赖和 Flutter/Wire/路径隔离，未发现具体可利用路径。

## 已确认控制

- lifecycle 先关闭 action/event transaction 准入，再取消并有界等待 action、event operation 与旧
  lifecycle；被淘汰 generation 不会与新 surface 并发提交。
- late `startSession` 交给 Session cancellation settle；late confirmed lease 在 timeout callback 再次进入
  release settle，不静默丢失 handle。
- event operation timeout 显式取消父 event task，Fake `AsyncStream.onTermination` 测试证明订阅终止；
  自然 stream 结束映射 `system_interrupted` 并清理 Session。
- surface detach、Session cancel、Media release 和 UIKit dismissal 分别有 5 秒返回边界。Media release
  只对明确暂时的 `invalid_state` 由进程级 cleanup owner 退避重试；永久类型化结果和非类型错误停止重试。
  deferred hold 清零前 slot 保持 poisoned，收敛后恰好释放一次。
- owner registry 使用 object identity 与随机 token；Scene notification 按当前对象 identity 过滤，surface
  generation 严格递增。focus 检查 finite 与 `[0,1]`，zoom 使用 UI 内部增量并按 Core snapshot 钳制。
- 公开 `awaitResult()` 的 cancellable waiter 以 UUID 隔离；已有结果优先。登记前取消由 MainActor
  continuation 闭包直接触发 `system_interrupted` cleanup，登记后取消与 `complete` 串行移除同一 waiter，
  不会双重恢复、跨 waiter 删除或只抛取消而遗留活动 flow。
- UI 不接触媒体路径、URI、原始字节、FileHandle、read scope 或 AVFoundation capture 对象，不记录
  handle/token；Package 仅依赖仓库内 `MediaCapture` 与 Apple UIKit，没有远程供应链。

## 已关闭的 Cleanup P2

`media-capture-ios-cleanup-terminal-outcomes` 已同时收敛 Core Failure 语义和 UI retry allowlist：closed、
expiry、discarded、restart 后旧 handle 返回 `media_invalid`；仅 teardown/restart 进行中返回可重试的
`invalid_state`。确定性测试覆盖初次 release 与 adopted retry 的永久类型化及非类型错误，证明任务停止且
slot 恰好恢复一次。独立 Security Reviewer 复核后将该 P2 关闭。

## 验证边界

当前 evidence 记录 51 个 Simulator XCTest、generic iOS Simulator Debug build、边界扫描和 `make lint`
全部通过。受控测试分别覆盖 blocked detach、cancel、late release 与 UIKit dismissal，证明公开结果有界、
cleanup 未收敛时 slot 保持 poisoned，并在 late cleanup 完成后恰好恢复。镜头切换等待新 capability snapshot
再恢复 action，后台 retake、event stream 结束，以及公开结果等待的登记前/登记后取消也有直接回归。

Simulator/Fake 不能证明真机 Camera/Microphone 权限 UI、真实 preview/录像/音频、来电或相机占用、Scene
硬件时序、后台恢复和长录制温度/内存/存储错误。这些保留给 iOS Quality Gate 与用户最终真机验收。

本轮 Reviewer 未读取普通 Review 报告，未运行构建或修改实现。

## 严格并发修正后的摘要对齐

后续 correction 把 NotificationCenter 的 background/foreground MainActor action 放入显式 Sendable relay，
不再由 Sendable callback 捕获 scene 对象；scene identity 仍由注册时的 `object:` filter 与 observation
`matches` 保证。Observer token 增加 MainActor `invalidate()`，rebind 先解除旧注册，deinit 只做隔离明确的
幂等兜底。权限、owner registry、surface generation、flow cleanup、媒体边界和依赖均未改变；51 个 UI
XCTest 与完整严格并发 generic Simulator build 通过，本报告摘要机械更新到当前实现快照。
