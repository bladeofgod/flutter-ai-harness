---
task: media-capture-android-core
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: Android Media Capture Native Core

## 首轮结论

首轮独立 Review 未通过，P0 0、P1 9、P2 1。模块可以在锁定工具链下完成 Debug/Release 编译、
24 个 Framework Fake 测试与 lint，但 Session/Recording/Thumbnail 的并发所有权、attachment cleanup、
捕获文件交接、事件可靠性、权限映射和生产 Wrapper 测试仍未满足任务卡。

## P1

### 1. 取消或重启与异步 prepare 存在资源所有权竞态

`startSession` 没有保存初始化 Job，CameraX `prepare` 在锁外运行。cancel 可先 close 并终结 Session，
旧 prepare 随后完成时只因状态不符 return，不会清理刚绑定的 Framework；替代 Session 还可能与旧
initialize 并发操作同一 CameraX 实例。

修复要求：Session 持有 initialize Job/epoch；cancel/restart/close 先推进 epoch 并取消、等待；stale
prepare result 使用 NonCancellable 清理，清理完成前不得复用 Framework。补 cancel-during-prepare 与
cancel 后立即新建 Session 的测试。

### 2. 自动停止计时器可能误停后续录像

录像 timer 没有保存、取消或校验 recording generation。第一次录像手动 stop、retake 并再次 start 后，
旧 timer 仍可能停止第二段录像。

修复要求：每次 recording 分配 generation/Job；stop/cancel/failure/close/new recording 均取消旧 Job，
timer 在锁内同时核对 generation。补完整序列测试。

### 3. thumbnail 的 release/expiry 与 success winner 不原子

release/定时 expiry 先改变媒体状态，解锁后才 fail Job；同步发现 expiry 时甚至不会 fail 已登记 Job。
worker 可在间隙提交 success，导致 source 已 release/expired 后仍返回缩略图。

修复要求：媒体状态转换和 thumbnail terminal winner 使用同一线性化协调点；success commit 同样在该
协调点确认 active lease，cleanup 再移到锁外。补 release、定时 expiry、同步 expiry 竞态测试。

### 4. thumbnail cleanup 抛错会挂起结果并占住并发槽

success/failure 都在 terminal CAS 后串行 cleanup，最后才 unregister/complete。任一步抛错后 fallback
无法改变已提交 terminal，`await()` 不结束且 managed Job 永不注销。

修复要求：NonCancellable 与 try/finally 保证每步 best-effort，unregister last，outcome exactly-once；
cleanup 异常不得覆盖稳定结果。补各 cleanup step 抛错测试。

### 5. attachment cleanup 持全局 mutex 调用外部 suspend Adapter

attach/detach/revoke 从 mutex 内调用 Adapter；Adapter 重入 Core 会死锁，revoke 或 detach 抛错会留下
binding 并让 terminal/rotation/close 半完成。

修复要求：锁内推进 generation 并清除或标记 binding，锁外按 token 有序执行 revoke/detach，finally
保证后续步骤。补 reentrant 和 throwing Adapter 测试。

### 6. 捕获文件在 Framework 产出到 Registry 接管之间缺少 ownership guard

photo/video 已产出后，metadata 校验、handle 分配或取消失败会遗留私有媒体；生产存储删除还吞掉异常
或 delete=false，Core 仍可能宣布 released/read_revoked。

修复要求：CapturedMedia 使用 commit flag 与 NonCancellable finally；Registry 接管前任何退出都
revoke/delete。删除失败必须可感知并采用确定策略，不能伪报 cleanup 完成。补 invalid metadata、handle
exhaustion、capture cancellation 和 delete failure 测试。

### 7. Ready/Failed 等关键事件可能在订阅前永久丢失

`MutableSharedFlow(replay=0)` 不保留无 subscriber 时的历史事件；initialize 可在 `startSession` 返回或
调用方订阅前 emit，消费者一旦漏掉 Ready 就无法恢复 capability snapshot。

修复要求：提供可可靠观察的 per-session outcome/state stream/await API，或带消费确认的事件机制，
不能依赖调用前订阅。补 start 后订阅测试。

### 8. 运行时权限失效映射与文档不一致

Camera bind 的 `SecurityException` 被映成 `resource_in_use`，focus/zoom/torch Future 的安全异常还可能
被泛化成 `system_interrupted`，而文档声明应映成 `permission_denied`。

修复要求：所有受权限保护的窄调用点统一捕获 SecurityException 并映射 permission_denied，同时保留
CancellationException 传播；补 Framework Wrapper 映射测试。

### 9. 验收测试没有覆盖任务声明的生产边界

当前测试全部依赖 Fake，没有覆盖 `CameraXCaptureFramework`、`AndroidPrivateMediaStore` 或
`AndroidSanitizedThumbnailGenerator`，因此文档对 EXIF、poster、decode-time bound 与 cleanup 的已覆盖
表述不成立。

