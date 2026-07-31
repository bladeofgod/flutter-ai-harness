---
task: media-capture-wire-v2-capability-v3-compatibility
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/bridge/contracts/wire.schema.json
  - docs/bridge/contracts/media-capture.wire.json
  - docs/bridge/media-capture.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: 36a6b0c06996ac5061d1374c52c52369d6e20f6ed3ebe1a115a1a96469f35f45
---

# Security Review: Media Capture Wire V2 / Capability V3 Compatibility

## 首轮结论

独立 Security Review 发现 P0 0、P1 0、P2 1。当前 Media Capture Profile、专用 Validator 和负例已阻止
V3 surface、factory、target、source、renderer、binding、generation、path、URI、原始 bytes 与 SDK
对象跨 Channel；唯一问题位于通用 Base Schema 的 Native artifact 条目约束。

## P2

### 通用 Native Artifact Schema 允许自相矛盾的 Wire 映射

`nativeArtifactCoverageEntry.disposition` 只允许 `native_consumer_only` 或
`intentionally_not_exposed`，但同一结构仍允许非 null `wireId`，`reason` 也允许 null 或空字符串。仓库
贡献者或契约生成器可创建“声明 Native-only、同时分配 Wire ID”的矛盾 Profile；只依赖通用 JSON
Schema、没有 Media Capture 专用 Validator 的后续消费者会接受它。

当前 Media Capture 没有实际泄漏：专用 Validator 已额外要求 `native_consumer_only`、`wireId: null` 和
非空 reason，现有 53 项均满足。风险仅影响通用 Schema 的后续复用。

修复要求：将 `nativeArtifactCoverageEntry.wireId` 固定为 `null`，将 `reason` 改为非空字符串；
`_validateWireSchema` 必须机器校验这两个领域中立约束，并增加分别放宽 wireId 与 reason 的 Schema mutation
负例。

## 已确认边界

- V3 全量校验先于 V2 synthetic projection；surface resource、owner scope 与 53 项 artifact 使用精确
  集合，重复、额外项和错误平台不能靠 Map 覆盖或计数替换绕过。
- Transport digest 覆盖 Channel、field、payload、method、event、failure、platform 和 lifecycle；Wire
  Version、Capability `[2, 3]` 范围与 V1 history 另有精确校验。
- field、payload、event、method 四类 Native Render 插入 Fixture 均命中指定语义诊断，不依赖 Schema
  偶然失败。
- slot、lease settlement、late cleanup、thumbnail、listener、去重和 exactly-once 结构未回归；没有新增
  网络、依赖、Agent 权限、路径/URI/raw bytes fallback 或敏感日志能力。

## 证据状态

首轮 `make harness-test` 与 `git diff --check` 通过；`make harness-check` 仅剩共享实现导致的既有安全摘要
漂移。修复和安全复审后必须更新最终 implementation digest、同步受影响摘要并重新采集绿灯。

## 最终复审

独立 Security Review 复审通过，P0 0、P1 0、P2 0。

- Base `nativeArtifactCoverageEntry.wireId` 固定为 null，`reason` 固定引用 `nonEmptyString`；普通
  `coverageEntry` 没有被误收紧。
- Harness 精确检查 Native artifact Schema 的闭合字段、null wireId 和 non-empty reason reference。
- 两条限定范围的 Schema mutation Fixture 分别放宽 wireId/reason，并要求出现各自专用诊断；完整
  `make harness-test` 实际通过，不能依赖 Schema digest 或其它错误偶然拒绝。
- V2/V3 双投影、53 项 Native artifact 精确集合、重复/额外项/错误平台拒绝、四类 Channel 注入边界、
  transport digest、V1 history、slot、lease、late cleanup、thumbnail 和 exactly-once 未发现回归。

最终安全复审快照的 `make harness-test` 与 `git diff --check` 通过。`make harness-check` 等待本报告及 6 份
受共享 Harness 影响的既有 Security Review 摘要同步后重跑。

## 当前实现复审

独立只读复审重新检查 Wire V2 保持、Capability V2/V3 兼容、V3 Surface/Artifact Native-only 边界、
path/bytes/surface fallback 禁止以及 thumbnail/late cleanup 语义。历史 P2 修复保持有效，当前实现未
发现 P0、P1 或 P2，摘要可同步到当前文件集合。双端 V3 concrete surface 行为仍需平台集成验证。

## V4 Harness 最终复审

独立安全复审确认 V4-only operation、field/request、result、failure、lifecycle/transition、resource、
ownership、cleanup/privacy、streaming policy 和 history 均由降投影移除，并有十三类 mutant 直接证明。
当前实现 `P0=0`、`P1=0`、`P2=0`；摘要已绑定最终 Wire 与共享 Harness。
