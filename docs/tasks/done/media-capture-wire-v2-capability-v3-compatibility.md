---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy:
  - media-capture-native-ui-flow-wire-evolution
  - media-capture-render-surface-capability-evolution
securityReview: required
---

# 对齐 Media Capture Wire V2 与 Capability V3 Render Surface

## 输入与事实来源

- 已归档 `media-capture-native-ui-flow-wire-evolution` 的 Wire V2、Harness、Review 与安全结论。
- 已完成 `media-capture-render-surface-capability-evolution` 的 Capability V3。
- 用户批准：Wire 保持 Version 2，并显式兼容 Capability V2/V3。
- `docs/native-architecture.md`、Bridge Contract 与安全边界。

## 目标

- 保持 `wireVersion: 2`，将兼容声明更新为 Capability `[2, 3]`。
- 证明 V3 concrete platform surface、内部 renderer/source 和 owner generation 仍完全留在 Native UI/Core，
  不改变现有 Flutter method、payload、event、failure 或全屏 flow。
- 为 Dart Client、双端 Core/UI/Adapter 提供稳定的 V2/V3 选择与失败语义。

## 非目标

- 不提升 Wire Version，不修改 Capability V3，不实现 Dart/Android/iOS 代码。
- 不新增 surface、View、Layer、SurfaceProvider、Session、path、URI、descriptor 或媒体 bytes 的 Channel
  mapping、payload fallback 或 platform object codec。
- 不修改现有 `present_capture_flow` 三终态、slot、lease settlement、exactly-once 或 thumbnail 语义。

## 实现路径与所有权

本任务只写：

- `docs/bridge/contracts/media-capture.wire.json`
- `docs/bridge/media-capture.md`
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`
- 本任务 Review、Security Review 与 evidence

只有通用 Schema 确有缺口时才可修改 `docs/bridge/contracts/wire.schema.json`，并须由 Review 证明没有
写死 Media Capture。本任务不得修改 Capability、Native/Dart 实现、Host、CI、Makefile 或归档任务卡。

## 契约要求

1. `wireVersion` 保持 2；当前 Profile 与 V2 history 的 `compatibleCapabilityVersions` 更新为 `[2, 3]`，
   保留 Wire V1 history 与 Capability V1 投影。
2. Capability V3 不新增 Channel method/payload/event/failure/result；现有 direct operations、
   `present_capture_flow`、thumbnail 和 envelope digest/shape 不变。
3. V3 module-defined platform surface、render binding/source、target identity、owner generation、attachment
   result/event/resource/ownership scope 全部逐项 `native_consumer_only`、`wireId: null` 并有稳定原因。
4. Android/iOS Adapter 只在 Native 内部创建和消费 concrete surface；Flutter 只能 present flow 或调用
   既有 direct methods，不能构造、选择或持有 surface。
5. V2/V3 选择失败继续使用 `incompatible_wire_version`/稳定 compatibility 语义，不用未知字段或
   platform exception 猜测版本。
6. Harness 对照 Capability V3 全量 coverage，并拒绝遗漏 V3、提升 Wire Version、改变既有 payload/
   method/event digest、把 surface/UI/SDK/source 加入 field/payload/event/method、增加 path/bytes fallback、
   缺双平台 disposition 或错误 history。
7. 直接补齐安全审查指出的纵深负例：分别向 field mapping、payload、event 和 method 插入 Native Render
   数据，并断言 Validator 精确拒绝。
8. 更新文档 support matrix、data classification、late cleanup 和日志 redaction；不得记录 Figma、公司
   设计来源、平台对象内容或真实媒体。

## 测试与验收

- 当前 Wire V2 Profile 对 Capability V2/V3 都确定性通过，Wire V1 historical projection 不回归。
- Profile/Harness 能证明 V3 surface 不跨 Channel，且现有 Flutter/Dart codec 无需新增字段。
- 普通 Review 与 Security Review 复核 slot/lease/late result/thumbnail 和 Native-only 边界没有回归。

## 验证命令

```bash
make format
make harness-check
make harness-test
git diff --check
```

## 环境限制

本任务只修改 Wire Contract/Harness，不需要 SDK、Xcode、设备或 Figma。静态兼容声明不证明双端
concrete surface 已实现；对应证据由 Android/iOS Core 与平台 Gate 产生。
