---
executor: task-executor
platforms: [android, ios]
workKinds: [capability-contract, harness]
blockedBy:
  - flutter-media-resource-architecture
  - media-capture-render-surface-capability-evolution
securityReview: required
---

# 演进 Media Capture 确认媒体导出 Capability

## 输入与事实来源

- Flutter 媒体资源设计要求先把 confirmed media 导入 App 私有 `app_media` Store，再释放 Native lease。
- Capability V3 的 `open_media_read` 只允许 Native callback-scoped 读取；Wire V2 明确禁止把 read scope、
  路径、URI 或原始 bytes 直接暴露给 Flutter。
- 当前照片为 `image/jpeg`、视频为 `video/mp4`，Native Module 物理拥有 confirmed media，consumer lease
  为 24 小时，release/expiry read grace 为 60 秒。
- `docs/native/contracts/capability.schema.json`、Media Capture Capability V3 和 Harness Validator。

## 目标

- 在传输中立 Capability V4 定义“把 active confirmed media 流式复制到 consumer-provided sink”的安全
  导出语义，供 Native Consumer 和后续 Bridge Adapter 复用。
- 固定 source lease、导出 job、chunk buffer、sink commit/abort、取消、竞态和清理边界。
- 让 Wire 可以派生一次性 transfer copy，而不是把 callback read scope 或整段视频 bytes 编码过 Channel。

## 非目标

- 不定义 Channel method、Wire key、file URI、Bridge export handle 或 Flutter Store。
- 不实现 Android/iOS 文件复制，不修改 Native Module、Adapter、Dart Client、Host 或 Feature。
- 不改变原媒体 lease TTL、release grace、thumbnail、Capture UI、编码格式或相册权限。
- 不允许调用方传入字符串路径、URI、文件描述符或平台 SDK 文件对象作为 Capability 字段。

## 契约要求

1. 提升为 Capability V4，保留 V1-V3 history/投影；Schema 扩展必须是通用 resource/sink 结构，不把
   Media Capture MIME、50 MiB 或字段 ID 写死进 base Schema。
2. 新增 `copy_confirmed_media_to_sink` operation（或语义等价稳定 ID）。输入只含 active
   `media_handle`、类型化 Native-only `MediaCopySink` capability 和结构化最大长度；sink 是调用范围内的
   consumer object，不可序列化、不可保存进 Module registry，也不能含路径字符串。
3. `MediaCopySink` 采用 begin/write/commit/abort 或等价闭合协议：Module 顺序写入 bounded chunk，成功时
   恰好一次 commit，失败/取消/release/expiry 时恰好一次 abort；commit 与 abort 不能同时发生。
4. 固定 source 类型 `image/jpeg`/`video/mp4`，最大复制长度 52,428,800 bytes，单 chunk/buffer 最大
   262,144 bytes。Module 必须在复制前检查声明长度、复制中累计长度、commit 前检查实际长度一致，
   不得把完整视频加载到内存。
5. 成功结果只返回 source handle 对应的媒体类型、content type、实际长度和可选完整性摘要等传输中立
   metadata；不返回 sink 的路径、URI、句柄或平台对象。摘要算法若加入必须闭合为 SHA-256，不能记录
   原始摘要值到日志。
6. 新增 `media_export_job` 和 `media_export_buffer` 资源/所有权阶段。每个 media 最多 1 个、每个 Module
   最多 4 个 active export job，总 working buffer 最大 1,048,576 bytes；Module 必须在打开 source/sink
   前原子预留 job/buffer，容量满时不调用 sink且不逐出既有 job。
7. 每个 job 从 registry reservation 起固定 120 秒 deadline。sink 的 begin/write/commit/abort 必须响应
   Task/coroutine cancellation，并在收到取消后 5 秒内收敛；不合作的 consumer 不满足 Capability
   conformance。deadline/release/expiry/Core close 获胜后关闭 callback gate、发出取消、abort once、
   释放 registry/buffer；晚到 sink result 只能丢弃，不能 commit 或二次完成。
8. 固定新增 Failure taxonomy及属性：`media_export_conflict`、`media_export_overloaded`、
   `media_export_too_large`、`media_export_sink_rejected`、`media_export_read_failed`、
   `media_export_write_failed`、`media_export_cancelled`、`media_export_timed_out` 均为当前 operation 的
   direct、non-terminal Failure，source lease 保持 active；未知 handle/非法状态/参数和 Core close 分别
   复用 `media_invalid`、`invalid_state`、`invalid_argument`、`system_interrupted`。Contract 必须逐个
   声明 recoverable、触发状态、race winner 和 sink abort 行为，不允许平台自建含混的 `export_failed`。
9. Failure message/details 不包含 handle、长度之外的源 metadata、路径、sink details、OS error 或底层
   异常。job 只在 active confirmed lease 上运行，不刷新 lease/TTL/grace/tombstone；release/expiry 与
   export 的线性化赢家决定唯一终态。
10. source lease 在 export 成功后仍由原 consumer 持有；Capability 不自动 release。调用者只有在后继
   Store commit 成功后才显式 `release_media`，从而避免复制成功但业务资源未建立时丢失原文件。
11. Native Consumer 现有 callback read 能力保持兼容；V4 export 是面向有界复制的稳定能力，不把
   `open_media_read` 改成可跨 callback 存活的对象。
12. Harness 覆盖 operation/result/failure/resource/ownership/cleanup/history/platform support，并拒绝
    任意路径/URI字段、unbounded bytes、全量内存 read、缺 Module 预算/deadline/cancellation、Failure
    taxonomy 漂移、lease 自动释放/延长、无 abort、双终态或单平台语义。

## 写入所有权

- `docs/native/contracts/capability.schema.json`
- `docs/infrastructure/contracts/media-capture.capability.json`
- `docs/infrastructure/media-capture.md`
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`
- 本任务 Review/Security Review/evidence

不得修改 Wire、Native/Dart 实现、Host、Feature、CI、Makefile 或其它任务卡。

## 测试与验收

- 正例证明 50 MiB 上限、256 KiB chunk、4-job/1-MiB Module 预算、120 秒 deadline、commit/abort exactly
  once、完整 Failure taxonomy、active lease 和双平台一致。
- 负例覆盖路径/URI/descriptor 字段、raw bytes result、unbounded sink、release 竞态、超限/截断/增长、
  never-returning/cancellation-uncooperative sink、自动 release、TTL 刷新、日志泄漏和遗漏 resource cleanup。
- Wire 设计可只读 V4 派生 transfer copy，不需要猜测 Native streaming、错误或 lease 语义。

```bash
make format
make harness-check
make harness-test
git diff --check
```

## 环境限制

本任务只演进结构化契约，不需要 SDK、设备或真实媒体。静态契约不能证明平台复制使用 bounded buffer；
由双端 Core 任务提供实现证据。

## 执行结果

- [实现 Review](../../reviews/execute-media-capture-export-capability-evolution.md)
- [Security Review](../../reviews/security-media-capture-export-capability-evolution.md)
- [测试证据](../../reviews/test-evidence/media-capture-export-capability-evolution.log)
