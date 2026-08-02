---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-native-ui
---

# 修正 iOS UI 生命周期通知并发边界

## 输入与事实来源

- `media-capture-ios-quality-gate` 在 Xcode 26.5、`SWIFT_STRICT_CONCURRENCY=complete` 下的 UI generic
  Simulator SDK compile 结果。
- `swift-ios-standards` 与 `native-testing-strategy`。
- `NotificationCenter.addObserver` 回调是 Sendable 边界，现有实现捕获了 `AnyObject?` scene 和未声明
  Sendable 的 MainActor action；MainActor class 的非隔离 `deinit` 直接访问 Objective-C observer tokens。

## 目标

- NotificationCenter 回调只捕获显式 Sendable 的 MainActor action relay，不跨隔离域发送 scene 对象。
- Observer token 的注册、替换和解除保持明确 MainActor 所有权，重复清理安全。
- 保持 scene object identity filter、UIApplication fallback、rebind、background/foreground 行为不变。
- 在完整严格并发检查下消除 UI lifecycle observation 诊断。

## 非目标

- 不改变 Capture flow、UI 布局、手势、权限、render attachment、Capability、Wire 或 Host。
- 不修改 Core、Bridge Adapter、Android、Flutter、共享 Contract、CI 或 Makefile。
- 不使用 `@preconcurrency import` 或关闭并发检查掩盖告警。

## 实现路径与所有权

本任务只写：

- `app/native/ios/MediaCaptureUI/Sources/MediaCaptureUI/MediaCaptureViewController.swift`
- `app/native/ios/MediaCaptureUI/Tests/MediaCaptureUITests/**`
- 本任务自己的 Review 与 evidence 文件

## 实现与验收要求

1. scene identity 继续由 NotificationCenter 的 `object:` filter 和 observation 的 `matches` 保证；Sendable
   callback 不得捕获 `AnyObject?` scene。
2. background/foreground action 必须声明 `@MainActor @Sendable`，并由只捕获 Sendable 值的通知回调在
   main queue 上调用。
3. Observation 提供可重复 `invalidate()`；rebind 在替换前解除旧 observer，deinit 只做隔离明确的兜底。
4. 测试覆盖错误 scene 不触发、正确 scene 触发、rebind 后旧 scene 不触发、新 scene 触发、invalidate 后
   不再触发。
5. UI 51 个 Simulator XCTest 和 `MediaCaptureUI` generic Simulator SDK build 在完整严格并发检查下通过，
   并由独立普通 Review 清零 P0/P1。

## 验证命令

```bash
(cd app/native/ios/MediaCaptureUI && xcodebuild test -scheme MediaCaptureUI -destination '<available iPhone Simulator>' CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete)
(cd app/native/ios/MediaCaptureUI && xcodebuild -scheme MediaCaptureUI -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete build)
make harness-check
git diff --check
```

## 环境限制

Simulator 生命周期通知测试不替代真机 Camera、权限、系统中断或 Scene 调度时序验收。

## 执行结果

已完成 NotificationCenter Sendable relay、observer 明确清理与严格并发测试 helper 修正。最终 UI 51 个
XCTest、generic Simulator SDK build、diff check 和 Harness 全部通过；独立普通 Review 的唯一 P2 已按
建议改为编译器验证的普通 `Sendable`，最终 P0/P1/P2 均为 0。
