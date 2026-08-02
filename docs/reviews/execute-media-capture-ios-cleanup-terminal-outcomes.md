---
task: media-capture-ios-cleanup-terminal-outcomes
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: iOS Media Cleanup 永久终态

## 结论

独立普通复审通过，P0 0、P1 0、P2 0，当前快照可以归档。首轮指出的安全/门禁、discarded 与非类型错误
覆盖以及文档状态问题均已关闭。

## 已确认实现

- Core 对 closed、discarded、expiry grace、expired 和失效 handle 返回永久 `media_invalid`；只有 active
  teardown/restart 返回可重试的 `invalid_state`。
- Cleanup owner 只重试 `invalid_state`；其它类型化 Failure 与非类型错误停止任务并释放 deferred hold。
- UI 在初次 release 和 adopted retry 两个阶段都遵守同一 allowlist，slot 在 cleanup 未完成时保持 poisoned，
  收敛后恰好释放一次。
- 未新增 Capability/Wire Failure，也未修改 Flutter、Host、Android 或业务 Feature。

## 验证

最终 evidence 记录 MediaCapture scheme 101 项、MediaCaptureUI 51 项 Simulator XCTest，均 0 失败；三条
generic build、lint、`make harness-check` 和 `git diff --check` 均通过。独立 Security Review 为 P0/P1/P2
全零，四份受共享实现影响的旧安全报告已按独立影响复核刷新。

真机权限、系统中断、文件保护与性能验证仍归 iOS Quality Gate，不阻断本任务归档。