修复要求：增加可运行的 JVM/Robolectric 或 instrumented production-wrapper 测试；真实 Camera、权限
和厂商编码器仍留给设备 Gate，不得用 Fake 结果代替。

## P2

### 1. SessionOptions 集合没有防御性快照

`enabledMediaTypes` 可由调用方传入 mutable Set，SessionRecord 保存原引用后，调用方可在 Session 中途
无锁改变能力判断。

修复要求：入口和 PreparedCapture 均执行不可变快照，并增加 mutation test。

## 证据缺口

模块 `test lint` 已成功留证；任务卡要求的 `make lint`、`make harness-check`、`git diff --check` 尚待在
共享 Wire 测试完成后追加。真机 Camera、Microphone、权限 UI、硬件中断和性能按任务卡留给 Android
Quality Gate，不作为本卡 Fake 验收结果。

## 第 1 轮复审

录像 generation/timer、thumbnail release/expiry 核心 winner、cleanup step 异常、权限映射、Robolectric
边界和 Set 防御快照已关闭。复审仍有 P0 0、P1 8、P2 0，任务不能通过。

1. 普通 photo/recording/control operation 未绑定 Session/Framework owner；cancel 后旧 operation 可能
   作用于替代 Session。terminal cleanup 必须 drain 旧 operation，进入 Framework mutex 后再次验证 token。
2. Framework close 在真实 close 前标记 closed，异常被吞后仍释放 ownership。需要 closing/closed/poisoned
   状态，只有确认关闭才允许复用，失败时稳定阻止新 Session 或执行确定重试。
3. cancel/failure/timeout 删除失败时 Media 仍为 PREVIEW，可重新 attach。逻辑终态必须先使 Media 不可
   attach/read，物理删除转为可调度 retry。
4. StateFlow 离开 PREVIEWING 后仍继承旧 preview。retake/cancel/failure/timeout 必须显式清空并补晚订阅测试。
5. `adapter.attach()` 与 cleanup 并发时，唯一 detach 可能发生在 attach 真正完成之前。Binding 需要
   attach-completion gate，cleanup 等 settle 后保证最终 detach。
6. thumbnail 在 terminal claim 前创建 caller copy；failure 先胜时 Lost 分支必须擦除本地 copy。
7. thumbnail source open 在 dispatcher prompt cancellation 时可能丢失已打开 descriptor。acquire/ownership
   transfer 必须提供取消 disposal，并补 gated open 测试。
8. CameraX 预交接取消/错误仍直接 `File.delete()` 或不删除，绕过安全擦除与 pending retry。所有路径必须
   经统一 MediaStore ownership guard，把清理失败交回模块 owner。

当前 evidence 仍是首轮 24-test 快照；修复完成后需重新采集 Debug/Release 38+ tests、lint 和仓库门禁。

## 第 2 轮复审

第 1 轮的 8 个 P1 中，Framework owner 隔离、poisoned close、删除重试、StateFlow 清理、attachment
completion gate、descriptor 取消释放和 CameraX 预交接清理均已关闭。复审仍有 P0 1、P1 2、P2 0。

### P0：内部 cleanup 状态被扩展为 public MediaState

Android 单平台新增 public `MediaState.CLEANUP_PENDING`，但 Capability V2 没有该状态，Bridge/iOS 也无
合法映射。删除失败后的逻辑终态方向正确，但 pending physical cleanup 必须保持为 `MediaRecord` 内部
标志，对外继续使用 Capability 已声明状态。

### P1：Framework action 整段 NonCancellable 会无限阻塞 drain

`takePhoto`/`stopRecording` 整段位于 NonCancellable，operation cancel 无法传播到 CameraX
`suspendCancellableCoroutine`。真实 callback 不返回时 cancel/restart/close 会无限等待 settled。

修复要求：Framework action 保持 cancellable；只有 ownership rollback、close、delete cleanup 使用
NonCancellable。响应取消的 gated Framework 必须无需人工放 gate 即完成；不响应 Framework 采用有界
poison/timeout 隔离，不能无限挂 Host 生命周期。

### P1：thumbnail Lost-copy 分支缺少受控竞态测试

Lost/Failure 已实现 caller copy wipe，但现有 gate 停在 generate 之前，没有命中“copy 已创建、terminal
claim 前 failure 先胜”。需要在 copy/claim 之间提供测试协调点或提取 arbiter，断言 failure outcome、
caller copy 清零、work cleanup 与 unregister 顺序。

本轮源码为 48 个测试；主线程已在复审并行期间追加 JDK 21 当前快照模块门禁证据，但普通 Review 仍须
对第 3 轮最终实现重新复核。

## 第 3 轮最终复审

