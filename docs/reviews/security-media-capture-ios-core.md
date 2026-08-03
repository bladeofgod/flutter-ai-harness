---
task: media-capture-ios-core
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/ios/MediaCapture/Package.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/AVFoundationCapturePlatform.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/AppleMediaStorage.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/InternalDependencies.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureCore.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureModels.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureRenderBoundary.swift
  - app/native/ios/MediaCapture/Sources/MediaCaptureAppleRendering/MediaCaptureRenderView.swift
  - docs/infrastructure/media-capture-ios.md
implementationDigest: 298e7dd737a5897b74a46abb358fa55620aa3d4fc0157ef78be6e9c552c9274d
---

# Security Review: iOS Media Capture Native Core

## 最终结论

独立 Security Review 与最终复审通过，P0 0、P1 0、P2 0。审查覆盖 Camera/Microphone 权限、opaque
handle、App 私有媒体、callback-scoped read、metadata/thumbnail、Capability V3 render surface、actor/
callback gate、日志和 SwiftPM 供应链。

## Read lease 竞态修复

首轮发现 `withMediaRead` 在 `fileStore.openSource` 的 actor reentrancy window 后缺少二次状态提交，release
或 expiry 可能先结束 lease，late source 却被登记为新 read。第一轮修复增加当前 record/state/reference
校验；安全复审进一步指出，lease deadline 已过但 deadline task 尚未调度时，state 仍可能暂时是 leased。

最终实现会在 `openSource` 返回后先处理 deadlines，再重新读取 record，并同时要求同一 storage reference、
`state == leased`、存在 lease deadline 且 `deadline > now`。任一条件失败立即关闭 source，以稳定 Failure
返回，且不会写入 `readScopes`。受控 Fake 分别覆盖 release-during-open 和 lease-expiry-during-open，断言
`invalid_state`、source 已关闭且没有 late read capability。最终普通与 Security Reviewer 均确认问题关闭。

## 已确认边界

- Camera 只在显式 start 触发；Microphone 只用于启用音频的录像动作；Photo Library 不请求。denied、
  permanently denied 与 restricted 按 iOS 可表达语义稳定映射。
- Session/Media handle 使用 Security Framework CSPRNG、实例内永不复用和 strict registry lookup，不从路径
  派生；公共 API 不暴露 URL、descriptor、AVFoundation、UIKit 或 CALayer 类型。
- 媒体位于 App 私有 temporary/cache 且使用文件保护；release/expiry grace 后关闭 read source 并删除文件；
  restart/close 关闭全部 read scope 和 platform resource。
- 照片 metadata 与 thumbnail 重新编码净化；输出有尺寸、字节、并发和 working-memory 上限，中间 buffer
  在失败、取消和 loser 路径擦除。
- Rendering product 的 source、endpoint、binding、session/player/layer 只在 Swift `package` 边界；pending/
  committed gate 与 generation/identity/lifecycle 校验阻止 stale mutation。
- Package 只依赖 Apple Framework，没有第三方 SwiftPM package；实现不记录 handle、路径、媒体内容、
  platform description 或 raw exception。

## 此前验证缺口

iOS Simulator SDK `swift build --build-tests` 当时已编译全部 product/test target，仓库 lint/harness/diff
通过。两条 mandatory generic Simulator `xcodebuild` 因本机缺少 iOS 26.5 platform component 退出 70，
因此当时不能归档。Simulator/Fake 也不证明真机权限 UI、中断、编码性能或内存峰值。

## 平台门禁解除后的最终安全复审

iOS 26.5 platform component 可用后，独立 Security Reviewer 对最终实现、测试、文档和脱敏 evidence
重新复核，结论为 P0 0、P1 0、P2 0。`AVCaptureSession` 配置在 `startRunning` 前完成 commit；自动录像
deadline 按 task identity 领取后再执行，避免 cleanup 取消当前任务。照片重新编码会去除 GPS、设备字段和
用户备注；视频先构造只复制 audio/video 时间段与方向的全新 composition，再以空 metadata 和 sharing
filter 导出，真实 MOV 测试证明 container location/make 与 track model 不进入净化副本。

两条 mandatory generic iOS Simulator build 与 `MediaCapture-Package` 的 74 个 XCTest 均通过。Simulator/
Fake 仍不能证明真机 Camera/Microphone 授权 UI、硬件 interruption、实际编码性能和大媒体内存峰值；这些
是后续 iOS quality gate 的设备证据边界，不构成本 Core 快照的安全 finding。

## 实例隔离与轨道时序修复待复审

