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
  - app/lib/harness_validator.dart
  - app/lib/src/harness_validator.dart
  - app/lib/src/implementation_digest.dart
  - scripts/quality/test-harness.sh
implementationDigest: 9e9720b2caf479088fcf422d984a1f13df21da636200b1cf5985ae9a7dceb8b3
---

# Security Review: Media Capture Wire V2 / Capability V3 Compatibility

## iOS dismiss 支持状态影响复审

后续 Wire V3 只提升 Adapter dismissal 的 iOS support；V2 history projection 仍完整移除 V3-only dismiss，
Capability V3 Native artifact、surface、path/URI/raw bytes 禁入和 transport digest 规则均未变化。独立
Security Reviewer 确认 P0 0、P1 0、P2 0，摘要已绑定当前共享文件。

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

## 跨 Runtime 集成影响

最终 golden 继续精确锁定 Wire V1/V2 不暴露 Native read/render/transfer，V3 才暴露 scoped transfer；
三端消费者与 Harness 均验证完整 history。独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。

## Validator Library 路径迁移复审

2026-08-06 独立安全复审确认 Validator 仅拆分为不可变 Library 结果和薄 CLI，未放宽本报告的既有安全约束。绑定已覆盖公开入口、真实 Validator、摘要计算器、CLI 和 Shell Fixture。

## Wire 生成 Profile 影响复审

2026-08-06 复审确认新增内容仅为闭合 descriptor、无副作用 field/envelope primitive 和生成工具，Wire V3、Capability V4、Native 生命周期、线程与资源 ownership 均未改变。固定 Schema/输出白名单和注入负例未放宽本报告边界，P0/P1/P2 维持 0/0/0。
