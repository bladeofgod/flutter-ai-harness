---
task: media-capture-ios-export-core
status: passed
p0: 0
p1: 0
---

# Review: iOS Media Capture Export Core

## 首轮结论

独立只读 Review 首轮发现 P1 4：commit 已成功后可能被失败 winner 覆盖；source read/close 竞态中的 Data
没有完整擦除；自发 `CancellationError` 会被误映射为 caller cancel；commit/peak buffer 的确定性竞态覆盖
不足。实现增加线程安全 `MediaExportControl`、逐阶段 Cancellation 映射、read/chunk accounting 与六类 commit
trigger 测试后关闭。

## 第二轮结论

复审继续发现 P1 2：Data 已由 source 产生但仍停留在 executor delivery window 时，failure winner 后仍可能
调用 `sink.write`；不合作 sink 在观察取消后仍成功 commit 时无法保证物理 commit/abort 互斥。

最终实现会在 executor 交付 Data 后、创建 chunk/write 前重新检查 control，失败先擦除 Data；确定性
delivery gate 断言 `writeCount == 0`、abort once、buffer 为零。`MediaCopySink` 契约明确同进程 consumer 的
合作边界：callback 五秒内响应 structured cancellation，commit 观察取消必须在不可逆发布前抛错并保持
abortable；违反者不属于 Capability conforming sink。

## 最终复审

最后一轮发现 commit 正常返回后、Core 仲裁前的 late cancellation 仍可能把已发布目标报告为失败。
修复把 commit 正常返回定义为发布成功线性化点；返回前观察到取消仍失败并 abort，返回后才登记的 release
或 caller cancellation 均返回成功且不 abort。参数化回归测试直接覆盖两种窗口。

独立 Reviewer 最终结论为 P0 0、P1 0、P2 0，可以归档。已确认：

- active lease、50 MiB、单 Media 1 job、Module 4 job/1 MiB reservation 在打开 source/sink 前验证。
- 128 KiB read 与 128 KiB callback chunk 逐块复制、返回即失效/擦除；长度漂移不截断或补齐。
- caller cancel、120 秒 deadline、release、expiry、restart、close 共用 first-winner cleanup。
- success 不自动 release/刷新 source lease；失败 abort once，source/chunk/job/deadline 均收口。
- 公共 API 不出现 Flutter、UIKit、AVFoundation、URL、FileHandle、路径、sink identity 或全量媒体 Data。

## 验证

[`test-evidence/media-capture-ios-export-core.log`](test-evidence/media-capture-ios-export-core.log) 的最终记录：

- Export 专项：16 tests，0 failures。
- MediaCapture Core：86 tests；Apple Rendering：6 tests；Public Consumer：2 tests；合计 94 tests，0 failures。
- generic Simulator Debug build 与 distribution Release build：通过。
- distribution `.swiftinterface` 敏感依赖/类型扫描：通过。
- 证据脱敏：通过。

Simulator/Fake 不证明真机大媒体 I/O/RSS、文件保护、厂商文件系统、硬件采集到导出的完整时序或进程终止
恢复。这些由最终 iOS Gate/用户真机验收承担，不影响本 Core API 与状态机结论。

## 后续共享 Core 对齐

镜头切换 correction 没有改变 Export source、sink、预算、deadline、commit/abort 或 lease 语义。当前共享
Core 完整 scheme 已增长为 Core 89 项、Apple Rendering 6 项、Public Consumer 2 项，合计 97 项 XCTest；
Export 专项仍为 16 项并由其原始 evidence 独立记录。
