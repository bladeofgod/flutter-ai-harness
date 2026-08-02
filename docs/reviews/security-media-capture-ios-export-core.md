---
task: media-capture-ios-export-core
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/ios/MediaCapture/Sources/MediaCapture/AppleMediaStorage.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/InternalDependencies.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureCore.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureModels.swift
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaExportControl.swift
  - docs/infrastructure/media-capture-ios.md
implementationDigest: a31b6321771f2e5e8f123de43d19f96d5a7814c4c5c237380637617afd04b575
---

# Security Review: iOS Media Capture Export Core

## 结论

独立只读 Security Review 通过，P0 0、P1 0、P2 0。审查覆盖 App 私有媒体、opaque lease/handle、
typed sink 信任边界、内存与并发预算、取消/deadline/release/expiry/restart/close、commit 线性化、abort、
脱敏和 SwiftPM 供应链。首轮唯一 P2 是 evidence 命令包含 Simulator UUID；最终证据已按设备名称重录，
命令与输出均通过脱敏检查。

## 已确认控制

- Export 只接受 active confirmed lease、JPEG/MP4 与 `1..52428800` 固定长度；打开 source 和调用 sink
  前完成同 Media 1 job、Module 4 job/1 MiB reservation。
- source read 与 callback chunk 均最多 128 KiB；callback-scoped copy 返回即擦除，长度缩短或增长都会
  失败，不截断、不补齐。
- caller cancel、120 秒 deadline、release、expiry、restart 和 close 共用终态控制。失败 abort once，
  source/chunk/job/deadline 全部收口；成功不会自动释放或刷新 source lease。
- `commit` 正常返回是成功发布线性化点；返回前终态触发失败并 abort，返回后才发生的 release/cancel
  不会把已发布目标改报失败。参数化测试直接覆盖这两个 late window。
- 公共边界只暴露 Sendable `MediaCopySink`、metadata 与 callback-scoped `MediaCopyChunk`，不暴露 Flutter、
  UIKit、AVFoundation、URL、FileHandle、路径或 sink identity；底层异常只映射稳定 Failure ID。
- Package 没有远程依赖，只链接 Apple Framework。同进程 Native sink 必须遵守五秒取消、原子
  commit/abort 契约；不合作 sink 的外部副作用不属于 Core 可撤销边界。

## 验证边界

最终 evidence 记录 Export 专项 16 项；当前完整 scheme 为 Core 93 项、Apple Rendering 6 项、Public
Consumer 2 项，合计 101 项 XCTest，全部通过；generic Simulator Debug、distribution Release、公开接口
扫描和 `make lint` 通过。Simulator/Fake
不能证明真机锁屏文件保护、真实 50 MiB 峰值 RSS/吞吐、POSIX 最坏取消延迟或 Host sink 合规性，这些
留给 iOS Quality Gate 与用户最终真机验收。

本轮 Reviewer 未读取普通 Review 报告，未运行构建或修改实现。

后续镜头切换 correction 只改变共享 Core 的 camera snapshot 提交和基础设施说明，不改变 Export source、
sink、预算、deadline、commit/abort 或 lease 语义。独立 Security Reviewer 对当前共享 Core 快照复审无
finding；本报告摘要已机械更新到当前重叠实现。

后续 cleanup 终态修正只收敛 `releaseMedia` 在 teardown/restart 与永久无效状态下的 Failure 分类；release、
expiry、close 仍会领取 export 终态、取消 worker 并保持既有 abort/commit 规则。独立 Security Reviewer 对
当前共享文件完成影响复核，无新增 finding，本报告绑定更新到当前快照。

后续严格并发 correction 在重叠文件中只为与 Export 无关的内部 `CapturePlatform` 增加 `Sendable` 协议
约束；Export executor、source/sink、预算、deadline、commit/abort 与 lease 语义均未改变。完整严格并发
编译通过，本报告摘要机械更新到当前共享实现快照。
