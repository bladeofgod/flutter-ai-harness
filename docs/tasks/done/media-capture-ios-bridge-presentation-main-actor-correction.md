---
executor: ios-engineer
platforms: [ios]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-ios-export-bridge-adapter
---

# 修正 iOS Bridge Presentation MainActor 隔离

## 输入与事实来源

- `media-capture-ios-quality-gate` 在 Xcode 26.5、`SWIFT_STRICT_CONCURRENCY=complete` 下的
  `MediaCaptureBridgeCore` generic Simulator SDK compile 结果。
- `swift-ios-standards` 与 `native-testing-strategy`。
- `MediaCaptureBridgeController` 是 MainActor 类型，但其嵌套 `ActivePresentation` 没有显式继承外层隔离，
  调用 `async waitUntilSettled()` 时引用被视为发送到非隔离 executor。

## 目标

- `ActivePresentation` 的 session、dismiss flag、settlement 状态与 continuation 全部显式归 MainActor。
- dismiss、owner destroy、Engine detach 与 presentation settle 的既有顺序和 exactly-once 语义不变。
- 在完整严格并发检查下消除 Bridge Core presentation send 诊断。

## 非目标

- 不改变 Wire、Channel method/event/error、Core/UI 公共 API、transfer store、Host 或 Flutter。
- 不修改 Android、共享 Contract、CI 或 Makefile。
- 不增加 `@unchecked Sendable`、锁、Task 或非隔离逃逸。

## 实现路径与所有权

本任务只写：

- `app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeController.swift`
- 必要时 `app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/**`
- 本任务自己的 Review 与 evidence 文件

## 实现与验收要求

1. `ActivePresentation` 必须显式使用 MainActor 隔离；所有现有调用点继续由 MainActor Controller 拥有。
2. 不改变 unknown/already-ended dismiss 幂等、dismiss-wins、late confirmed lease release、owner/Engine cleanup
   和 presentation cleanup poisoning。
3. Bridge Core 69 个 Simulator XCTest 全部通过。
4. `MediaCaptureBridgeCore` generic Simulator SDK build 使用完整严格并发检查，无 Sendable/actor/MainActor/
   data-race 告警。
5. 独立普通 Review 清零 P0/P1 后归档并恢复 iOS Quality Gate。

## 验证命令

```bash
bash app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh
(cd app/packages/app_media_capture_bridge/ios/app_media_capture_bridge && xcodebuild -scheme MediaCaptureBridgeCore -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build)
make harness-check
git diff --check
```

## 环境限制

Bridge Core Fake/Simulator 不替代临时 Flutter Host、真实 Runner 或真机 Camera/权限验收。

## 执行结果

已完成私有 presentation MainActor 隔离及严格并发测试 helper 修正。最终 69 个 Bridge Core XCTest、
generic Simulator SDK build、diff check 和 Harness 全部通过，普通 Review 为 P0 0、P1 0、P2 0。
