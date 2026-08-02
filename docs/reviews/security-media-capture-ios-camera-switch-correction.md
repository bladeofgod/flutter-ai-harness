---
task: media-capture-ios-camera-switch-correction
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureCore.swift
  - docs/infrastructure/media-capture-ios.md
implementationDigest: cc2acd1d8a9798c7dc6645b617386467d645e0fe29e43cb65e99375335f1e5f6
---

# Security Review: iOS 镜头切换提交与能力快照修正

## 结论

独立只读 Security Reviewer 对最终 Core/UI 交互快照复审通过，P0 0、P1 0、P2 0。修正没有增加新的权限、
媒体数据、路径、日志、公共类型或供应链边界。

## 已确认控制

- Camera/Microphone 的请求时机不变；镜头切换只操作已有 active Session。
- 平台切换成功后，新 snapshot 先经过公共模型校验，再由同一 Session operation ownership 提交并发送
  `sessionReady`。
- caller cancellation 与纯 Render lifecycle 不能回滚物理提交；Session terminal、cancel、restart 或
  generation 替代仍阻止晚结果写回。
- 新 snapshot 不支持旧 flash mode 时，内部当前值重置为受支持默认值，后续 photo capture 不会把旧镜头
  配置继续传给平台边界。
- 公开事件只包含类型化 handle 与 capability，不包含路径、原始媒体、AVFoundation 对象或底层错误文本。

## 验证边界

当前完整 evidence 记录 Core 93 个、Apple Rendering 6 个、Public Consumer 2 个 Simulator XCTest，scheme
合计 101 个测试；两条 generic iOS Simulator Debug build 和 `make lint` 通过。后续 cleanup 终态修正不改变
镜头提交、generation、snapshot 或脱敏边界，独立 Security Reviewer 已确认本结论继续成立。
Simulator/Fake 不证明真机权限 UI、硬件镜头切换或系统中断，这些保留给 iOS Quality Gate。

本轮 Reviewer 未读取普通 Review，未运行构建或修改实现；摘要由主流程按其确认的实现文件计算。
