---
task: media-capture-ios-native-ui
status: passed
p0: 0
p1: 0
---

# Review: iOS Media Capture Native UI

## 首轮结论

独立只读 Review 首轮为 P0 0、P1 7、P2 3，当前不能归档。现有 14 个 Simulator XCTest、generic iOS
Simulator build 和模块边界扫描通过，但没有覆盖以下阻断竞态和可达性行为。

## P1 发现

1. zoom action 在途时松手只设置 `pendingRecordingStop`，该标记只在 start-recording action 收口时消费；
   zoom 完成后可能持续录像到自动时限。手势每次上报相对起点总位移，coordinator 却叠加当前 zoom，连续
   move 会重复累计。
2. rotation/background 在 action 或 event surface transaction 仍执行时先调用 Core lifecycle，可能使旧
   operation 返回 `invalid_state` 并被误报 terminal failure；action、event 与 surface replacement 缺少共同
   transaction 仲裁。
3. terminal cleanup 无上限等待不合作 action/lifecycle；detach/cancel 失败仍释放 presentation slot；晚到
   lease 的无限同步 retry 又可能让 dismiss/result 永不完成。
4. ViewController 监听全 App 的 `UIApplication` background/foreground，而非当前 `UIWindowScene`；多窗口
   下当前 Scene 单独进入后台时不会及时撤销相机 surface。
5. 快门只绑定 tap/long-press gesture，`CaptureShutterButton` 没有 VoiceOver primary/custom action；视频模式
   即使读出 Record 也不能可靠开始/停止。
6. Fake 与测试缺少 zoom-release、in-flight lifecycle/surface、cleanup poison/recovery、Scene notification、
   public presenter/window、真实 safe-area 和 VoiceOver action 覆盖；文档对覆盖范围的描述超出现有事实。
7. 证据命令仍包含完整 Simulator UUID；输出虽然脱敏，command redaction 没有处理 destination ID。

## P2 发现

- SF Symbols 缺少 iOS 13 fallback，旧系统上图标可能为空。
- focus capability 不支持时，点按仍先显示 focus indicator，产生虚假成功反馈。
- 录像展示进度使用 wall-clock `Date`，会受系统时间调整影响。

## 既有验证

[`test-evidence/media-capture-ios-native-ui.log`](test-evidence/media-capture-ios-native-ui.log) 记录修复前
14 个 XCTest 和 generic Simulator build 通过，也保留前序 scheme、actor isolation 与测试构造失败。
这些成功结果不关闭上述 finding。真机权限弹窗、硬件采集、中断和性能按用户安排留到最终验收，不作为
本轮 P1。

## 第一轮修复

- Gesture 改为相邻 move 增量；coordinator 增加 stopping phase，start 或 zoom/focus action 在途松手都会在
  action 收口后立即 stop。自动 preview event 也先取消并有界等待 recording action，再进入单一 surface
  transaction。
- rotation/background 先提升 generation、取消并最多等待 action/event attach 5 秒，再调用 Core lifecycle；
  被本次 lifecycle 淘汰的 failure 不进入 terminal。成功产生的 photo/stop 恢复 preview，失败的 capture/start
  恢复 live，stopping 在 foreground/rotation 后继续。
- terminal 同时跟踪 action/lifecycle/event task。5 秒未收敛、Session cancel 失败或 late lease release 失败
  时公开结果仍完成，但 slot 保持 poisoned；进程 cleanup owner 持有任务/Core capability 并退避重试，恢复
  后以一次性 gate 释放 slot。
- lifecycle observer 绑定当前 UIWindowScene，使用 object identity 拒绝旧 Scene 通知；没有 Scene 才启用
  UIApplication fallback。observer identity/rebind 与 public presenter fallback 均有直接测试。
- VoiceOver 快门实现 primary action，混合模式提供录像 custom action，录像态 primary action 停止；focus
  indicator 只在 capability 接受调用时显示。SF Symbol 增加 iOS 13 fallback，录像进度改用 system uptime。
- Fake 增加 photo/zoom/attach gate 和 detach/cancel/release failure 注入；测试扩展到 blocked zoom release、
  automatic preview/zoom、action/event 与 lifecycle 竞争、timeout、slot poison/recovery、Scene identity、
  public presenter/window、safe area 和实际 VoiceOver action。
- 最终 evidence 使用 Simulator 名称重录，命令和输出均不含设备 UUID。

## 修复验证

第一轮修复后的 [`test-evidence/media-capture-ios-native-ui.log`](test-evidence/media-capture-ios-native-ui.log)
曾记录：

- MediaCaptureUI Simulator XCTest：30 tests，0 failures，0 skipped。
- generic iOS Simulator SDK Debug build：通过。
- Flutter/Channel/AVFoundation/path/raw bytes/强制类型与 detached task 边界扫描：通过。
- `make lint`：通过。

本节只记录执行者修复与命令事实；frontmatter 仍保持首轮 failed，等待独立 Reviewer 复审。

## 第二轮独立复审

独立 Reviewer 对第一轮修复给出 P0 0、P1 3、P2 1，仍不可归档：lifecycle 调度后仍可准入新 action 或
`sessionReady` event；detach 和晚到 `startSession` 的失败/无限等待没有完整接管；测试把 detach failure 与
cancel failure 混在一起且未证明前台重连；result/slot 只等待一次 `Task.yield()`，没有等待 UIKit dismissal。

## 第二轮修复

