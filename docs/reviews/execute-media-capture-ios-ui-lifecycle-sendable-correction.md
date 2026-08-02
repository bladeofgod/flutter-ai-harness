---
task: media-capture-ios-ui-lifecycle-sendable-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# iOS UI 生命周期通知并发修正 Review

## 结论

独立普通 Review 通过，P0 0、P1 0、P2 0。首轮唯一 P2 是 action relay 使用了不必要的
`@unchecked Sendable`；最终实现改为编译器验证的普通 `Sendable`，并在该快照上重新运行完整 UI 测试与
严格并发 generic build。

## 实现核对

- NotificationCenter callback 只捕获不可变、编译器验证的 Sendable relay；scene 不跨隔离域发送。
- scene identity 继续由 observer 注册时的 `object:` filter 与 observation `matches` 双重限定。
- background/foreground action 是 `@MainActor @Sendable`，并只在 `.main` notification queue 回调中通过
  `MainActor.assumeIsolated` 调用。
- `invalidate()` 可重复执行，rebind 先解除旧注册，deinit 只做 MainActor 隔离明确的兜底。
- 测试保留错误/正确 scene 与旧/新 scene rebind 断言，并新增 invalidate 后不再触发的断言；测试 helper
  的方法引用也改为显式 Sendable closure，没有弱化时序。

## 验证

脱敏证据位于
[`media-capture-ios-ui-lifecycle-sendable-correction.log`](./test-evidence/media-capture-ios-ui-lifecycle-sendable-correction.log)：

- `MediaCaptureUI` 51 个 Simulator XCTest，0 failure。
- `MediaCaptureUI` generic iOS Simulator SDK Debug build 通过，使用
  `SWIFT_STRICT_CONCURRENCY=complete`，无 Sendable/actor/MainActor/data-race 告警。
- `git diff --check` 通过。
- Native UI 与 SwiftPM Host 既有 Security Review 补充窄影响说明并刷新摘要后，最终
  `make harness-check` 通过。

## 验证边界

Simulator 中人工投递通知不能证明真机 Scene 调度时序，也不证明 Camera、Microphone、系统权限 UI、
硬件中断或性能；这些保留给最终真机验收。