后续普通复审发现跨 Core temporary root 删除和 composition track offset 问题。实现已增加实例隔离目录、
active-root registry、双 Core lease/read/thumbnail 测试，并改为复制非空 media segment、保留相对 offset、
从净化输出重新计算公开 metadata。当前实现摘要已变化，上一轮 Security Review 不再绑定最新快照；在独立
安全复审更新 `implementationDigest` 前，本报告保持 failed，不能用于归档。

## 实例清理竞态最终复核

安全复审在最终实例隔离实现中发现 active-root 快照与目录枚举/删除之间的 TOCTOU：新 Core 可能在旧快照
生成后注册并创建目录，随后被误删。修复后 registry 在同一锁域内枚举目录、核对 active set 并删除残留；
`register` 在清理完成前不能返回。确定性测试阻塞删除并并发注册，证明新 Core 只能在清理结束后创建目录，
且后续清理保留其 active root。

全量测试同时覆盖并关闭了 release/expiry grace 的重复 deadline cleanup：terminal state 在物理删除前
原子提交，竞争 processor 不会对同一租约执行第二次删除。删除完成后才发送 revoke event 的顺序保持不变。

最终实现摘要为 `c1f0c49ac299b1983031f30e89676923e731d3a5fd32cb5e5a79bb4cb00e3afc`。两条 generic
Simulator build、共 78 项 XCTest、`make lint`、`make harness-check` 与 `git diff --check` 最终均通过。
P0 0、P1 0、P2 0；真机权限 UI、硬件 interruption、锁屏文件保护、设备 MOV metadata 变体和大媒体性能
仍由后续 iOS quality gate 验证。

## Export 演进后的摘要对齐

后续 Export Core 在 `AppleMediaStorage`、`InternalDependencies`、`MediaCaptureCore`、
`MediaCaptureModels` 与同一 iOS 基础设施文档上增加有界 typed-sink 能力，因此本报告摘要更新为当前共享
文件快照。原 Core 权限、存储、渲染、租约与 actor 边界未回退；新增 Export 攻击面由独立
`security-media-capture-ios-export-core.md` 审查并通过。本报告与 Export 报告共同覆盖当前重叠文件。

## 镜头切换修正后的摘要对齐

后续 correction 明确 AVFoundation `switchCamera` 成功返回为不可回滚提交点。Core 会在同一 Session
operation ownership 下提交新 capability snapshot 并发送 `sessionReady`；caller cancellation 或纯 Render
lifecycle epoch 不会制造物理镜头与 registry 分叉，terminal/cancel/restart/generation 替代仍阻止晚写回。
独立 Security Reviewer 对最终 Core/UI 快照复审为 P0 0、P1 0、P2 0；专项安全结论记录在
`security-media-capture-ios-camera-switch-correction.md`。当前完整 evidence 为 Core 93 个、Apple
Rendering 6 个、Public Consumer 2 个 XCTest，scheme 合计 101 个测试；两条 generic Simulator build 与
lint 通过。

## Cleanup 永久终态修正后的摘要对齐

后续 cleanup 任务把 closed、expired、discarded 和 restart 清理后的 release 统一为不可恢复的
`media_invalid`，只保留 teardown/restart 进行中的 `invalid_state` 作为明确暂时状态。原有权限、存储隔离、
read lease、渲染、脱敏与供应链控制未回退；独立 Security Reviewer 对当前共享文件完成影响复核，P0/P1/P2
均为 0。本报告绑定更新到当前快照。

## 严格并发修正后的摘要对齐

后续 correction 只把内部 `CapturePlatform` 协议、AVFoundation session queue 工作闭包/返回值和
operation completion 泛型的既有并发保证显式表达为 `Sendable`，并调整测试 helper 以通过 Xcode 26.5
完整严格并发编译。没有新增 `@unchecked Sendable`、资源所有权、权限、文件、媒体、日志或依赖行为；
既有安全控制与结论不变。完整 Core Package XCTest 和两个 generic Simulator product build 均在 warning
作为 error 时通过，本报告摘要机械更新到当前共享实现快照。

## iOS 综合修正后的最终复审

带声录像现在在正常停止、启动失败、取消、停止失败、并发 cancel/stop 与 Session 停止路径释放 audio
input；retake 先提交旧媒体 discarded 和 Session ready，再异步删除文件。PreviewLayer 对焦转换只在本地
Rendering 边界完成，不暴露原生对象或扩大跨 Runtime 输入。独立 Security Reviewer 确认 P0/P1/P2
0/0/0；Core/Rendering 107 项测试及完整 Gate 已通过，方向适配明确不在本轮范围内。
