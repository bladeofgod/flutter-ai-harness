# iOS Media Capture Native Core

> 实现状态：Core、Apple Rendering product 与 Framework Fake 已实现；Host、Bridge Adapter、Native UI、mandatory Xcode 平台门禁、模拟器运行证据和真机系统能力证据仍待对应任务或可用环境完成。

[返回 Media Capture 公共能力](./media-capture.md)

## 模块与依赖

iOS 模块位于 `app/native/ios/MediaCapture/`，采用 iOS 13、Swift 5 语言模式、本地 Swift Package 和
Apple Framework。Package 同时提供 transport-neutral 的 `MediaCapture` Core product 与 UIKit
presentation `MediaCaptureAppleRendering` product。纯原生消费者直接依赖所需 product；模块不 import
Flutter，不读取 Wire Dictionary，也不依赖 Host 类型。

本模块只保留 SwiftPM 路线，不提供 Podspec。后续 Bridge Adapter 必须通过仓库相对路径依赖该 Package
product，Host 只负责权限文案、生命周期转发和装配，不接管 Session/Media 状态机。

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
`MediaMetadata`、`ConfirmedMedia`、`MediaThumbnail`、`MediaCaptureEvent` 和
`MediaCaptureFailure` 等 Sendable 值。异步操作使用 `async throws`，事件使用 `AsyncStream`；外部 Task
取消保留 `CancellationError`，不会伪装成用户取消结果或普通能力 Failure。

Session handle 与 Media handle 都由 Security Framework 的 CSPRNG 生成 128-bit 随机值。handle 只参与
actor registry 的严格查找，不参与文件名或路径拼接；实例内已经发出的值即使 tombstone 清除也不复用。

Session 由 Core 单独拥有，同一实例只允许一个活动 Session。`startSession` 立即返回可取消 handle，再由
event 交付 ready snapshot 或 terminal failure。拍照、带声/静音录像、镜头切换、闪光、对焦、缩放、
重拍、确认和取消都先验证当前 registry state；非法参数不改变状态。确认结束 Session，但确认媒体的租约
由独立 Media registry 继续持有，因此不会阻止下一次拍摄。

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
  后到的旧回调不能完成新 operation。close 会显式注销 NotificationCenter observer。
- photo 只在最终 `didFinishCaptureFor` 提交底层 completion；movie 只在最终 recording callback 提交。
  调用者取消会请求对应 operation 停止，但仍等待底层 exactly-once completion，再传播 `CancellationError`。
  视频净化 export 同样由 cancellable operation 包装 `cancelExport` 和最终 export callback。
- 系统 interruption/runtime error 映射为 `system_interrupted`，与用户 `cancel` 分离。

Host 后续只在真实流程启用时增加 `NSCameraUsageDescription`；启用带声录像时再增加
`NSMicrophoneUsageDescription`。Core 初始化不会弹权限，也不修改 Info.plist 或 Entitlements。

## 文件、租约与清理

媒体文件只存在于 App 私有 temporary 子目录，物理所有者始终是 Core。照片在进入 preview registry 前通过
ImageIO 物理旋转并重新编码 JPEG；视频在进入 preview registry 前通过 AVAssetExportSession 输出无业务
metadata 的副本。公共 metadata 不包含文件名、路径、位置或设备信息。

未确认 preview 的 TTL 固定 600 秒。confirm 后逻辑 lease 固定 86400 秒；显式 release 或 lease 到期会
立即拒绝新读取，并给既有原始读取最多 60 秒 grace。grace 结束后 Core 强制关闭读取、删除文件，再进入
released/expired tombstone；Session 与 Media tombstone 都固定保留 300 秒。重复 stop、cancel 和 release
复用既有结果，不延长 TTL、grace 或 tombstone。

App restart 和 Core close 会先使 thumbnail job 与 render generation 失效，再停止 callback、关闭读取、
等待 AV delegate 和 decoder worker，丢弃未完成录像 destination、删除临时媒体并清空 registry。restart 后
旧 handle 只能得到 `session_invalid` 或 `media_invalid`。

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
5. 拍照、停止录像、重拍、确认、取消、失败、超时、旋转、后台、owner destroy、restart 和 close 都先撤销
   相应 attachment，再处理状态或媒体所有权。

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
租约/grace/tombstone、teardown/restart 对新 Session 的 gate、阻塞读取强制撤销、production read/close
串行、真实文件删除、partial recording 删除、photo/movie/export cancel-and-await、delegate/observer cleanup、
concrete surface 全链路 replacement/stale generation、rotation/background/restart/双类 owner destroy、thumbnail
budget/first-winner/cancel-and-await/JPEG retry buffer wipe、poster 选择和 metadata 净化。
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
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -configuration Debug CODE_SIGNING_ALLOWED=NO test)
```

Framework Fake 和 Simulator 只能证明模块编排、iOS SDK 链接与支持的 Apple API 行为，不能证明真机 Camera、
Microphone 授权 UI、硬件 interruption、编码性能或内存峰值。大尺寸照片/视频、真实系统权限、硬件中断和
持续性能仍由 iOS quality gate 在明确真机上留证。
