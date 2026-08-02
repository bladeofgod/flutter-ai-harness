---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-core
---

# 修正 iOS CapturePlatform 并发协议边界

## 输入与事实来源

- `media-capture-ios-quality-gate` 在 Xcode 26.5、`SWIFT_STRICT_CONCURRENCY=complete` 下的 generic
  iOS Simulator SDK compile 结果。
- `swift-ios-standards` 与 `native-testing-strategy`。
- 生产 `AVFoundationCapturePlatform` 已显式声明 `@unchecked Sendable`，测试实现是 actor，但
  `CapturePlatform` 类型擦除没有保留 Sendable 约束。

## 目标

- 让 Core actor 跨 `await` 持有的 `any CapturePlatform` 保留实现已有的 Sendable 保证。
- 在完整并发检查下消除 CapturePlatform 跨隔离域调用的数据竞争诊断。
- 通过完整 Core/Rendering XCTest 和两个 product 的 generic iOS Simulator SDK compile。

## 非目标

- 不改变 Capture Capability、Wire、Core 公共 API、状态机、权限、媒体文件或渲染语义。
- 不修改 UI、Bridge Adapter、Host、Android、Flutter、共享 Contract、CI 或 Makefile。
- 不用关闭严格并发检查或降低 warning 级别掩盖诊断。

## 实现路径与所有权

本任务只写：

- `app/native/ios/MediaCapture/Sources/MediaCapture/InternalDependencies.swift`
- `app/native/ios/MediaCapture/Sources/MediaCapture/AVFoundationCapturePlatform.swift`
- 必要时 `app/native/ios/MediaCapture/Tests/**`
- 本任务自己的 Review 与 evidence 文件

## 实现与验收要求

1. `CapturePlatform` 内部协议必须继承 `Sendable`；生产与测试 conformer 继续由各自已有隔离机制负责。
2. AVFoundation session queue 的逃逸工作闭包与返回值必须显式满足 `Sendable`，不能把普通闭包跨
   DispatchQueue 隔离域传递。
3. 广播给 continuation 的 operation completion 泛型值必须显式满足 `Sendable`。
4. 不增加新的 `@unchecked Sendable`、锁、Task、依赖或公共符号。
5. `MediaCapture-Package` Simulator XCTest 全部通过。
6. `MediaCapture` 和 `MediaCaptureAppleRendering` 在 generic iOS Simulator SDK 下使用完整严格并发检查，
   warning 作为 error，均成功编译。
7. 独立普通 Review 清零 P0/P1 后归档，再恢复执行 iOS Quality Gate。

## 验证命令

```bash
(cd app/native/ios/MediaCapture && xcodebuild test -scheme MediaCapture-Package -destination '<available iPhone Simulator>' CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES)
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build)
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCaptureAppleRendering -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO SWIFT_STRICT_CONCURRENCY=complete SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build)
make harness-check
git diff --check
```

## 环境限制

该修复只校验 Swift 并发类型边界和 Simulator/generic SDK 构建，不替代真机 Camera、权限、中断或性能验收。

## 执行结果

已完成内部协议、session queue、completion 与测试 helper 的严格并发修正。Core Package 101 个 XCTest、
两个 generic Simulator product build、diff check 和最终 Harness 全部通过；独立普通 Review 最终为
P0 0、P1 0、P2 0。
