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
implementationDigest: 749e0b60592f105cd479fd6fb45c267de7ff8bf56cd3b4d8312cad109d2d4cef
---

# Security Review: Media Capture Export Capability V4

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
