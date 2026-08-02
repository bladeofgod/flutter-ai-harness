# iOS Media Capture Native UI

iOS 原生拍摄 UI 位于 `app/native/ios/MediaCaptureUI/`。它是一个 iOS 13 起可用的 Swift Package，
由宿主 `UIViewController` 全屏呈现并直接调用 `MediaCapture` Core。模块不依赖 Flutter、Method Channel、
Wire Dictionary，也不接触媒体路径、文件句柄、原始媒体字节或 AVFoundation capture 对象。

## 模块边界

`MediaCaptureUI` 只依赖同仓库的两个产品：

- `MediaCapture`：提供类型化 Session、拍摄操作、confirmed lease、Failure 和 attachment API。
- `MediaCaptureAppleRendering`：提供 Core 控制的 `MediaCaptureRenderView` 与 surface owner。

Presenter 注入的 Core 必须属于当前宿主 capability trust domain，不得与不受信任的 Feature 或 Bridge
consumer 共享同一实例；模块代码可以复用，Session/event handle 的运行时实例不能跨信任域复用。

UI 只组合 Rendering 提供的 concrete view，不创建 `AVCaptureSession`、preview/player layer 或 sample
buffer。相机、编码、App private media、租约和能力状态机仍由 Core 独占。

## 公共入口

宿主通过 `MediaCaptureUiPresenter` 创建流程：

```swift
let presenter = MediaCaptureUiPresenter(
    presentingViewController: viewController,
    core: mediaCaptureCore
)
let flow = try presenter.present(
    configuration: MediaCaptureUiConfiguration(sessionOptions: options)
)
let result = try await flow.awaitResult()
```

presenting ViewController 必须已经位于 window 中且没有正在呈现其他页面。同一个 owner 同时只允许一个
拍摄流程；共享 identity registry 使用 owner identity 和随机 token 管理 slot，并为每次成功预留分配单调
递增的初始 surface generation。清理完成前不会释放 slot。

`MediaCaptureFlowResult` 只有三种终态：

- `confirmed(ConfirmedMedia)`：交付 Core 管理的 confirmed lease metadata。
- `cancelled`：用户主动关闭，是正常结果。
- `failure(MediaCaptureFailure)`：权限、Capability、呈现或系统中断失败，不冒充取消。

`MediaCaptureFlowSession` 只开放等待结果、主动关闭和通知显示旋转，调用方不能直接完成内部 continuation。
`awaitResult()` 是 `async throws` 且每个 waiter 都有独立 identity；调用 Task 取消会移除该 waiter、以
`system_interrupted` 启动一次性 flow cleanup，并向调用方原样抛出 `CancellationError`，不会冒充用户主动
关闭产生的 `.cancelled`。

## 交互与布局

首版使用黑色全屏拍摄画布、白色高对比图标和 Shoppe primary `#004CFF` 的录制进度/确认语义，图标来自
SF Symbols，不复制第三方品牌资源。底部 112 pt 黑色控制区继续覆盖 bottom safe area，相机画面不会从
Home Indicator 区域露出；按钮触控目标至少 48 pt，快门固定为 80 pt。

- 点击快门拍照；长按进入录像，松手或手势取消后停止。
- 录像开始仍在 Core 返回途中时松手，会记录 pending stop，并在 start 成功后立即 stop。
- 录像中纵向滑动以相邻 move 的增量按最新 `SessionReadySnapshot` zoom 范围换算并钳制；zoom 调用在途
  松手会进入 stopping phase，并在 zoom 收敛后立即 stop。
- 点按画面只在 Core 声明支持 focus 时发送 `[0, 1]` 归一化坐标。
- 切换镜头、闪光模式和按钮显隐都来自最新 capability snapshot；录像和预览阶段隐藏不适用操作。
- Core 自动录制时限产生的 preview event 与手动 stop 使用同一去重 preview 路径。
- 预览阶段左上角操作变为重拍，底部蓝色操作确认当前媒体。

所有可操作图标都有本地化 VoiceOver label。快门实现 VoiceOver primary action；混合模式另外提供录像
custom action，录像态 primary action 用于停止。英文和简体中文资源均位于 Package Resources 中。界面不
增加可见教程文案。SF Symbol 使用 iOS 13 可用的 fallback，旧系统不会留下无图标按钮。

## Surface 与生命周期

