---
task: media-capture-ios-ui-public-waiter-stability-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# iOS UI public waiter 稳定性修正 Review

## 结论

普通 Review 通过，P0 0、P1 0、P2 0。修复只改变测试对多个 cleanup 终点的等待方式，生产
`MediaCaptureFlowCoordinator`、公开 API 和运行语义未修改。

## 根因与修复

- public waiter 取消后，result task 先以 `CancellationError` 返回；Core cancel、surface detach、event
  termination 与 presentation slot release 是相关但不同的收敛终点。
- 原测试在前三个 Core 计数满足后立即 acquire slot，偶发仍处于 deferred dismissal hold，抛出
  `presentationConflict`。未捕获的 async test error 被 XCTest 显示为误导性的
  `InvalidTransition(idle -> failed(deinit))`。
- 最终测试用非 throwing child Task 把 public waiter 结果封装为 `Result`，精确断言错误是
  `CancellationError`；setup/present 都显式报告阶段错误。
- Core cleanup 计数达标后，再通过有界 `presenterEventually` 等待 slot 真正恢复并完成 acquire/release。
  测试继续使用确定性 dismissal completion，不依赖 Simulator UIKit 动画完成时序。

## 验证

脱敏证据位于
[`media-capture-ios-ui-public-waiter-stability-correction.log`](./test-evidence/media-capture-ios-ui-public-waiter-stability-correction.log)：

- 完整 `MediaCaptureUI` 51 项 Simulator XCTest 连续运行三次，全部通过。
- `MediaCaptureUI` generic Simulator SDK Debug build 在完整严格并发检查下通过。
- `git diff --check` 通过。
- SwiftPM Host 架构报告同步新增 Gate 依赖摘要后，最终 `make harness-check` 通过。

## 验证边界

本测试证明 cancellation 与 deferred slot cleanup 的顺序，不替代真机 UIKit Scene、Camera、权限或硬件中断
验收。
