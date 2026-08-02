---
task: media-capture-ios-capture-platform-sendable-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# iOS CapturePlatform 严格并发修正 Review

## 结论

独立普通 Review 与修复后复审通过，P0 0、P1 0、P2 0。修正把实现已有的并发隔离保证准确表达在内部
类型边界，不改变 Capability、Wire、公共 API、资源所有权或运行状态机。

## 实现核对

- `CapturePlatform` 继承 `Sendable`；生产 AVFoundation 实现继续使用既有受控队列和
  `@unchecked Sendable`，测试实现继续由 actor 隔离。
- session queue 的逃逸闭包和泛型返回值显式满足 `Sendable`；operation completion 与 awaiter 只接收
  `Sendable` 值。
- 严格并发编译发现的测试 helper 问题通过显式 `@Sendable` 闭包、同步锁函数和 MainActor 内按需缓存修正，
  没有改变测试时序或断言。
- 没有新增 `@unchecked Sendable`、锁、Task、依赖、日志或公共符号。

## 验证

脱敏证据位于
[`media-capture-ios-capture-platform-sendable-correction.log`](./test-evidence/media-capture-ios-capture-platform-sendable-correction.log)：

- `MediaCapture-Package`：Core 93、Apple Rendering 6、Public Consumer 2，共 101 个 XCTest，0 failure。
- `MediaCapture` 与 `MediaCaptureAppleRendering`：generic iOS Simulator SDK Debug build 均通过，使用
  `SWIFT_STRICT_CONCURRENCY=complete` 和 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`。
- `git diff --check` 通过。
- 首次 `make harness-check` 发现三份既有 Security Review 摘要因共享文件变化失效；三份报告补充窄影响
  说明并刷新摘要后，最终 Harness 通过。Reviewer 复审确认该 P1 已关闭。

## 验证边界

Simulator/Fake 与 generic SDK compile 不证明真机 Camera、Microphone、系统权限 UI、硬件中断或性能；
这些继续由 iOS Quality Gate 文档和最终人工真机验收负责。
