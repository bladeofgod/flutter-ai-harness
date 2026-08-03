# iOS Media Capture Native Core

> 实现状态：Core、Apple Rendering、Native UI、V4 Export Bridge、专项 Gate 与真实 Demo SwiftPM Host 接线已完成；真机系统能力证据待人工验收。

[返回 Media Capture 公共能力](./media-capture.md)

## 模块与依赖

iOS 模块位于 `app/native/ios/MediaCapture/`，采用 iOS 13、Swift 5 语言模式、本地 Swift Package 和
Apple Framework。Package 同时提供 transport-neutral 的 `MediaCapture` Core product 与 UIKit
presentation `MediaCaptureAppleRendering` product。纯原生消费者直接依赖所需 product；模块不 import
Flutter，不读取 Wire Dictionary，也不依赖 Host 类型。

本模块只保留 SwiftPM 路线，不提供 Podspec。Bridge Adapter 通过仓库相对路径依赖该 Package product；
Host 只负责权限文案和标准 Plugin 装配，不接管 Session/Media 状态机。

内部依赖仅包括 UIKit、AVFoundation、CoreGraphics、ImageIO、MobileCoreServices、Security 和 Foundation，
没有第三方依赖。Core public symbol 不出现 UIKit、AVFoundation、URL 或 CALayer；capture session、capture
input/output、delegate、文件 URL、CGImage、AVAsset、layer 和 player 都只在 target 内部或 Swift
`package` 边界可见。每个异步公共 operation 在 actor 内取得独立 operation generation；任何
AVFoundation、文件或 MainActor `await` 返回后都必须同时核对 generation、当前状态和 module lifecycle
epoch，旧结果不能覆盖 cancel、timeout、interruption、background、rotation 或 restart 已提交的状态。
模块另外维护 capture-resource lifecycle phase。Session terminal cleanup 使用 `tearing_down` phase，App
restart 使用 `restarting` phase；旧 Session 的平台 stop、delegate、render、partial file 和 registry cleanup
完成前拒绝新 Session 与普通 operation，避免旧 cleanup 停止新 Session 的平台资源。

## 公共 API

`MediaCaptureCore` 是 actor，公开 API 使用 `SessionHandle`、`MediaHandle`、`SessionOptions`、
`MediaMetadata`、`ConfirmedMedia`、`MediaThumbnail`、`MediaCopySink`、`MediaCopyChunk`、
`MediaExportResult`、`MediaCaptureEvent` 和
`MediaCaptureFailure` 等 Sendable 值。异步操作使用 `async throws`，事件使用 `AsyncStream`；外部 Task
取消默认保留 `CancellationError`；V4 流式导出按 Capability 明确映射为可恢复的
`media_export_cancelled`，不会冒充用户取消拍摄或 terminal Session Failure。

Session handle 与 Media handle 都由 Security Framework 的 CSPRNG 生成 128-bit 随机值。handle 只参与
actor registry 的严格查找，不参与文件名或路径拼接；实例内已经发出的值即使 tombstone 清除也不复用。

Session 由 Core 单独拥有，同一实例只允许一个活动 Session。`startSession` 立即返回可取消 handle，再由
event 交付 ready snapshot 或 terminal failure。拍照、带声/静音录像、镜头切换、闪光、对焦、缩放、
重拍、确认和取消都先验证当前 registry state；非法参数不改变状态。确认结束 Session，但确认媒体的租约
由独立 Media registry 继续持有，因此不会阻止下一次拍摄。

一个 `MediaCaptureCore` 实例就是单一 capability trust domain。它的 event stream 会向该实例内订阅者广播
opaque Session/Media handle，因此 Host DI 不得把同一实例共享给互不信任的 Feature、Native UI 或 Bridge
consumer；需要隔离时必须创建独立 Core 实例。共享模块实现不等于共享运行时实例。

