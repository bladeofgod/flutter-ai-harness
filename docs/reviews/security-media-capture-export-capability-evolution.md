---
task: media-capture-export-capability-evolution
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/native/contracts/capability.schema.json
  - docs/infrastructure/contracts/media-capture.capability.json
  - docs/infrastructure/media-capture.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: 1a1257c66ac5f8c866e7a7c92b06e925c9840790feb8d9dace0f3594b8607afb
---

# Security Review: Media Capture Export Capability V4

## iOS dismiss 支持状态影响复审

后续 Wire/Harness 变化只提升 Adapter dismissal 的 iOS support；Capability V4 typed sink、buffer、deadline、
commit/abort、路径禁入和 source lease 语义均未变化。独立 Security Reviewer 确认 P0 0、P1 0、P2 0，
摘要已绑定当前共享文件。

## 结论

独立 Security Review 及修复复审通过，当前 `P0=0`、`P1=0`、`P2=0`。V4 export 只允许把 active
confirmed media 通过调用范围内、不可序列化且不可登记的 typed Native sink 进行有界流式复制；路径、
URI、descriptor、平台对象、raw result bytes 和完整媒体内存缓冲均被禁止。

照片与视频的 source type、format ID 和 MIME literal 已分别闭合为
`photo -> image_jpeg -> image/jpeg` 与 `video -> video_mp4 -> video/mp4`。50 MiB source、256 KiB
chunk、每媒体 1 job、每 Module 4 job/1 MiB、120 秒 deadline、5 秒取消收敛、commit/abort 互斥、
late result 丢弃、Failure details 脱敏以及 source lease 不自动释放或延长均由 Profile 和 Validator 固定。

## 修复复审

首轮 P2 指出 V4 降投影的 request、lifecycle rule、state transition、cleanup 和 privacy policy 分支缺少
故障注入。修复后临时 Harness mutant 共覆盖 operation、field、request、result、failure、lifecycle、
transition、resource、ownership、cleanup、privacy、streaming policy 和 history 十三类 V4-only artifact；
每一类都必须命中 `Capability V3 transport projection` 隔离诊断。完整 `make harness-test` 通过。

## 验证缺口

静态 Capability/Harness 不能证明 Android/iOS 实现始终使用 bounded buffer，也不能证明真实文件复制、
不合作 sink、release/expiry/Core close 竞态和平台内存行为。对应证据由后续双端 Core 和质量门禁任务提供。

## 跨 Runtime 集成影响

最终集成通过三端 current/history/failure source 和 bounded transfer vectors 验证既有 V4 能力，没有改变
Native sink 或 Core ownership。独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。

## iOS 综合修正后的复审

独立 Security Reviewer 复核共享 Gate、golden、Core、Rendering、UI 与文档增量后，确认本轮没有修改
Capability/Wire 结构、export ownership、权限或 Agent 能力。最终结论为 P0/P1/P2 0/0/0，本报告按当前
实现文件重新绑定摘要；方向适配明确不在本轮范围内。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。