`MediaCaptureFlowCoordinator` 在 `@MainActor` 上拥有 UI 状态，但所有 Core 调用保持 async，不把相机或
编码工作放到主线程。每次 live/preview 初次 attach、替换、旋转或前台恢复都会创建新的
`MediaCaptureRenderSurfaceOwner` 和严格更高的 generation；旧 surface 在新 attach 前退休并从层级移除。

拍摄 action、event surface transaction 与 lifecycle task 分开跟踪，但共享一个 MainActor 准入门。旋转或
后台入口先提升 lifecycle generation、原子关闭普通 transaction 准入并取消/有界等待旧 action 与 event
attach，再通知 Core 退休 render；后到 event 排队等待 lifecycle，后到用户 action 在恢复前被拒绝，
因此被本次 lifecycle 淘汰的 `CancellationError`/`invalid_state` 不会冒充 terminal failure。已经产生媒体的
action 恢复 preview，失败的 capture/start 恢复 live，stopping recording 在恢复后继续 stop。前台或旋转按
最新 live/recording/preview phase 创建 fresh surface，旧 task 不能清除新任务所有权。

切换镜头期间 UI 进入 busy，Core 提交新镜头后用新的 `sessionReady` 更新 flash、focus 与 zoom 能力，
随后才恢复 action 准入。平台成功返回是不可回滚的切换提交点；旋转取消上层 action 后，如果切换已经
提交，UI 保持 `.switchingCamera` 且不抢先挂载旧能力对应的 surface，等新 `sessionReady` 排队完成后再用
fresh generation 恢复 live。event 已从 stream 取出但仍等待 action 收口时，lifecycle cancellation 会保留并
在 lifecycle 完成后重放该 event，不会消费掉唯一的新 snapshot。只有 `.off` 时不显示闪光控制。retake
即使在后台等待期间晚成功，也会先
清空旧 preview handle 并提交 live phase，surface 延迟到前台用新 generation 恢复。

ViewController 绑定当前 `UIWindowScene` 的 background/foreground notification，并按 scene object identity
过滤；window 尚无 Scene 时才使用 UIApplication fallback。scene 替换会移除旧 observer 后重新绑定。

用户 dismiss、owner 销毁、Session failure、确认和系统中断共用一次性终态：关闭事件与进度任务，取消并
有界等待 action/lifecycle/event transaction，再分别有界等待 surface detach、Session cancel、late lease
release 与 UIKit dismissal。每项 cleanup 未在 5 秒内收敛时公开结果仍可完成，但 presentation slot 保持
poisoned；进程级 cleanup owner 持有完整 surface owner、Session/Media handle 与 Core capability，以有界
退避重试明确可恢复的 cleanup。Media release 只对 Core 的 `invalid_state` 重试；`media_invalid` 和其它
非 retry allowlist 结果视为永久收口，立即释放 deferred hold，避免 closed/restarted/expired 媒体无限持有
slot。`startSession` 在终态后晚返回也走同一 Session 接管路径。UIKit
dismissal 同时观察 completion 与实际 presentation 关系，未完成时同样不释放 slot。晚到 lease 不会静默
丢失或记录 handle。

## 自动化验证边界

Simulator XCTest 使用 Fake Core 覆盖点击/长按/增量滑动、start/zoom 在途松手、自动时限 preview、三种
终态、权限失败、重复 preview 去重、镜头能力变化、后台 retake、lifecycle-first/action-first/event attach
竞态、fresh generation、detach/cancel/release/dismiss 各自的 5 秒 timeout、release 永久终态不重试与
暂时 `invalid_state` 恢复、各类单独失败、late
Session/lease、slot poison/recovery、event
operation timeout 后取消父订阅、event stream 异常结束、ViewController deinit、public presenter、dismiss
completion 顺序、并发 owner registry、配置对象 identity/
Scene 或 UIApplication fallback、公开 result waiter cancellation、safe area、窄屏/横屏、图标非空与 fallback
配置和 VoiceOver 实际 action。
generic iOS Simulator SDK build 另外验证 UIKit、iOS 13 deployment target 与 Core Package 依赖。

这些自动化结果不代表真实硬件验收。以下内容留给最终 iOS 真机 Gate：

- Camera/Microphone 系统权限弹窗与拒绝后恢复。
- 实时相机画面、前后镜头、闪光、对焦和缩放手感。
- 照片与视频真实编码、自动时限、预览与音频。
- 横竖屏、后台/前台、来电或相机被占用时的硬件时序。
- 长时间录制的温度、内存、文件系统错误和性能。