镜头切换的平台调用成功返回就是不可回滚的提交点。即使调用方此时已取消，Core 仍会提交并发送新的
`sessionReady`，其中包含新镜头的 flash、focus 与 zoom 范围，避免物理摄像头与 registry snapshot
分叉。纯 render rotation/background 引起的 lifecycle epoch 变化也不能丢弃已提交切换；Session 已取消、
终止或 operation generation 已被替代时仍拒绝写回。Native UI 必须等该 snapshot 再开放控制，不能沿用
上一镜头的能力状态。Core 同时把拍照 flash mode 重置为新 snapshot 支持的默认值，避免 UI 显示关闭而
后续照片仍沿用旧镜头的 `.on`、`.auto` 或 `.torch`。

Native 原始读取使用 `withMediaRead`。回调只拿到模块定义的 `MediaReadAccess`，可以读取 Data、实际长度与
MIME，但拿不到路径、URI 或文件描述符；内部使用模块持有的 FileHandle 分块 source，并在每块读取前后检查
revoke 与 Task cancellation。生产 backend 的 POSIX throwing read 与 FileHandle close 共用同一把锁，descriptor
不会被两个并发调用同时访问。回调返回、抛错、取消或 read grace 到期时 Core 都关闭 handle；grace 清理会
先撤销/关闭进行中的读取，完成 source 关闭，再删除文件并发事件。该 API 只服务直接原生消费者，Bridge
不得把它映射为 Flutter 原图读取。

## 权限与 AVFoundation

- Camera 只在明确调用 `startSession` 后检查或请求。
- Microphone 只在 `audioEnabled` 的录像真正开始时检查或请求；拍照和静音录像不请求。
- Photo Library 不属于能力范围，模块没有任何相册权限调用。
- iOS `.denied` 映射为 `permanently_denied`，`.restricted` 映射为 `restricted`；不虚构系统不存在的再次弹窗能力。
- AVCaptureSession 在模块私有串行队列配置和启停。每次 photo/movie operation 使用独立 UUID、delegate 和
  exactly-once completion；stop/cancel/close 会请求停止并等待对应 operation 完成，再按 identity 移除，
  后到的旧回调不能完成新 operation。Session 必须先 commit configuration，再调用 startRunning；close 会
  显式注销 NotificationCenter observer。
- photo 只在最终 `didFinishCaptureFor` 提交底层 completion；movie 只在最终 recording callback 提交。
  调用者取消会请求对应 operation 停止，但仍等待底层 exactly-once completion，再传播 `CancellationError`。
  视频净化 export 同样由 cancellable operation 包装 `cancelExport` 和最终 export callback。
- 系统 interruption/runtime error 映射为 `system_interrupted`，与用户 `cancel` 分离。

真实 Demo Host 已声明 `NSCameraUsageDescription` 与 `NSMicrophoneUsageDescription`；Camera 仍只在用户
主动进入拍摄时请求，Microphone 仍只在带声录像时请求。Core 初始化不会弹权限，也不修改 Info.plist 或
Entitlements。

## 文件、租约与清理

媒体文件只存在于 App 私有 temporary 模块父目录下的实例隔离子目录，物理所有者始终是对应 Core。进程内
registry 保护所有 active store root；启动清理只删除未注册的旧实例残留和当前实例 root，不会删除另一
Core 的 active lease。照片在进入 preview registry 前通过 ImageIO 物理旋转并重新编码 JPEG；视频先创建
只复制 video/audio 时间段、相对共同时间原点的 track offset 与方向变换的新 `AVMutableComposition`，不复制
源 container/track metadata，再通过 AVAssetExportSession 和 sharing filter 输出 MP4 副本。尺寸、方向和
时长从净化后的输出重新读取并校验；公共 metadata 不包含文件名、路径、位置或设备信息。

未确认 preview 的 TTL 固定 600 秒。confirm 后逻辑 lease 固定 86400 秒；显式 release 或 lease 到期会
立即拒绝新读取，并给既有原始读取最多 60 秒 grace。grace 结束后 Core 强制关闭读取、删除文件，再进入
released/expired tombstone；Session 与 Media tombstone 都固定保留 300 秒。重复 stop、cancel 和 release
复用既有结果，不延长 TTL、grace 或 tombstone。

