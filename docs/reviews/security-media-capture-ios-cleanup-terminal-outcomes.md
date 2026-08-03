---
task: media-capture-ios-cleanup-terminal-outcomes
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureCore.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureLeaseCleanupOwner.swift
  - app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureFlowCoordinator.swift
  - docs/infrastructure/media-capture-ios.md
  - docs/native/media-capture-ios-ui.md
implementationDigest: d6fca7b53f3a6ba7cb3d257f8e7e95581741b00ea503d718af9aab10afb9b871
---

# Security Review: iOS Media Cleanup 永久终态

## 结论

独立只读 Security Review 通过，P0 0、P1 0、P2 0。修正关闭了 late confirmed lease 在永久无效状态下
无限重试并长期持有 Core、handle、Task 与 presentation slot 的路径，没有引入新的权限、媒体数据、路径、
日志、公共类型或供应链边界。

## 已确认控制

- `releaseMedia` 对 closed Core、未知 handle、discarded、expiry grace 和 expired media 返回
  `media_invalid`；只有 active teardown 或 restart 返回可重试的 `invalid_state`。
- restart 在清理前把资源置为 terminal，并在重新 idle 前清空 registry；close 立即关闭 Core，因此 retry
  只能等待真实 teardown，随后稳定收敛为成功或永久终态。
- cleanup owner 只重试 `invalid_state`；其它类型化 Failure 和非类型错误都会停止任务并释放 deferred hold。
- deferred hold 在 cleanup 阻塞或可重试时保持 slot poisoned，永久终态后由 MainActor gate 恰好释放一次。
- 变更不记录或返回 media bytes、path、URL、FileHandle、底层 error text 或 opaque handle 值。

## 既有报告影响

独立 Reviewer 确认 camera switch、export Core 与 Core 总体安全结论继续成立，只需按原文件集合刷新摘要；
Native UI 报告的唯一 P2 已由本任务关闭。四份报告均保持原 implementation file 边界，并更新到当前测试
计数和摘要。

## 验证边界

当前 Simulator evidence 为 MediaCapture scheme 101 项和 MediaCaptureUI 51 项 XCTest，均 0 失败；generic
build、lint、harness-check 与 diff check 由任务最终 evidence 记录。Simulator/Fake 不替代真机权限、系统
中断、文件保护与性能验证，这些保留给 iOS Quality Gate 和用户最终真机验收。

本轮 Security Reviewer 未读取普通 Review，未运行构建或修改实现。

## iOS 综合修正后的影响复审

retake 现在以 discarded/ready 状态提交为线性化点，再执行异步文件删除；删除期间旧 media 不可 confirm，
新 capture 使用不同 handle，不会保留指向已删除文件的有效 preview。既有 cleanup terminal outcome、deferred
hold 和 release 语义未放宽。独立 Security Reviewer 确认 P0/P1/P2 0/0/0，并允许按当前文件刷新摘要。