- action、event operation 与 lifecycle 共享原子准入门。lifecycle-first 时用户 action 被拒绝，event 在
  lifecycle 完成后执行；event operation 在开始前登记，因此生命周期可以取消并有界等待它。
- surface detach、Session cancel、late Media release 和 UIKit dismiss 分别执行有界 settle。超时或瞬时
  失败时完整资源身份由进程 cleanup owner 持有，slot 继续 poisoned；晚到 `startSession` 也不会丢失
  Session handle。
- attach 后取消/失败会尝试 detach；终态不再 `try?` 丢弃 surface 错误。UIKit dismissal 使用 completion
  信号和 presentation 关系共同确认，未完成时公开结果仍有界返回但 slot 不开放。
- 新增 lifecycle-first action/event、仅 detach failure、blocked detach、late Session cancel failure、
  foreground reattach 和 dismissal completion/slot 顺序测试；cancel failure 测试不再混入 detach failure。
- 非主动取消的 Core event stream 结束会进入 `system_interrupted` 终态并清理 Session，不再留下静默失联
  的拍摄页面；event operation timeout 同时取消父订阅，不会回到长期 `for await`；增加两条直接回归。
- 最终 evidence 已按当前快照重录：36 个 Simulator XCTest、generic iOS Simulator Debug build、模块
  边界扫描与 `make lint` 全部通过，命令和输出均通过脱敏检查。

安全复审在旧 evidence 上给出 P0 0、P1 0、P2 1：event operation timeout 后父 `for await` 订阅可能
继续存活。该 P2 已通过 timeout 路径显式取消 `eventTask` 及 `onTermination` 断言关闭。frontmatter 在最终
普通复审和最终 Security Review 绑定当前实现摘要前继续保持 failed。

## 第三轮独立复审

独立 Reviewer 给出 P0 0、P1 3、P2 0：Core 切镜头成功后没有发送新 capability snapshot，UI 会继续使用
旧镜头 flash/focus/zoom；retake 在后台晚成功时没有清空已删除 preview；文档声称 blocked
cancel/release/dismiss timeout 已覆盖，但当时只有 blocked detach 测试。

## 第三轮修复

- Core 在切镜头成功提交后发送新的 `sessionReady`；UI 切换期间保持 busy，并在新 event 应用后才恢复
  action。Fake 让前置镜头只支持 flash off、无 focus、zoom 最大 2，测试证明旧 capability 不再可调用。
- retake 成功后无论当前是否后台都先清空 preview 并提交 live；仅 surface attach 延迟到前台。非合作
  retake gate 覆盖 background、晚成功和 fresh live generation。
- 新增 blocked cancel、blocked late release、blocked UIKit dismissal 三条短 timeout 测试，逐项断言
  result 已完成、slot 仍 poisoned、gate/completion 收敛后 slot 恰好恢复。文档覆盖描述与测试对齐。
- evidence 重录时进一步暴露 VoiceOver action 在 surface event 刚 attach、transaction 尚未清空时可能
  虚报成功。拍照/录像/停止现返回真实准入结果，VoiceOver 只在 action 已提交时返回 `true`，对应测试按
  该行为等待。
- 交叉复核又将镜头切换从初始 `.starting` 拆为 `.switchingCamera`；旋转取消未提交 switch 时明确恢复
  live 并重新 attach，避免 UI 停在 busy。增加 blocked switch/rotation 回归。
- 当前 evidence 记录 MediaCaptureUI 42 个 Simulator XCTest、generic iOS Simulator Debug build、边界
  扫描与 `make lint` 全部通过；Core evidence 记录 88 个 XCTest 和 Core/Rendering generic build 通过。
  frontmatter 在最终独立复审前继续保持 failed。

## 最终独立复审

最终独立 Reviewer 确认镜头 capability 更新、`.switchingCamera` 仲裁、旋转竞态、后台 retake，以及
blocked cancel/release/dismiss 均已闭合，代码行为 P0 0、P1 0。必要的 Core 修复已拆为独立
`media-capture-ios-camera-switch-correction` 任务，不再越过本任务所有权；UI Security Review 摘要也已按
最终 42 项 evidence 和当前实现刷新。最终 P0 0、P1 0、P2 0，可以归档。

## 公开结果等待的取消竞态修复

后续 Security Review 发现公开 `awaitResult()` 的调用 Task 可能在 cancellation handler 安装与 waiter
登记之间取消：旧实现会先从 `Task.checkCancellation()` 抛出，但按 UUID 清理的 handler 尚找不到 waiter，
因此调用方收到 `CancellationError` 时 flow cleanup 可能没有启动。

最终实现把“已有结果、已取消、登记 waiter”收敛到 cancellation handler 内的同一个 MainActor 同步区间，
登记前不再存在绕过 `onCancel` 的抛错点。登记前取消由 continuation 闭包直接触发一次
`system_interrupted` cleanup；登记后取消与 `complete` 按 UUID 串行竞争，只有取得 continuation 的一方可
恢复。已完成结果保持优先，不会因调用 Task 已取消而被覆盖。

新增三条底层确定性回归，覆盖登记前取消、已完成结果优先和多 waiter identity 隔离；既有 public
presenter 回归继续证明已登记 waiter 取消后 Session cancel、surface detach、event subscription termination
和 presentation slot 恢复。当前 evidence 记录 47 个 Simulator XCTest、generic iOS Simulator Debug
build、模块边界扫描与 `make lint` 全部通过。最终独立普通复审为 P0 0、P1 0、P2 0，可以进入归档门禁。
