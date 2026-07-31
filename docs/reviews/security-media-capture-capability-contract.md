---
task: media-capture-capability-contract
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/native/contracts/capability.schema.json
  - docs/infrastructure/contracts/media-capture.capability.json
  - docs/infrastructure/media-capture.md
  - docs/infrastructure-modules.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: ffea5789725fe74c24d53b4549ef9b03f3c3f78d2ff883dd6e3afce4be5807dc
---

# Security Review：Media Capture 能力契约

## 结论

最终 Security Review 通过，P0 0、P1 0、P2 0。审查覆盖输入校验、Camera/Microphone 权限、
媒体文件所有权、受控读取、opaque handle、清理、日志与隐私边界，并复核共享 Harness 没有
破坏前序任务建立的 Agent 安全约束。

## 首轮问题与修复

### 1. 公共请求缺少一致、可执行的输入边界

首轮时长、焦点和 zoom 约束主要写在描述中，且 zoom 允许平台自行 clamp 或 reject。
修复后录像时长固定为 `1..60000` 毫秒，焦点固定为有限数 `[0,1]`，zoom 必须为有限数、
受当前 session 快照约束并统一 reject。请求违反结构化规则时返回可恢复、非终止且不改变状态的
`invalid_argument`；Schema、Profile、Harness 和负例共同固定这些语义。

### 2. 活动读取可能无限阻止敏感文件删除

修复后 release 或 24 小时 TTL 到期立即拒绝新读取，已有读取最多保留 60 秒；宽限到期执行
`force_revoke_close_delete`，强制撤销、关闭并删除媒体。重复 release 不延长宽限，App 重启
同样清理 leased 与 grace 状态。

### 3. opaque handle 缺少能力令牌约束

Session/Media handle 现在限定为 module instance 作用域，由平台 CSPRNG 生成，最小 128-bit
entropy、最长 128 字符、永不复用且只允许严格 registry lookup。契约明确禁止从文件路径派生
handle，也禁止把 handle 参与路径拼接。

## 已确认边界

- Camera 权限只由明确用户操作触发；Microphone 只用于带音频录像；模块不请求 Photo Library。
- 媒体位于 App 私有临时空间，Consumer 只获得 opaque handle 和受控只读访问，不获得任意路径。
- 取消、失败、TTL、release、读取宽限和 App 重启都有确定的资源清理规则。
- 位置与设备敏感元数据会被清理，日志不得记录原始 handle、路径或用户媒体内容。
- `docs/tasks` 链接防护、Executor/Skill 精确路由、Reviewer 只读工具与对应 Fixture 均未回归。

## 验证

[测试证据](test-evidence/media-capture-capability-contract.log) 中保留了修复过程与最终门禁输出。
Security Reviewer 基于当前实现、负向 Fixture 和证据完成独立只读复审，未发现剩余问题。

## 后续共享门禁复审

Media Capture Bridge Contract 扩展了共享 Validator 与 Fixture，因此本报告的实现摘要同步更新。
对应的最终独立 [Security Review](security-media-capture-bridge-contract.md) 重新验证了 Capability
输入边界、CSPRNG opaque handle、strict registry、禁止路径派生以及 60 秒读取宽限，确认这些
安全约束没有因 Wire 门禁变化而回归。

Thumbnail Capability V2 再次扩展了同一 Schema/Profile/Validator/Fixture。最终独立 Security Review
确认请求字段边界、CSPRNG opaque handle、strict registry、禁止路径派生、24 小时 lease、60 秒 read
grace、重启失效与隐私日志约束均未回归；本报告摘要同步到当前实现。

## 当前实现复审

独立只读复审重新检查 transport-neutral Capability、权限模型、文件所有权、opaque handle、EXIF/位置
隐私与 Render Surface 的 Native-only 边界。当前实现未发现 P0、P1 或 P2，摘要可同步到当前文件
集合。该静态契约结论不能证明 Android/iOS 真实模块行为。

## V4 Harness 最终复审

独立安全复审确认 V4 只增加有界 Native sink export，未放宽原有 opaque handle、lease、权限、文件、
清理或日志隐私边界。十三类降投影 mutant 全部通过。当前实现 `P0=0`、`P1=0`、`P2=0`；摘要已
绑定最终 Capability、模块索引和共享 Harness。

## 当前共享 Harness 复审

独立 Security Reviewer 确认后续 Validator 与 mutation Fixture 扩展没有放宽 Capability 的闭合集合、
opaque handle、权限、文件所有权、读取/导出、清理或日志边界，也没有扩大 Agent、MCP、CI 权限。
当前结论仍为 `P0=0`、`P1=0`、`P2=0`。
