---
task: media-capture-android-bridge-adapter
status: passed
p0: 0
p1: 0
---

# Review: Android Media Capture Bridge Adapter

## 审查闭环

独立普通 Review 首轮为 P0 2、P1 6、P2 1。阻断项包括 opaque handle 被错误限制字符集、Presenter
从 worker 调用、presentation slot 提前释放、cleanup 失败丢失所有权、资源编码先于纳管、event/Engine
scope 泄漏、Flutter terminal callback 与 boundary 竞态，以及 Native 返回资源缺少身份关联校验。

修复后复审仍发现 P1 2、P2 1：Engine detach 后 late confirmed lease 错误等待已关闭事件流的 revoke；cleanup
worker 的退出检查与 Job 清空存在丢任务窗口；dead Activity 的 Presenter 异常被误报为 presentation
conflict。三项均已关闭，并新增 direct/presentation late confirmed、dead/live owner 和 cleanup retry 测试。

最终独立普通复审为 P0 0、P1 0、P2 0。当前实现确认：

- command/event control 在 StandardMethodCodec 解码前有固定 byte 上限，随后执行闭合 Wire V2 校验；
- Presenter、dismiss、Flutter result 和 Event sink 都在 main dispatcher，terminal adoption/completion 与
  boundary 使用同一 coordinator 线性化；
- Session、Preview、lease、settling handle 和返回身份在交付前校验，编码失败与 late result 进入清理；
- Activity replacement 等待旧 presentation/in-flight/cleanup drain，但保留已交付 Engine lease 并路由到
  原 Core；Engine detach 等 late cleanup、Core close、collector 取消和 terminal callback 后取消 scope；
- cleanup 失败保留 owner/handle，以有界退避继续重试；权限 callback 核对 request code、权限名和数组结构；
- Android Event control 直接实现标准 listen/cancel wire protocol，重复 listen 不再被平台 wrapper 隐式替换。

## 验证

证据：`docs/reviews/test-evidence/media-capture-android-bridge-adapter.log`。

- Android Debug unit tests：35 tests，0 failures/errors。
- Android Release unit tests：35 tests，0 failures/errors。
- Android lint：通过，warnings as errors，检查 Core/UI dependency。
- 强制命令使用 `--rerun-tasks`；251 个 Gradle task 全部执行并通过。
- `make lint`、`make format`、`git diff --check`：通过。
- 后续 Android 平台 Gate 发现 `activity-ktx` 没有生产消费者；移除该直接依赖后，上述 35/35 测试与
  251 个 Gradle task 已重新强制执行并通过。

JVM/Robolectric/Fake 不能证明 Flutter Host 自动注册、真实 Activity presentation、CameraX 帧、系统权限框、
硬件录制、中断和设备性能。上述缺口保留给 Android Quality Gate 与最终跨 Runtime Integration。