public `CLEANUP_PENDING` 已关闭，公开状态重新与 Capability V2 一致，物理清理等待只保留为内部
`physicalCleanupPending`。photo/stop Framework action 已恢复可取消，cancel/prepare 的无响应路径有 5 秒
timeout + poisoned 隔离。thumbnail copy-before-claim 测试也真实命中 failure-first，并验证 copy 清零、
failure cleanup 和 slot 注销。当前仍有 P0 0、P1 1、P2 0。

### P1：retake drain 超时不会 poison Framework

`drainFrameworkOperation` 只在 Session epoch 已变化时 poison；`retake` invalidates active operation 后不
递增 epoch。若 photo 已发布 PREVIEWING、随后卡在 finally/pending cleanup，UI 调用 retake 会在 5 秒后
返回 READY，却不会 poison 仍被旧 operation 占用的 Framework，后续操作仍可能挂起。

修复要求：超时后只要 Framework 仍属于该 operation owner 就进入 poisoned，并增加“preview 已提交、
旧 operation 最终清理无响应、retake 超时”的受控测试。

源码与文档现为 52 个测试；JDK 21 当前快照的 Debug/Release test 与 lint 已重新采证通过，构建缓存已
清理。由于已达到三轮自动修复上限，本任务保持 active，不执行第 4 轮、不做 Security Review 或归档，
等待用户明确授权下一步。

## 用户授权的第 4 轮复审

用户明确授权继续修复第 3 轮剩余 P1。`drainFrameworkOperation` 超时后的 poison 判定已不再依赖
Session epoch；只要 Framework 仍属于同一 operation owner 即进入 poisoned。新增测试真实等待
StateFlow 发布 PREVIEWING/preview，将旧 photo 卡在 pending-cleanup finally，并验证 retake 5 秒有界
完成、后续 operation 稳定拒绝、restart 有界且新 Session 不会复用旧 Framework。

独立复审确认原有实现范围 P0 0、P1 0、P2 0；JDK 21 下 Debug/Release 各 53 个测试、lint 与 clean
由 Executor 通过。随后用户批准 Capability V3 规划，本活动任务新增 concrete
`MediaCaptureRenderView` 的真实 CameraX/photo/video renderer 验收，并被新的 Capability 任务阻塞。
该新增范围尚未实现或复审，因此本报告继续保持 `failed / p1: 1`，不得执行 Security Review 或归档；
V3 实现后重新采集最终证据并追加完整普通复审。

## Capability V3 concrete renderer 独立审查

独立 Reviewer 对当前 Android Core 与 concrete renderer 只读审查，结论为 P0 0、P1 3、P2 0：

1. attachment 在 mount 后、commit mutex 等待和 `commitCallbacks` 三个取消窗口中，回滚仍可能被调用方
   cancellation 再次中断，导致 provider、图片或播放器残留。
2. render surface 从 factory 创建到 Core module 登记、destroy callback 安装之间存在 prompt cancellation
   ownership window，未交付 View 的 lifecycle observer 可能残留。
3. `VideoView` 异步错误被无条件吞掉，既未校验当前 binding/generation，也没有撤销 attachment 或提供稳定
   恢复状态。

## Capability V3 修复待复审

- attachment 的所有取消与错误回滚统一进入 `NonCancellable` ownership cleanup；新增 mount、commit 前和
  callback commit 三个受控取消测试。
- surface create/register/callback handoff 使用短暂不可取消交接；任何未成功返回给 Consumer 的 output 都
  执行 `abandonFactoryOutput`，callback 改为弱持有 surface；新增 factory return 与 registration 等待取消测试。
- video error callback 只在 install/committed mutation gate 有效时通知 Core；Core 按 binding identity 撤销
  attachment 并复用 `AttachmentRevoked`，过期 callback 丢弃且不传播平台 `what/extra`。
- 当前 Debug/Release 各 63 个测试、lint、Debug/Release AAR、仓库 lint/harness/diff 均已通过本地验证。

在该修复快照中尚未完成独立复审，因此当时报告继续保持 failed。

## Capability V3 最终独立复审

独立 Reviewer 对最终实现、测试与脱敏 evidence 复审通过，P0 0、P1 0、P2 0：

- mount、commit mutex 等待与 `commitCallbacks` 三个取消窗口均进入不可取消 ownership rollback，且受控
  测试实际覆盖三处窗口。
- factory create、module registration 与 owner-destroy callback handoff 不会遗留未交付 surface；取消路径
  必定执行 abandon，弱 callback 不形成 surface 自持有。
- active VideoView error 仅通过当前 mutation gate 与 binding identity 撤销 attachment；stale error 被丢弃，
  平台 `what/extra` 不进入公共状态或日志。

最终 evidence 显示 Debug/Release 各 63 个测试、0 failures/errors，lint、Debug/Release AAR、`make lint`、
`make harness-check` 与 `git diff --check` 均通过。Robolectric/manual listener 不证明真机 CameraX 出帧、
MediaPlayer 厂商错误时序、权限 UI、硬件中断和性能，这些继续留给 Android Quality Gate。