`releaseMedia` 使用既有 Failure ID 区分 cleanup 终态：active lease 进入 `releaseGrace`，已在
`releaseGrace`/`released` 时幂等成功；capture teardown 或 App restart 尚未完成时返回可重试的
`invalid_state`；expiry/expired/discarded、restart 清空后的旧 handle 以及 closed Core 返回不可恢复的
`media_invalid`。因此 Native UI 可以只重试明确的 `invalid_state`，不会因已由 Core 接管或清除的媒体
无限持有 handle、Task 或 presentation slot，也不需要新增单平台 Failure。

App restart 和 Core close 会先使 thumbnail/export job 与 render generation 失效，再停止 callback、关闭读取、
等待 AV delegate、decoder 与 export worker，丢弃未完成录像 destination、删除临时媒体并清空 registry。
restart 后旧 handle 只能得到 `session_invalid` 或 `media_invalid`。

## 有界流式导出

`copyConfirmedMediaToSink` 只接受 active confirmed lease、调用范围内的 typed `MediaCopySink` 与
`1...52428800` 的最大长度。照片固定为 `image/jpeg`，净化视频固定为 `video/mp4`；其它 MIME、未知 handle、
非 leased 状态和过期 lease 在打开 source 或调用 sink 前拒绝。成功只返回 handle、媒体类型、MIME 与实际
长度，不返回路径、URL、FileHandle、sink identity 或媒体 bytes，也不会自动 release 或刷新 source lease。

Core 在打开 source/sink 前原子预留 export job。每个 Media 最多 1 个、每个 Core 最多 4 个；每个 job 固定
预留 262144 bytes，总预算 1048576 bytes。生产读取在注入的并发 Dispatch executor 中使用 131072-byte Data，
sink callback 使用另一份最多 131072-byte 的 `MediaCopyChunk`；callback 返回后 chunk 立即 wipe 并失效。
consumer 若需要持久化 bytes，必须在 callback 内通过 `copyBytes()` 建立自己拥有的有界副本。复制逐块检查
累计长度，EOF 后再次要求实际长度等于 source metadata；截断、增长、声明超限都返回
`media_export_too_large`，不截断、不补齐也不静默降质。

每个 job 从 reservation 起固定 120 秒 deadline。caller cancellation、deadline、release、lease expiry、
restart 和 Core close 共用同一个线程安全终态仲裁与 callback gate。成功 begin 后的失败路径 abort sink
恰好一次；commit 与 abort 互斥。`commit` 正常返回是目标已发布的线性化成功点，返回后才登记的取消不能
把已发布目标改报失败；若取消先被 `commit` 观察到，则 sink 必须在发布前抛错并保持可 abort。Core 会取消
并等待 tracked worker、关闭 source、wipe chunk、释放预算，
最后注销 job；晚到 callback 不能再次 commit。稳定 Failure 仅使用 `media_export_conflict`、
`media_export_overloaded`、`media_export_too_large`、`media_export_sink_rejected`、
`media_export_read_failed`、`media_export_write_failed`、`media_export_cancelled`、
`media_export_timed_out` 以及共享的 handle/state/argument/Core-close Failure，不暴露底层错误文本。

`MediaCopySink` 是显式的同进程事务信任边界。四个 callback 都必须响应 structured cancellation 并在 5 秒
内收敛；`commit` 观察到取消时必须在发布不可逆目标前抛错，并保持 begun target 可由 `abort` 丢弃。
Core 会丢弃晚到结果并执行一次 abort，但无法撤销违反上述协议、已在自身实现中不可逆提交后仍返回成功的
consumer sink；这种 sink 不符合 Capability conformance，不能作为受支持消费者。

## Native Render attachment

