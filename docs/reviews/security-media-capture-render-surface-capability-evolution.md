---
task: media-capture-render-surface-capability-evolution
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
implementationDigest: cd029d43af8db65ba19c2998a4faf775695b5e9dc0e15a917fd108f50498d50d
---

# Security Review: Media Capture Render Surface Capability V3

## iOS dismiss 支持状态影响复审

后续 Wire V3 只提升 Adapter dismissal 的 iOS support，并同步共享 Validator/Harness；Capability V3 的
surface factory、closed conformance、module-only target/source/binding、mutation gate 和日志脱敏规则均未
变化。独立 Security Reviewer 确认 P0 0、P1 0、P2 0，摘要已绑定当前共享文件。

## 首轮结论

独立 Security Review 未通过，P0 0、P1 1、P2 1。Factory output、closed conformance、module-only mount
endpoint、双平台组成、mutation gate、stale callback、replacement/revoke 和 V1/V2 安全语义已有确定性
校验；仍需关闭重复键覆盖绕过和 Render Surface 日志脱敏缺口。

## P1

### 重复 policy ID 或平台声明可绕过安全快照

资产包括 module-only backing target、source、renderer、binding、mount endpoint 和 Native-only surface。
仓库贡献者可插入同 `renderSurfacePolicy.id` 的不同对象，或在一个 policy 中插入第二个相同 platform 的
implementation。Schema `uniqueItems` 只拒绝完全相同对象；Validator 写 Map/Set 时未拒绝重复 key，后面的
正确条目可能覆盖前面的 `AnyObject`、arbitrary target 或额外 source 声明。

影响是契约可同时含安全和不安全并行定义，不同平台实现选择不同条目，导致任意 UI/SDK target 或
不受限 source 进入渲染路径。

修复要求：写入 Map 前显式拒绝重复 surface policy ID、重复 platform，并保证 attachment 绑定的 policy
ID 唯一。增加安全条目前置/后置恶意重复 policy 与 platform implementation 的失败 Fixture。

## P2

### Render Surface 诊断数据缺少明确日志脱敏规则

新策略将 surface/target identity、owner generation、source、renderer、binding 和底层对象定义为
Module-private，但现有 `redact_logs` 主要覆盖 handle、path、bytes 与 metadata。实现者可能在 stale、
mount/revoke failure 或平台异常中记录实例描述、generation、SDK 对象或原始异常。

修复要求：增加结构化 Render Surface 日志策略，只允许稳定枚举/脱敏状态，明确禁止实例描述、owner
generation、target/source/renderer/binding、路径、SDK 对象和原始异常；增加缺失或放宽策略负例。

## Runner 复核

Harness direct Dart runner 使用固定仓库 package config 和参数数组，不解析外部命令、不获取依赖、不
扩大网络或执行能力，并通过 `exec` 保留退出码；当前未发现安全回归。

## 最终复审

最终独立 Security Review 通过，P0 0、P1 0、P2 0。

- Attachment、surface policy、attachment reference 和 platform implementation 均在签名 Map 写入前
  拒绝重复；surface 与 attachment 保持一对一。
- 前置/后置恶意重复 policy/platform Fixture 内部自洽，并能命中指定重复诊断，不依赖 Schema 数量兜底。
- `diagnosticPolicy` 逐字段绑定结构化 value source/reference；operation/state/failure 使用实际完整 ID
  集合，record/status 使用 policy enum，伪值与引用漂移均被拒绝。
- 日志只允许稳定 record/status/failure 与脱敏状态，禁止实例、description、generation、target/source/
  renderer/binding、SDK/path/bytes/token/raw exception。
- Direct Dart runner 与固定 jq filter 未引入外部命令解析、依赖获取、网络访问或退出码吞没。

## V4 Harness 最终复审

独立安全复审确认 V3 Render Surface 仍保持 Native-only，V4 export 及其 source representation 不会
改变 surface/attachment 语义或进入旧版本投影。当前实现 `P0=0`、`P1=0`、`P2=0`；摘要已绑定最终
Capability、文档与共享 Harness。真实双端 surface 行为仍由平台任务验证。

## 跨 Runtime 集成影响

最终集成的 current/history vectors 继续把 concrete surface 固定为 Native-only，只更新已实现状态和
设备证据边界。独立安全复审为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。

## iOS 综合修正后的复审

独立 Security Reviewer 复核共享 Gate、golden、Core、Rendering、UI 与文档增量后，确认本轮没有修改
Capability/Wire 结构、surface ownership、权限或 Agent 能力。最终结论为 P0/P1/P2 0/0/0，本报告按当前
实现文件重新绑定摘要；方向适配明确不在本轮范围内。
