---
task: media-capture-ios-camera-switch-correction
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: iOS 镜头切换提交与能力快照修正

## 结论

独立只读 Reviewer 确认代码行为没有新的 P0/P1：平台成功返回后的 capability snapshot 提交、
`sessionReady` 分发、caller cancellation、display rotation、unsupported camera 和 Session 后续可用性均已
闭合。首轮唯一阻断是修复越过 Native UI 任务边界；现已用本 correction 任务独立声明 Core 所有权、测试、
Review 和 Security evidence，不再把 Core 改动静默归入 UI 任务。

## 已确认实现

- AVFoundation 平台成功返回后，Core 将切换视为不可回滚提交点，不再用 caller cancellation 丢弃结果。
- 提交后校验仍要求同一 Session、ready state、operation generation 和 in-flight ownership；terminal、cancel、
  restart 或替代 operation 不能被晚结果覆盖。
- display rotation 只淘汰 Render lifecycle，不会造成物理摄像头与 registry snapshot 分叉。
- 成功提交会发送包含新 flash、focus 和 zoom 能力的 `sessionReady`，原生 UI 可等待该 event 再开放 action。
- 新镜头不支持旧 flash mode 时，Core 同步把当前 photo flash mode 重置为新 snapshot 支持的默认值，后续
  拍照不会携带已经失效的旧镜头配置。

## 验证

[`test-evidence/media-capture-ios-camera-switch-correction.log`](test-evidence/media-capture-ios-camera-switch-correction.log)
记录 `MediaCaptureTests.xctest` 89 个、Apple Rendering 6 个、Public Consumer 2 个 Simulator XCTest，
scheme 合计 97 个测试；Core 与 Apple Rendering generic iOS Simulator Debug build 以及 `make lint` 全部
通过，命令与输出通过脱敏检查。

真机 Camera 权限 UI、实际镜头切换和系统占用时序留给 iOS Quality Gate 与用户最终验收，不计为本任务
P1。