Native Consumer 先创建只包含 owner generation 的 transport-neutral
`MediaCaptureRenderSurfaceOwner`，再由 `MediaCaptureRenderSurfaceFactory` 生成非空且全新的
`MediaCaptureRenderView: UIView`。同一 owner 不能重复生产 surface，非法 generation 或重复 factory 调用在
Core attachment registry 变更前被拒绝。Consumer 只持有 outer view 生命周期与 owner，不接触 backing layer、
source、renderer、mount endpoint 或 binding。

这里的闭合边界是公共 API、所有权和跨 Runtime 边界，不把同一 App 进程内的 UIView/layer tree 当作安全
沙箱。模块不会通过类型化 API、Channel、日志或 callback 交付内部对象；Native consumer 也不得遍历或修改
outer view 的实现 sublayer。已经能在 App 进程内执行任意代码的恶意依赖仍可检查 layer tree、截屏或反射
进程内对象，这属于 Host 供应链与进程完整性边界，不能由 UIView 子类提供机密性隔离。

`MediaCapture` 与 `MediaCaptureAppleRendering` 两个 target 只通过 Swift `package` access 共享强类型
`MediaCaptureRenderSource`、`MediaCaptureRenderMountEndpoint`、`MediaCaptureRenderBinding` 和 callback gate；
不使用 `_spi`、弱类型对象、空 token 或 runtime downcast 传递平台资源。live source 实际安装
`AVCaptureVideoPreviewLayer`；photo 在非 MainActor 文件执行域先解码为净化后的 CGImage，再安装 content layer；
video 创建 AVPlayer 与 `AVPlayerLayer`。Core registry 强持有 source、endpoint 与 binding，只弱持有 surface
owner；具体 endpoint 的闭包也只弱持有 outer view，Core 不会延长 Consumer view 生命周期。

install gate 与 commit 后 callback gate 分离：前者在 layer/player mutation 前后核对 active scope、concrete
surface identity、owner generation 与 lifecycle epoch，同时允许 binding 尚未 commit；后者只允许已经 commit
的当前 binding 执行异步 callback。Core 在读取 source 或调用 endpoint 前先登记 pending reservation 和 gate；
替换、旋转、后台、owner deinit、Session terminal、restart 与 close 会同时失效 pending/committed gate。
清理期间 slot 保持 reservation，依次断开 preview session/player source、移除 sublayer、清空 photo content、
完成 detach callback，最后才清理 binding state 并允许下一次 mount。被替换或 retired generation 的后到结果
不能再次修改 surface。

live Session 和未确认 preview 分别持有单调 generation high-watermark，同一 scope 最多一个 binding：

1. 新 generation 必须严格大于 high-watermark。
2. Core 先原子推进 high-watermark 并登记 pending gate；旧 target 完整 revoke/detach 且 registry 最终清理后，
   才允许新 target mount 并提交结果。
3. 当前 generation 与 adapter instance identity 都相同时才幂等；同 generation 换 adapter 返回
   `attachment_target_conflict`。
4. retired generation 返回 `attachment_generation_retired`，不能影响当前 binding；detach 也必须同时匹配
   generation 和 instance identity，否则是保持当前 binding 的 no-op。
5. 停止录像先立即向 `AVCaptureMovieFileOutput` 发出 stop 请求，并与 Live Preview revoke 并发收口；
   两者完成后才净化并提交 preview，Surface 清理不能延长录像时长。拍照、重拍、确认、取消、失败、超时、
   旋转、后台、owner destroy、restart 和 close 仍先撤销相应 attachment，再处理状态或媒体所有权。

前台恢复和旋转后必须由新 UI owner generation 显式重新 attach，Core 不保留已经销毁的 UI owner。

## 受限缩略图

