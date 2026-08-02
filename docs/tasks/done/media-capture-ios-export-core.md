---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-export-capability-evolution
  - media-capture-ios-core
securityReview: required
---

# 实现 iOS Media Capture 流式媒体导出

## 输入与事实来源

- Capability V4 bounded sink export、50 MiB 上限、256 KiB buffer 与 source lease 竞态。
- 已完成的 iOS Media Capture Core/Swift Package、App private media 和 callback-scoped read。
- 执行时发现既有净化视频仍输出 `video/quicktime`，与 V4 闭合的 `video/mp4` source format 不一致；本任务
  必须先把净化容器和 metadata 对齐为 MP4，不能只改 MIME 文案。
- Swift/iOS 生产规范和 Native Testing Strategy。

## 目标

- 在 transport-neutral Swift Core 实现 confirmed media 到 consumer sink 的有界流式复制。
- 用 actor/Sendable API 固定 job、取消、commit/abort 和 release/expiry 线性化。
- 保持 Native Consumer 可直接使用，不 import Flutter、UIKit 或 Wire Dictionary。

## 非目标

- 不创建 Bridge cache/file URL/export handle，不修改 Adapter、Runner、Info.plist、Flutter 或 Android。
- 不自动 release source；除上述净化视频 MP4 契约对齐外，不改变 capture/preview/thumbnail 和权限行为。
- 不把 URL、FileHandle、Data 全量副本或 AVFoundation 类型暴露在 Core 公共 API。

## 实现要求

1. 定义 Sendable、类型化 `MediaCopySink` 协议和 export result/failure；公共 API只含 bounded chunk value
   与稳定 metadata，不出现路径、URL、FileHandle、Flutter 类型或自由 Dictionary。
2. actor 只允许 active confirmed lease并原子登记 export job；每个 media 最多 1 个、Module 最多 4 个
   active job、总 working buffer 最大 1 MiB。验证 MIME/长度/上限，冲突和 overload 使用 Capability
   固定 Failure，容量拒绝不得调用 sink。
3. 在注入执行域用最大 262,144 byte buffer 顺序读取；禁止 `Data(contentsOf:)`/全量媒体分配。累计长度、
   EOF 和 source metadata 必须一致。
4. 从 reservation 起使用注入 Clock 执行 120 秒 deadline。成功 commit sink 后完成；throw/cancel/timeout/
   release/expiry/Core close/length drift 时 abort once，清理 buffer和 job。continuation/Task 不能双
   resume，CancellationError 按契约传播/映射，晚到不合作 sink 结果不得 commit。
5. export 不刷新或自动释放 source lease。日志和 error description 不包含 handle、路径、URL、文件名、
   内容、摘要或底层 Cocoa error。
6. 更新 iOS 基础能力详情；共享 Capability/Wire 由契约任务独占。

## 测试与验收

- Swift tests 覆盖 JPEG/MP4、边界/超限/截断/增长、完整 Failure taxonomy、4-job/1-MiB 预算、sink
  failure、never-returning cancellable sink、120 秒 deadline、cancel、release/expiry/Core close、并发和
  exactly-once。
- 大于多 chunk 的生成 Fixture 证明 peak buffer <= 256 KiB、顺序/长度一致且无全量 Data 分配。
- generic iOS Simulator SDK compile 通过，Core public symbol scan 不含 Flutter/UIKit/URL/FileHandle。

```bash
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
# 存在 available Simulator 时，以实际 ID 执行：
(cd app/native/ios/MediaCapture && xcodebuild test -scheme MediaCapture -destination 'platform=iOS Simulator,id=<available-simulator-id>' CODE_SIGNING_ALLOWED=NO)
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode。无 booted Simulator 时仍须完成 generic compile并记录运行测试缺口；存在 available
Simulator 时 `xcodebuild test` mandatory。真实文件性能和 Camera 流程留给最终集成，不以 host
`swift test` 替代 iOS SDK 证据。
