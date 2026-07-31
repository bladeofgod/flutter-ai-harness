---
executor: android-engineer
platforms: [android]
workKinds: [native]
blockedBy:
  - media-capture-android-core
  - media-capture-export-capability-evolution
securityReview: required
---

# 实现 Android Media Capture 流式媒体导出

## 输入与事实来源

- Capability V4 `copy_confirmed_media_to_sink`、export job/buffer、50 MiB 上限和 lease 竞态。
- 已实现的 Android Media Capture Core、App 私有媒体文件、callback-scoped read 与测试 Fake。
- Kotlin/Android 生产规范和 Native Testing Strategy。

## 目标

- 在 Android transport-neutral Native Module 实现 bounded streaming export 到调用方 sink。
- 保持源文件/lease 由 Core 拥有，sink/目标文件由 Native Consumer 拥有，不引入 Flutter 类型。
- 用单测证明大文件不会整段进入内存，取消/release/expiry 竞态只有一个终态且完整清理。

## 非目标

- 不创建 Bridge transfer 目录、file URI、export handle、Channel mapping 或 Flutter Store。
- 不修改 Wire、Dart Client、Android Adapter、Host/Manifest、Camera UI 或 iOS。
- 不自动 release source media，不改变 capture/thumbnail/preview 状态机。

## 实现要求

1. 在公共 API 增加类型化 `MediaCopySink` 和 export result/failure，sink 只暴露 suspend begin/write/commit/
   abort 等传输中立方法，不出现 `File`、`Uri`、`OutputStream`、Flutter 或 Channel Map。
2. Core 只允许 active confirmed `leased` media，验证 MIME、声明长度和 52,428,800 上限后原子登记
   `media_export_job`。每个 media 最多 1 个、Module 最多 4 个 active job、总 working buffer 最大 1 MiB；
   容量满时返回 Capability 固定的 `media_export_conflict`/`media_export_overloaded` 且不调用 sink。
3. 在注入的 IO Dispatcher 以最大 262,144 byte buffer 顺序读取并写 sink；测试可观察 peak buffer，
   禁止 `readBytes()`/等价全量分配。复制中累计长度和 EOF 必须与 metadata/实际文件一致。
4. 每个 job 从 reservation 起使用注入 Clock/调度器执行 120 秒 deadline。成功路径 flush/commit sink 后
   才完成 result；任意读写、取消、超时、长度漂移、sink failure、Core close、
   release/expiry 竞争都 abort once、清零/释放 buffer、注销 job，再完成稳定 failure。
5. export 不刷新 lease/TTL/grace/tombstone，也不释放源。release/expiry 获胜后拒绝新 export，并按
   Capability 顺序取消在途 job；export 已 commit 获胜时 caller 仍需单独 release source。
6. 日志与异常 mapper 只记录稳定 operation/state/failure，禁止 media/export handle、路径、文件名、URI、
   content、摘要或底层 IOException。
7. 更新 Android 基础能力详情的公共 API/线程/所有权/验证状态，不修改共享 Capability/Wire 文档。

## 测试与验收

- Kotlin 单测覆盖 JPEG/MP4、边界长度、空/超限、截断/增长、完整 Failure taxonomy、4-job/1-MiB 预算、
  sink begin/write/commit/abort failure、never-returning cancellable sink、120 秒 deadline、取消、
  release/expiry/Core close、并发 export、late callback 和 exactly-once。
- 以大于多个 chunk 的 Fixture 证明 peak buffer 不超过 256 KiB且 output bytes/order 正确；Fixture 为
  生成数据，不读取真实媒体。
- 原生 Consumer 测试直接实现 sink 并调用 Core，编译图不含 Flutter、Wire、Android `Uri` 或业务类型。

```bash
app/apps/demo/android/gradlew -p app/native/android/media_capture test lint assembleDebug assembleRelease
make lint
make harness-check
git diff --check
```

## 环境限制

需要 Android SDK/JDK。生成文件测试不证明真实 Camera 文件或设备 IO 性能；平台 Adapter/最终集成补充
真实 capture-to-import 流程。

## 执行记录

- Review：[`../../reviews/execute-media-capture-android-export-core.md`](../../reviews/execute-media-capture-android-export-core.md)
- Security Review：[`../../reviews/security-media-capture-android-export-core.md`](../../reviews/security-media-capture-android-export-core.md)
- 测试证据：[`../../reviews/test-evidence/media-capture-android-export-core.log`](../../reviews/test-evidence/media-capture-android-export-core.log)
