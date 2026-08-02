---
task: media-capture-bridge-contract
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/bridge/contracts/wire.schema.json
  - docs/bridge/contracts/media-capture.wire.json
  - docs/bridge/media-capture.md
  - docs/bridge/README.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: 27c2a069b085b0c2dea019bfd63ba54d3620d4572734a8274b470c624756bcad
---

# Security Review：Media Capture Bridge Contract

## iOS dismiss 支持状态影响复审

后续变更只把既有、闭合的 `dismiss_capture_flow` iOS support 提升为 `supported`。method kind、Channel、
originating `presentationRequestId` payload、协议错误集合、exactly-once、lifecycle、错误 details 与日志脱敏
均未放宽。独立 Security Reviewer 确认 P0 0、P1 0、P2 0，摘要已绑定当前共享文件。

## 结论

最终 Security Review 通过，P0 0、P1 0、P2 0。审查覆盖 Channel 外部输入、协议版本、错误泄漏、
资源耗尽、opaque handle、Engine/UI 生命周期、跨线程 callback、资源 adoption 与 Capability 边界。

## 发现与修复

### 1. 错误 details 可能回显不可信输入

首轮只约束 details key，无法阻止 Adapter 回显未知字段、Payload、底层异常或路径。修复后 8 个
detail 字段分别声明 Wire 类型、固定来源、闭合枚举、长度/范围与 redaction；未知 operation/field
只返回固定哨兵，版本限定 signed-64，静态 message 不包含原始异常或用户内容。

### 2. 成功 completion 与资源登记存在 detach 竞态

复审发现 Native 成功、Flutter completion、资源登记与 boundary 扫描若不线性化，可能遗留相机
Session 或 24 小时媒体 lease。最终 Profile 要求 `session_created` 与 `confirmed_media` 在同一
coordinator 内先登记资源再成功完成 Flutter。Engine/UI boundary 先赢时，返回资源先通过既有
`system_interrupted` 或 `release_media` 清理，再丢弃 callback，且不二次完成 Flutter。

## 已确认边界

- Envelope、Payload、finite/enum、handle 长度、requestId pattern 和 signed-64 均在调用 Capability 前校验。
- pending 与 completed 去重表有固定容量；完成墓碑槽在调用 Capability 前预留，且不会提前逐出。
- 第二 listener 不替换旧 sink；generation 隔离 late event，编码失败行为跨平台一致。
- Engine detach 释放 attachment Session/lease；UI owner destroy 保留已交付 lease、释放未交付的晚到 lease。
- `open_media_read` 不进入 Channel；媒体 bytes、路径、任意 URI、自由 Map 和原生 SDK 对象均被禁止。
- Task 2 的任务入口/只读 Reviewer 边界与 Task 3 的输入、handle、路径和 read-grace 约束未回归。

## 验证

[测试证据](test-evidence/media-capture-bridge-contract.log) 包含完整失败 Fixture 和最终验证输出。
最终独立复审基于当前实现与证据完成，剩余风险仅是后续真实 Adapter 仍需并发竞态运行测试。

Thumbnail Capability V2 后续扩展了共享 Validator 与 Fixture。对应最终独立 Security Review
重新核对 Wire V1 projection、signed-64 输入、opaque handle、typed error details、共同 lifecycle
coordinator、resource adoption、exactly-once completion 和 late cleanup，确认没有回归；本报告摘要
同步到当前实现。

## 当前实现复审

独立只读复审重新检查 Method/EventChannel 类型边界、requestId 去重、错误 details、生命周期、资源
adoption 和版本兼容，确认原始路径、URI、媒体 bytes 与 SDK 对象仍被拦截。当前实现未发现 P0、P1
或 P2，摘要可同步到当前文件集合。尚未执行 Adapter 或跨 Runtime 行为验证。

## V4 Harness 最终复审

独立安全复审确认 typed Native sink、export operation/result/failure/resource 和 source MIME mapping 均未
进入既有 Wire。十三类 projection mutant 全部通过，当前实现 `P0=0`、`P1=0`、`P2=0`；摘要已绑定
最终共享 Harness。

## 跨 Runtime 集成影响

最终集成补齐 current/history/failure source、MIME、signed-64、URI、lifecycle 与 redaction 的三端消费，
未放宽 Bridge Contract。独立安全复审为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。
