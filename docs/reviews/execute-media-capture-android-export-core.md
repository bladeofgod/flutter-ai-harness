---
task: media-capture-android-export-core
status: passed
p0: 0
p1: 0
---

# Review: Android Media Capture Export Core

## 首轮结论

独立只读 Review 首轮为 P0 0、P1 5、P2 0。类型化 sink、50 MiB 上限、4-job/1-MiB
预算、稳定 Failure 与基础复制流程已经实现，但终态所有权、callback gate、失败清理线程和 late cleanup
仍有阻断问题，现有测试也没有直接覆盖这些竞态。

## P1 发现

1. caller cancel、release、expiry、deadline 或 close 取消 worker 后，取消中的协程仍可能在 Core mutex
   上再次抛出 `CancellationException`，使 `Committing` 状态缺少确定的终态收口者。修复需要让取消后的
   claim/handoff 在 `NonCancellable` 中完成，并由唯一 terminal owner 负责 abort、unregister 与 result。
2. sink begin/write/commit 与 failure winner 没有共同 callback gate。Core terminal 已经失败后，已准备但尚未
   进入的 callback 仍可能修改 consumer target。修复需要让所有 sink callback 在同一生命周期 gate 下准入，
   terminal winner 先关闭 gate，再取消 worker并进入清理。
3. 成功复制虽运行在注入的 `ioDispatcher`，失败路径的 sink abort 和 source close 只切到
   `NonCancellable`，可能继承主线程或 worker dispatcher。修复需要让成功/失败 cleanup 都运行在注入的 IO
   上下文，并逐 callback 验证 dispatcher affinity。
4. 非协作 callback 超过 5 秒后，late cleanup 通过 Core `scope.launch` 投递；Core close 会取消该 scope，
   restart 又会提前清空 `exportJobs`。晚到 callback 因而可能没有 cleanup owner，并让旧 buffer 尚存时重新
   获得完整 module capacity。修复需要独立的 late cleanup owner，并把 reservation 保留到 identity-safe
   unregister 完成。
5. 任务卡声明的异常与竞态证据不完整：缺少 abort 抛错、零字节 source、真实 Android streaming wrapper、
   callback dispatcher、取消锁竞争、terminal gate、restart/close late callback 的直接测试。修复需要补齐
   这些回归场景，不能只依赖 Gradle task 成功。

## 流程项

当前任务声明 `securityReview: required`，首轮普通 Review 时尚未生成本任务绑定的独立 Security Review。
该报告将在实现问题修复、测试和普通复审通过后执行，避免对仍在变化的攻击面做无效摘要。

## 首轮验证

现有 evidence 记录了 Gradle `test lint assembleDebug assembleRelease`、仓库 lint、最终 Harness 和
`git diff --check` 成功。首轮 Reviewer 严格只读，没有运行测试、构建、格式化或修改文件；上述 P1 不在
现有覆盖内，因此任务暂不归档。

## 第一轮复审

首轮 5 个实现/测试 P1 中 4 个已经关闭，独立 Reviewer 仍发现 1 个 commit 线性化 P1：
`sink.commit()` 正常返回后、Core 写入 `Success` 前，release/deadline/expiry/close 仍可把 terminal 覆盖成
Failure。此时 target 已提交且 abort 被禁止，上层却可能按失败重试并产生重复资源。

修复后，`Committing` 阶段的 failure request 只关闭 callback gate、记录首个 failure code 并取消 worker，
不提前覆盖 terminal。Commit owner 根据 callback 结果完成唯一终态：正常返回对应 Success；取消或异常退出
对应记录的 Failure。测试 hook 被移到 callback return 后、Success claim 前，并在该窗口触发 release。

## 最终复审

独立只读复审最终为 P0 0、P1 0、P2 0：

- `sink.commit()` 正常返回后立即进入 `NonCancellable`，先标记 target 已提交，再经过受控 hook claim
  Success；该窗口中的 release 只能记录取消请求，不能把已发布 target 改报失败。
- commit callback 因取消或异常退出时，commit owner 在不可取消上下文中把 `Committing` 唯一转换为首个
  稳定 Failure，并执行 abort/close/wipe/unregister。
- caller cancellation 的 mutex claim/handoff、统一 callback gate、IO dispatcher cleanup、独立 late
  cleanup owner 和 restart/close reservation 保留均未回归。
- 新增测试覆盖 abort 异常、空 source、Core mutex 竞争、精确 commit-return 窗口、callback dispatcher、
  restart/close late callback、模块容量保留及生产 Android streaming read 的 EOF/revoke/idempotent close。

最终 Android Debug/Release 各 85 个测试通过，其中 export 专项 20 个；Gradle test/lint、Debug/Release
AAR 与仓库 lint 通过。Harness 仅待本任务 Security Review 完成并同步受影响旧报告的实现摘要后重跑。
JVM/Robolectric 仍不代替真实设备文件 I/O 性能、厂商文件系统行为与 capture-to-export 集成验证。
