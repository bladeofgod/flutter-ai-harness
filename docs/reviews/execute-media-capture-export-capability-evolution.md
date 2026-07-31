---
task: media-capture-export-capability-evolution
status: passed
p0: 0
p1: 0
---

# Review: Media Capture Export Capability V4

## 结论

首轮独立 Review 未通过，P0 0、P1 1、P2 1。V4 的 typed sink、资源预算、deadline、取消、Failure、
lease 和清理主体结构已经闭合，完整 Harness 失败 Fixture 通过；但 export 的实际 MIME literal 仍未成为
机器契约，历史投影缺少针对 V4 泄漏的失败 Fixture。

## P1

### Export content type 没有闭合到媒体类型映射

Profile 的共享 `content_type` 字段仍是开放 `mime_type`；V4 export precondition 只引用内部格式 ID
`image_jpeg` / `video_mp4`，没有机器可读地固定 `photo -> image/jpeg`、`video -> video/mp4`。Android/iOS
实现和后续 Wire 仍可能对返回值作不同解释。

修复要求：在通用 Schema 可表达的 Profile 级 streaming-copy source type 结构中增加媒体类型、格式 ID 与
literal content type 的闭合映射；Media Capture Profile 精确声明两项，Harness 和失败 Fixture 拒绝 MIME
漂移、缺项和额外项。

## P2

### V4 到旧版本的降投影缺少泄漏负例

Harness 已实现 V4 -> V3 -> V2 正向投影，但失败 Fixture 没有证明 export operation、sink field、result、
failure、job/buffer、streaming copy policy 或 V4 history 泄漏到 V3/V2 时会被拒绝。

修复要求：增加有针对性的 projection mutation Fixture，至少覆盖各类 V4-only artifact 与 history；不能
只依赖最终 Wire shape digest 偶然失败。

## 已确认项

- Sink 为调用范围内 Native-only typed capability，不可序列化或登记进 Module Registry。
- 50 MiB source、256 KiB chunk、每 media 1 job、每 Module 4 job/1 MiB 和 120 秒 deadline 已机器化。
- begin/write/commit/abort 顺序、commit xor abort、5 秒取消收敛、late result 丢弃和清理顺序闭合。
- 8 个 direct non-terminal export Failure 与复用 Failure 的 race winner、sink action、lease effect 闭合。
- source lease 不自动 release、延长 TTL/grace 或改变 tombstone。
- `make harness-test`、`make lint` 与 `git diff --check` 已有通过证据；最终 Harness 只剩共享安全摘要漂移。

## 修复复审

独立 Reviewer 复审通过，当前 `P0=0`、`P1=0`、`P2=0`。

- Schema、Profile 与 Validator 现已通过 `sourceRepresentations` 精确闭合
  `photo -> image_jpeg -> image/jpeg` 和 `video -> video_mp4 -> video/mp4`；失败 Fixture 覆盖 MIME
  漂移、缺项和额外项。
- V3 projection 在交给 Wire Validator 前增加独立隔离校验，精确拒绝 V4 operation、sink/request
  field、result、failure、resource、ownership、cleanup/privacy、streaming policy 和 history 残留。
- 失败 Fixture 使用临时 Harness mutant，分别禁用 operation、field、request、result、failure、
  lifecycle、transition、resource、ownership、cleanup、privacy、streaming policy 和 history 共十三类
  V4 清理规则并确认投影门禁拒绝，不依赖最终 Wire shape digest 偶然报错。
- `make harness-test`、`make format`、`make lint` 与 `git diff --check` 通过；`make harness-check`
  在同步既有 Security Review 摘要前只报告摘要漂移。
