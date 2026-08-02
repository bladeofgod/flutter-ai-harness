---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-bridge-presentation-main-actor-correction
---

# 稳定 iOS Transfer Store 启动准备回归测试

## 输入与事实来源

- iOS Quality Gate 完整运行中，`testConstructionSchedulesRestartSweepWithoutReservation` 偶发在残留文件
  已删除后立即读取到 `store.isAvailable == false`。
- `MediaCaptureTransferStore.prepare()` 先执行 sweep，再在锁内发布 `generationOpen` 和 `.ready`；文件删除是
  准备过程中的中间观察点，不是准备完成的同步信号。
- `swift-ios-standards` 与 `native-testing-strategy`。

## 目标

- 让测试等待构造期异步准备的完整终态，同时验证 restart residue 被删除且 Store 可用。
- 保持构造即调度 sweep、无需创建 reservation 触发准备的产品语义。
- 恢复 Bridge Core 完整 Simulator suite 和 iOS Quality Gate 稳定性。

## 非目标

- 不改变 Transfer Store 生产实现、文件安全边界、Wire、Capability、Flutter、Android 或 Host。
- 不使用无界等待、固定长时间 sleep 或跳过断言掩盖准备失败。

## 实现路径与所有权

本任务只写：

- `app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureTransferStoreTests.swift`
- 本任务自己的 Review 与 evidence 文件

## 实现与验收要求

1. 有界轮询必须同时等待 residue 不存在和 `store.isAvailable == true`，不能把 sweep 中间状态当作完成。
2. 不得显式调用 `prepare()` 作为触发条件；测试继续证明构造器会自行调度启动准备。
3. 完整 Bridge Core Simulator XCTest 全部通过；严格并发 generic build 无并发告警。
4. 独立普通 Review 清零 P0/P1 后归档。

## 验证命令

```bash
(cd app/packages/app_media_capture_bridge/ios/app_media_capture_bridge && xcodebuild test -scheme MediaCaptureBridgeCore -destination '<available iPhone Simulator>' CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete)
(cd app/packages/app_media_capture_bridge/ios/app_media_capture_bridge && xcodebuild -scheme MediaCaptureBridgeCore -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build)
make harness-check
git diff --check
```

## 环境限制

Simulator 文件系统测试不替代真机 Camera、权限、硬件中断或性能验收。

## 执行结果

已将 restart residue 删除和 Store ready 发布作为两个必须同时满足的有界等待条件。完整 Bridge Core
69 项 Simulator XCTest、严格并发 generic build、diff check 和 Harness 均通过；独立普通 Review 为
P0 0、P1 0、P2 0。
