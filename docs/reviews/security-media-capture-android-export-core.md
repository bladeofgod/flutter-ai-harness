---
task: media-capture-android-export-core
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/api/AndroidMediaCaptureFactory.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/api/MediaCaptureModels.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/core/MediaCaptureCore.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/framework/AndroidStorageAndThumbnail.kt
  - app/native/android/media_capture/src/main/kotlin/com/example/mediacapture/framework/FrameworkContracts.kt
  - docs/infrastructure/media-capture-android.md
implementationDigest: 5cfe68d13c4991c36b90a2f0326cea7ac0e00687f5a28240c8007fe925723d0a
---

# Security Review: Android Media Capture Export Core

## 结论

独立只读 Security Review 通过，P0 0、P1 0、P2 0。审查覆盖 App 私有 source、Native consumer
提供的 typed sink、callback-scoped bytes、资源预算、终态与取消、late callback、目标所有权、异常脱敏
及跨 Runtime 边界，未发现具有具体可利用路径的问题。

## 资产与信任边界

- 受保护资产是 App 私有 JPEG/MP4 source、opaque media handle、borrowed callback bytes、最多 4 个
  export reservation、1 MiB working-buffer 预算和 consumer-owned target。
- Native consumer 控制 `mediaHandle`、`maxLength` 与 sink callback 行为，并已被授权接收对应媒体内容；
  同一 App 进程内的 Native consumer 不是机密性沙箱。Consumer 若违反 5 秒合作取消或原子 commit/abort
  协议，Core 无法恢复其外部 target，该限制已经写入 Capability 与 Android 文档。
- 公共 `MediaCopySink` 只暴露类型化 begin/write/commit/abort，不接收或返回 `File`、URI、FD、
  `OutputStream`、Flutter/Wire 类型或目标身份。真实 `File` 与 source reference 保持 module-internal。

## 已确认控制

- Export 只允许 active confirmed lease、固定 JPEG/MP4 MIME 和 `1..52428800` 长度；容量预检在打开
  source 或调用 sink 前完成，同 Media 1 job、Module 4 job。
- 生产 export 使用 128 KiB read buffer 与最多 128 KiB callback copy，不调用既有 callback read 的
  `readBytes()`；四个 job 的 Core working-buffer 上限为 1 MiB。
- callback copy 在回调返回后的 `finally` 擦除；read buffer 在 success/failure finalization 擦除。晚回调
  不与已释放 read buffer 共用数组，reservation 保留到 callback、abort 和 identity-safe unregister 收口。
- restart/close 不提前清除未收敛 export reservation；late cleanup 使用独立 owner，不允许 restart 后绕过
  4-job 总预算。sink callbacks 由同一 gate 串行，commit 与 abort 互斥且 exactly once。
- source/sink 底层异常、路径、handle、内容与异常文本不进入公开 Failure 或日志；公开结果只含 source
  handle、media type、固定 MIME 和实际长度。

## 验证边界

Debug/Release 各 85 个 JVM/Robolectric 测试、Android lint 和双 AAR 构建通过。状态机 50 MiB 用例使用
生成式 reader/counting sink；生产 `AndroidPrivateMediaStore` streaming 测试约 200 KiB。当前证据不包含
instrumented/device 命令，因此尚未证明真机 50 MiB I/O/RSS、厂商文件系统错误、存储中断和进程终止
时序；这些留给 Android Quality Gate 与最终 capture-to-export 集成。

本轮 Reviewer 未读取普通 Review 报告，未运行命令，也未修改实现。
