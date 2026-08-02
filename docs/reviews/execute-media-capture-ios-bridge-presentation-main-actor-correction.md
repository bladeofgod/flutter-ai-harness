---
task: media-capture-ios-bridge-presentation-main-actor-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# iOS Bridge Presentation MainActor 修正 Review

## 结论

普通 Review 通过，P0 0、P1 0、P2 0。改动只使 Controller 私有 presentation 状态的既有 MainActor
所有权在类型系统中显式化，不改变 Wire、Channel、资源生命周期或 completion 行为。

## 实现核对

- `ActivePresentation` 显式标记 `@MainActor`；session、dismiss flag、settlement state 与 continuation
  继续只由 MainActor Controller 访问。
- 没有增加 `@unchecked Sendable`、锁、Task 或非隔离逃逸。
- unknown/already-ended dismiss 幂等、dismiss-wins、owner destroy、Engine detach、late lease cleanup 与
  cleanup poisoning 的调用路径未改变。
- Permission Fake 的锁操作封装为同步函数，消除 async context 直接 lock/unlock 告警。
- TTL 测试把 deadline 调为 300ms、Flutter callback 阻塞调为 800ms，并在 callback 返回后只等待最多
  150ms；若 deadline 错误地从 callback 返回后开始，测试仍会失败，因此证明语义没有弱化。

## 验证

脱敏证据位于
[`media-capture-ios-bridge-presentation-main-actor-correction.log`](./test-evidence/media-capture-ios-bridge-presentation-main-actor-correction.log)：

- Bridge Core 69 个 Simulator XCTest，0 failure。
- `MediaCaptureBridgeCore` generic iOS Simulator SDK Debug build 使用完整严格并发检查并通过，无
  Sendable/actor/MainActor/data-race 告警。
- `git diff --check` 通过。
- Base/Export Bridge 与 SwiftPM Host 既有 Security Review 补充窄影响说明并刷新摘要后，最终
  `make harness-check` 通过。

## 验证边界

Bridge Core Fake/Simulator 不替代 Flutter Plugin Host、真实 Runner 或真机 Camera、权限和硬件中断验收。