`readMediaThumbnail` 只接受 active confirmed lease 与 `64...512` 的最大边长。Core 在访问 source 前登记
managed job；每个 job 强持有独立 decoder Task、CancellationSignal、source、原子 first-winner arbiter 和
可擦除 generation buffer。ImageIO 从第一份 JPEG output 起直接写入可擦除 owner；每个降质/缩放 candidate
在重试、取消和失败前显式 wipe，只有成功 candidate 才能转交 Core。每个 Media 最多 1 个、每个 Core 最多 2 个 job，每个 job 预留 8 MiB working
budget，模块总预算 16 MiB。ImageIO 使用 decode-time thumbnail subsampling；视频
AVAssetImageGenerator 在取帧前设置 maximumSize。输出像素不超过 512 x 512，也不超过请求边界。

输出是 caller-owned 的独立 upright JPEG Data，最多 524288 bytes，方向固定 0。ImageIO 重新编码会移除
EXIF、GPS、设备、原始文件名和其它非展示 metadata。照片的 poster time 为 nil；视频 target 是
`min(1000, floor(durationMillis / 2))`，优先 target 或之后最近可解码帧，没有时选择之前最近帧，并返回
实际帧时间。

result commit、release、lease expiry、restart、caller cancel 和 decoder failure 共用线程安全的原子 first
terminal winner；Task cancellation handler 会同步提交 caller-cancel winner 并取消 tracked worker。成功先赢
时，Core 先复制出独立 caller Data，再关闭 source、释放 decoder/pixel 对象、
擦除 module generation buffer，最后注销 job；后续 source release/expiry 不能修改 caller copy。其它 winner
先撤销 source、取消并等待 generator、关闭 source、释放 decoded pixels、擦除 generation buffer、丢弃
partial copy，最后注销 job，再交付唯一 outcome。底层 decoder error 不进入公共 Failure。

## 测试与证据边界

`Tests/MediaCaptureTests/` 使用窄 CapturePlatform、FileStore、Clock、HandleGenerator、Render endpoint 和
ThumbnailGenerator Fake 覆盖状态机、权限时机、operation Failure allowlist、非法输入、幂等、actor 竞态、
租约/grace/tombstone、release 与 confirm teardown/restart/close/expiry 的永久或暂时终态、
teardown/restart 对新 Session 的 gate、阻塞读取强制撤销、production read/close
串行、真实文件删除、partial recording 删除、photo/movie/export cancel-and-await、delegate/observer cleanup、
concrete surface 全链路 replacement/stale generation、rotation/background/restart/双类 owner destroy、thumbnail
budget/first-winner/cancel-and-await/JPEG retry buffer wipe、poster 选择、照片 metadata 净化、真实输入 MOV
到净化 MP4 的 container/track 位置与设备 metadata 清除，以及 V4 export 的 50 MiB 边界、长度漂移、
4-job/1-MiB 预算、sink/source failure、取消、deadline、release/expiry/close 和 exactly-once cleanup。
`Tests/MediaCaptureAppleRenderingTests/` 直接核对真实 layer tree、live session/photo content/video player source
binding、fresh factory 与 revoke/detach 清空。`Tests/MediaCapturePublicConsumerTests/` 是独立 SwiftPM test
target，普通 import 两个 product 并创建 concrete surface，不使用 `@testable`、Flutter 或 Wire model。

iOS SDK 编译命令：

```bash
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCaptureAppleRendering -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
```

可以使用 iOS Simulator SDK triple 的 `swift build --build-tests` 补充验证所有 product 与 test target 的编译，
但 SwiftPM 不能在 macOS 进程内执行 iOS Simulator test bundle，也不能替代上述两条 generic destination
`xcodebuild`。只有可用 Simulator destination 才能运行 XCTest。

Target 测试命令在已安装且可用的 Simulator 上执行：

```bash
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -configuration Debug CODE_SIGNING_ALLOWED=NO test)
```

Framework Fake 和 Simulator 只能证明模块编排、iOS SDK 链接与支持的 Apple API 行为，不能证明真机 Camera、
Microphone 授权 UI、硬件 interruption、编码性能或内存峰值。大尺寸照片/视频、真实系统权限、硬件中断和
持续性能仍由 iOS quality gate 在明确真机上留证。
