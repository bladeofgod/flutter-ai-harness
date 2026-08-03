---
task: media-capture-native-ui-flow-wire-evolution
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
implementationDigest: 7ba96668bfc86b7a8629971de2a4138943b68a956077947f1f991fc1e053b8d5
---

# Security Review: Media Capture Native UI Flow Wire V2

## iOS dismiss 支持状态影响复审

后续 Wire V3 仅把 `dismiss_capture_flow` 的 iOS support 提升为 `supported`，没有改变本报告审查的
presentation payload、owner correlation、exactly-once、lease settlement、Native-only Render、thumbnail
或 redaction 边界。反向 mutation 继续拒绝支持矩阵回退；独立 Security Reviewer 复审为 P0 0、P1 0、
P2 0，摘要已绑定当前共享文件。

## 结论

独立 Security Review 通过，P0 0、P1 0、P2 1。审查覆盖 Flutter/Native 信任边界、UI owner 与
generation、presentation 并发和 exactly-once completion、late result、lease adoption/settlement、
Native-only Render attachment、缩略图 bytes/metadata、错误与日志脱敏、双平台一致性和 Harness 负例。

Wire V2 没有传输原始媒体、路径、URI、文件描述符、RenderTarget、owner generation 或平台 SDK 对象；
confirmed lease 在完成前登记，failure/presentation-failed 的未交付 lease 在 slot release 前清理。缩略图
固定受限 JPEG bytes、active lease、尺寸/字节上限、upright orientation、EXIF/source metadata 清理且无
路径 fallback。没有新增依赖、网络访问、CI 权限或 Agent 能力。

## P2

### Native Render 编码入口缺少直接失败 Fixture

当前 Validator 已用精确集合拒绝 `render_target_adapter`、`owner_generation`、Native attachment payload/
event 和 attach method 进入 Channel；Profile/coverage 也保持 `native_consumer_only` 与 `wireId: null`。
但是现有负例主要修改 coverage disposition 或删除 coverage 条目，没有直接把禁用项插入
`fieldMappings`、`payloads`、`methods` 或 `events`。

这不是当前数据泄漏；风险是未来重构精确集合校验时，测试不一定直接捕获 Native 资源进入 Channel 的
回归。后续应分别增加禁用 field mapping、payload/event、attach method 的失败 Fixture，并可补缩略图
尺寸上限漂移负例。

## 普通 Review P2

共同 machine 最终 action ID 的 `exactly_once_success_completion` 命名不准确，但 failure 已被机器化固定为
`delivery: error`、空 resultType/payload，不会因名称变成成功结果，因此不构成安全问题。Adapter 实现前
宜改为中性命名。

## 当前实现复审

独立只读复审重新检查 Wire Schema/Profile、Native UI 三终态、owner generation、presentation 并发、
lease settlement、Native-only Render attachment、缩略图边界及错误脱敏。当前实现未发现 P0、P1 或
P2，摘要可同步到当前文件集合。静态契约不能替代 Android/iOS 实际 present 行为验证，该缺口继续由
平台集成任务负责。

## V4 Harness 最终复审

独立安全复审确认 V4 export 仍不会进入 Wire V2/V3，十三类 projection mutant 全部通过。当前实现
`P0=0`、`P1=0`、`P2=0`；摘要已绑定最终共享 Harness。

## 跨 Runtime 集成影响

最终集成只补充 V4/V3 golden 全量消费、consumer 摘要绑定和文档计数校验，没有放宽 Native UI 三终态、
owner、lease、locator 或 Native-only 边界。独立安全复审为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。
