---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy:
  - media-capture-export-capability-evolution
securityReview: required
---

# 演进 Media Capture Flutter Transfer Wire

## 输入与事实来源

- Capability V4 的 bounded sink export、原媒体 lease 语义与资源分类。
- Flutter `app_media` 设计：业务消息只持有 `MediaResourceId`；Bridge file URI 只用于立即导入 Store。
- Wire V2 当前只允许 bounded JPEG thumbnail，并明确禁止原始媒体路径/URI/bytes。

## 目标

- 建立 Wire V3，为 Flutter Consumer 增加一次性 `materialize_media_resource` 和
  `release_materialized_media`。
- 固定 Adapter-owned App 私有 transfer store、临时 file URI、export handle、TTL、容量、线程、生命周期
  和 exactly-once cleanup。
- 保持大媒体走本机流式文件复制，Channel 只传有界 metadata 和短生命周期 locator。

## 非目标

- 不修改 Capability V4，不实现 Dart/Android/iOS 代码，不接入业务页面。
- 不通过 Channel 传原始媒体 bytes、chunk、文件描述符或调用方提供的目标路径。
- 不把 transfer file 当成消息持久资源，不允许远程 URL、共享存储、相册 URI 或跨 App 访问。
- 不改变已有 capture/thumbnail/presentation method 的语义。

## Wire 要求

1. 提升 `wireVersion` 到 3，声明兼容 Capability V4；保留 Wire V1/V2 history 和既有 payload shape
   投影，已有方法、事件、错误和 thumbnail digest 不回归。
2. `materialize_media_resource` 请求只接受 `mediaHandle`；Adapter 自己创建随机目标和 export handle，
   不接受 Dart 提供 path/URI/file name。它以固定 Bridge sink 调用 V4 export。
3. 成功 payload 闭合为：opaque `exportHandle`、absolute normalized `fileUri`、媒体类型、content type、
   byte length、可选 duration/完整性 metadata 和 signed-64 `expiresAt`。canonical vector 使用
   `file:///absolute/path`：允许 URI authority component 存在但 host 必须为空字符串；拒绝非空 host、
   userinfo、port、query、fragment、`.`/`..` segment和非法/超长 percent encoding。Dart/Kotlin/Swift
   必须消费同一组合法与恶意 golden vectors，不能各自解释“无 authority”。URI 只允许 ASCII
   serialization，非 ASCII path scalar 使用 UTF-8 uppercase percent encoding；4096 上限按序列化后的
   ASCII code unit 计数。
4. file URI 必须由 Adapter 从 plugin-owned App private cache transfer root 生成；Wire 文档明确这是
   `sensitive_local_locator`，只允许 Dart 基础设施立即消费，禁止进入日志、error details、event、消息、
   Fixture、Route、analytics 或持久化。
5. transfer file 最大 52,428,800 bytes，TTL 固定 300 秒。每个 Engine attachment 最多 4 个 active export、
   总 active bytes 最大 104,857,600；容量满时先返回稳定 `transfer_store_overloaded`，不调用 Capability。
6. `release_materialized_media` 只接受 opaque export handle，删除 transfer file 并保留 300 秒 tombstone；
   首次 release 原子认领 cleanup 和 tombstone reservation，删除成功后移除 active registry 并归还 active
   export/bytes 容量；不同 request 并发 release 同一 handle 只能加入同一 claim，重复 release 幂等。
   materialize 不自动释放 source media lease，release export 也不等价于
   `release_media`。
7. Adapter 成功完成 Flutter 前必须原子 commit 文件并登记 export；Flutter completion 失败、Engine
   detach、App restart、TTL、cancel 或 late Capability result 都先 abort/delete，再结束 completion。
   已交付 export 在 Engine detach/TTL 时按固定顺序标记 cleanup、删除、移除登记并释放容量；App restart
   必须先清扫私有 transfer root 并重置容量，再开放新请求。Flutter 必须在使用范围内完成导入，不能跨
   attachment 保留。
8. Capability V4 direct Failure 使用一一对应的稳定 Wire code：`media_export_conflict`、
   `media_export_overloaded`、`media_export_too_large`、`media_export_sink_rejected`、
   `media_export_read_failed`、`media_export_write_failed`、`media_export_cancelled`、
   `media_export_timed_out`，并保留各自 recoverable/terminal 属性。Adapter/Wire 自有错误另用
   `transfer_store_overloaded`、`transfer_store_unavailable`、`materialized_media_invalid` 和既有 lifecycle/
   encoding code；不得使用来源含混的 `export_failed`/`export_invalid`。failure coverage 必须标记
   `capability_failure` 或 `wire_protocol` 来源，details 不回显 URI、handle 或底层错误。
9. Dart 调用顺序写入 contract：materialize -> import `app_media` -> release export -> release source media。
   任一清理失败采用 bounded retry/retained cleanup，但不得在 source 尚未成功导入时先 release source。
10. coverage 逐项映射 V4 export operation/result/failure/job/buffer/sink。Native sink 和 source read scope
    `native_consumer_only`；只有 Adapter 生成的 transfer metadata 映射到 Wire。
11. Android/iOS support matrix 完全一致；平台只能在私有 cache API 和 UI-thread callback 机制上不同。
12. Harness 拒绝 caller path、非 file URI、locator 进入错误/日志/event、raw bytes/chunk method、无 TTL/
    容量/cleanup、source 自动释放、双平台漂移和版本 history 缺失。

## 写入所有权

- `docs/bridge/contracts/media-capture.wire.json`
- `docs/bridge/media-capture.md`
- 必要时通用 `wire.schema.json`
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`
- 本任务 Review/Security Review/evidence

不得修改 Capability、Dart Client、Native Module、Adapter、Host、Feature、CI 或 Makefile。

## 测试与验收

- Schema/Profile 正例和恶意 Fixture 覆盖三端 file URI vectors、Failure 来源、长度、容量、TTL、tombstone、
  版本、late cleanup 和 redaction。
- Wire V2 历史投影仍证明原始媒体不可读；只有 Wire V3 明确增加 scoped transfer locator。
- 安全审查确认 file URI 的暴露范围、清理时序和源 lease 不会造成越权读取或永久残留。

```bash
make format
make harness-check
make harness-test
git diff --check
```

## 环境限制

纯 Contract 任务不创建真实文件，也不证明 Android/iOS cache root。平台实现与最终集成负责路径范围和
真实复制证据。

## 执行结果

- [实现 Review](../../reviews/execute-media-capture-export-wire-evolution.md)
- [Security Review](../../reviews/security-media-capture-export-wire-evolution.md)
- [测试证据](../../reviews/test-evidence/media-capture-export-wire-evolution.log)
