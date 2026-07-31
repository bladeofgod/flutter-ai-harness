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
implementationDigest: 186d6847ec6b845194ce51343cdd4ffa5c3bee23969c246968e8cc4c4d69f986
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

## 验证缺口

iOS Simulator SDK `swift build --build-tests` 已编译全部 product/test target，仓库 lint/harness/diff 通过。
两条 mandatory generic Simulator `xcodebuild` 因本机缺少 iOS 26.5 platform component 退出 70，因此 iOS
Core 仍不能归档。Simulator/Fake 也不证明真机权限 UI、中断、编码性能或内存峰值。
