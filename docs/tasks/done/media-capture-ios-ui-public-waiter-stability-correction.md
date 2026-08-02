---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-ui-lifecycle-sendable-correction
---

# 稳定 iOS UI public waiter 取消回归测试

## 输入与事实来源

- iOS Quality Gate 和连续 UI suite 运行中，`testCancellingPublicResultWaiterCleansUpFlowAndPropagatesCancellation`
  偶发抛出 `InvalidTransition(idle -> failed(deinit))`；单测或只运行同组前两项时通过。
- 测试在 Core cancel/detach/event termination 计数满足后立即 acquire presentation slot，但 slot 还要等待
  dismissal/deferred cleanup hold 收敛，偶发仍处于 poisoned 状态。
- `swift-ios-standards` 与 `native-testing-strategy`。

## 目标

- 让 public waiter cancellation 测试分别等待 Core cleanup 与 presentation slot cleanup，不混淆两个终点。
- 保持生产 `awaitResult()` 的 CancellationError、Session/surface/event cleanup 和 slot release 语义不变。
- 证明完整 51 项 UI suite 连续运行稳定，并恢复 iOS Quality Gate。

## 非目标

- 不改变 Capture flow 产品行为、Capability、Wire、Bridge、Host、Android 或 Flutter。
- 不通过重试失败测试、吞掉非 CancellationError 或扩大等待时间掩盖状态错误。

## 实现路径与所有权

本任务只写：

- `app/native/ios/MediaCaptureUI/Tests/MediaCaptureUITests/MediaCaptureUiPresenterTests.swift`
- 必要时 `app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureFlowCoordinator.swift`
- 本任务自己的 Review 与 evidence 文件

## 实现与验收要求

1. 测试必须继续断言 public result task 抛出 `CancellationError`；其它错误明确失败，不能被 catch-all 吞掉。
2. 测试可以使用确定性 dismissal callback，但必须有界等待 presentation slot 真正恢复，不能在 Core 计数
   达标后立即 acquire。
3. cleanup 仍断言 cancel、live detach、event termination 各一次，且原 owner 的 presentation slot 可重新获取。
4. 完整 UI 51 项 Simulator XCTest 至少连续运行三次全部通过；严格并发 generic build 无并发告警。
5. 独立普通 Review 清零 P0/P1 后归档。

## 验证命令

```bash
(cd app/native/ios/MediaCaptureUI && for run in 1 2 3; do xcodebuild test -scheme MediaCaptureUI -destination '<available iPhone Simulator>' CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete; done)
(cd app/native/ios/MediaCaptureUI && xcodebuild -scheme MediaCaptureUI -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build)
make harness-check
git diff --check
```

## 环境限制

Simulator presentation hierarchy 不替代真机 Scene、Camera、权限或硬件中断验收。

## 执行结果

已拆分 public waiter CancellationError、Core cleanup 与 deferred presentation slot cleanup 的测试等待。
完整 51 项 UI XCTest 连续三轮通过，严格 generic build、diff check 和 Harness 均通过，普通 Review 为
P0 0、P1 0、P2 0。
