---
task: media-capture-wire-v2-capability-v3-compatibility
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: Media Capture Wire V2 / Capability V3 Compatibility

## 首轮结论

首轮独立 Review 未通过，P0 0、P1 1、P2 0。Wire Version 2、Capability `[2, 3]` 声明、V1 history、
既有 transport shape、V3 Native artifact/resource/ownership coverage 与四类 Native Render 直接注入负例
均已形成；但当前 Harness 只对完整 Capability V3 做验证，尚未真正证明同一 Wire V2 映射对 Capability
V2 projection 仍成立。

## P1

### Capability V2/V3 兼容只验证了声明，没有分别验证两个投影

Validator 固定要求被读取的 Capability 为 Version 3，再检查 Wire 声明精确等于 `[2, 3]`；operation、
result、event、failure、resource、ownership 和 Native artifact coverage 也只从当前 V3 展开。现有测试会
篡改兼容声明，但没有构造或验证 V2 projection。因此当前结果只能证明 V3 Profile 声明兼容 V2/V3，
不能证明 V2 既有传输映射没有随 V3 演进失配。

修复要求：Harness 应根据已锁定的 V3 additive history/delta 构造 V2 transport projection，不新增或修改
Capability V2 文件；精确移除仅属于 V3 的两个 render surface policy、两个 surface resource、两个 owner
scope 和对应 53 项 artifact coverage，并对 V2 projection 与完整 V3 分别执行同一套 Wire field/method/
payload/result/event/failure 映射校验。Profile 可以保留额外 V3 coverage metadata，但这些条目必须已由 V3
校验为 `native_consumer_only`、`wireId: null`，且不能进入受保护 transport shape。补 V2/V3 正例，以及
篡改 V2 既有映射和 V3 additive delta 的定向负例；projection delta 必须由精确集合或摘要锁定，不能只
修改 `capabilityVersion`。

## 已确认项

- 53 项 Native artifact coverage 与当前两项 V3 render surface 的 factory input/output、target identity、
  owner generation、双平台 surface/conformance/mount/source/renderer/binding/diagnostic 动态集合一致。
- field mapping、payload、event 和 method 四类 Fixture 插入真实 Capability Native Render 数据，并断言
  指定 Validator 诊断。
- 既有 Wire transport shape 使用独立摘要保护；resource、ownership、Native-only、日志和 late cleanup
  静态核对未见回归。

## 证据状态

首轮审查时本任务 evidence 尚在主流程采集。修复后必须重新采集最终 `make format`、`make harness-test`、
`make harness-check` 与 `git diff --check`；安全摘要只能在独立 Security Review 后同步。

## 第 1 轮复审

独立复审通过，P0 0、P1 0、P2 0。

- 完整 V3 先执行 transport 与 coverage 校验，再由受限 builder 构造 V2 projection；V2/V3 复用同一个
  `_validateMediaCaptureWireTransportProjection`，没有维护第二套宽松映射规则。
- Additive delta 精确锁定两个 render surface policy、两个 surface resource、两个 owner scope 和 53 项
  Native artifact。V3 完整校验先证明 extra metadata 全部为 `native_consumer_only`、`wireId: null`，再在
  V2 projection 中过滤；受保护 transport shape 保持不变。
- 双 projection 基线正例已加入。篡改 V2 既有 `enabled_media_types` 映射的负例明确命中
  `Capability V2 transport projection` 诊断；篡改 V3 surface resource delta 的负例明确命中 builder 的
  `Capability V3 additive transport delta` 诊断，证明实现不是只改 `capabilityVersion`。
- Base Wire Schema 继续使用领域中立 artifact kind、owner policy、可选平台和 disposition，没有写入
  Media Capture、Camera 或具体 Render 类型。

修复后执行 Agent 的完整 `make harness-test`、格式、Dart analyze、Shell/JSON 与 diff 检查均通过；最终
主流程证据和绿灯 `make harness-check` 在独立 Security Review 与摘要同步后追加。

## 安全修复后的额外普通复审

安全修复后的额外独立普通复审通过，P0 0、P1 0、P2 0。

- 仅 `nativeArtifactCoverageEntry` 的 `wireId` 被固定为 null、`reason` 被固定为
  `nonEmptyString`；普通 `coverageEntry` 继续允许 mapped/exposed 条目使用非空 wireId 和 null reason。
- Validator 使用正确的 raw `$ref` 精确检查 `#/$defs/nonEmptyString`，没有字符串插值或转义错误。
- 两条 Schema mutation 的 sed 范围只覆盖 `nativeArtifactCoverageEntry` 到下一个 `platformContract`
  定义，分别命中 wireId/reason 的专用诊断。
- V2/V3 projection、受保护 transport shape、既有 Wire Fixtures 与 Base Schema 领域中立性未回归。
