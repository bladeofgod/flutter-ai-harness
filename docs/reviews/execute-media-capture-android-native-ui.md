---
task: media-capture-android-native-ui
status: passed
p0: 0
p1: 0
---

# Review: Android Media Capture Native UI

## 首轮结论

独立 Review 首轮为 P0 0、P1 4、P2 1。阻断项包括用 LifecycleOwner 而非 Activity 占位、晚到
`startSession` 泄漏、`collectLatest` 取消 surface transaction、cleanup 异常后仍释放 slot；公开构造器还允许
任意 UI dispatcher。

## 第 1 轮复审

上述问题关闭后，复审仍有 P1 2：后台 `onAppBackgrounded` 失败没有等待已取消的 late action；confirm
commit 后 release 失败只毒化 slot，没有继续持有 lease cleanup ownership。P2 指出 Registry 仍依赖
`WeakHashMap.equals/hashCode`，且独立 LifecycleOwner 不能保证 Activity destroy cleanup。

## 最终复审

当前实现未发现剩余 P0/P1/P2：

- presentation Registry 使用弱引用与 `===` Activity identity；LifecycleOwner 管理可见状态，Application
  Activity lifecycle callback 始终处理真实 Activity destroy。
- start/observation/action/surface transaction 通过原子 gate 与顺序收集协调；后台失败与其他 terminal 路径
  都等待已取消 action，late Session 在释放 slot 前 cancel，超时则保持 slot poisoned。
- confirm cancellation 保留 preview handle。release 先执行短次数退避，仍失败则把 `MediaCapture` 与 handle
  转交 process-owned cleanup scope，以最大 5 秒间隔继续重试至成功或 `media_invalid`；恢复前 Activity slot
  不释放，恢复回调也必须等待 surface/UI terminal cleanup 已完成。
- 生产入口固定 `Dispatchers.Main.immediate`；测试 dispatcher 只存在于 internal 构造器。UI 不 import Flutter、
  Wire Map、CameraX provider、媒体 path/URI 或 raw bytes。

测试新增后台失败 + late start、commit 后首次 release 失败、独立 cleanup owner 接管、Activity 自定义
equals/hashCode、独立 LifecycleOwner 下 Activity destroy，以及原有手势、长按录像隐藏切镜头、surface
generation、旋转、前后台、三终态、无障碍和小屏/横屏/大字号覆盖。

视觉修正后，原生 Chrome 使用固定 112 dp 黑色控制区、80 dp 拍摄键和 98 dp 录像进度环；录像态同时
隐藏闪光与镜头翻转，预览态使用顶部重拍和底部发送确认。外部设计标识与资源没有写入仓库。

独立视觉复审发现的三项 P1 已关闭：录像启动确认前松手会在框架启动后立即停止；对焦监听完整消费
DOWN/MOVE/UP/CANCEL 并用 concrete render child 测试；发送按钮保留 54 x 32 视觉 pill，但使用 54 x 48
点击目标。进度刷新不再每 250ms requestLayout，闪光提示覆盖大字号，默认/中文资源保持同 locale。

## 验证

证据：`docs/reviews/test-evidence/media-capture-android-native-ui.log`。

- Android Debug unit tests：41 tests，0 failures/errors。
- Android Release unit tests：41 tests，0 failures/errors。
- Android lint：通过，warnings as errors。
- Demo Host Debug APK：构建通过。
- `make lint`、`make format`、`make harness-check`、`git diff --check`：通过。

Robolectric/Fake Core 不证明真机 CameraX 出帧、系统 Camera/Microphone 权限框、硬件录像、厂商中断或性能。
这些保留给 Android Quality Gate；本任务未宣称真机通过。
