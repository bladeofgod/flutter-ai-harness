---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-render-surface-capability-evolution
securityReview: required
---

# 实现 iOS Media Capture Native Core

## 输入与事实来源

- 最新 Capability V3、Schema/详情文档与本任务现有 Review 历史。
- `docs/native-architecture.md`、`swift-ios-standards`、`native-testing-strategy`。
- 当前 Host 基线 iOS 13、Swift 5 配置；模块采用 Swift、Swift Concurrency、本地 SwiftPM 和
  AVFoundation，实际 Package platform/工具链由本任务在仓库环境构建验证。

## 目标

- 在本地 Swift Package 中实现 transport-neutral、类型化的 Media Capture Core。
- 使用 Swift Concurrency/actor 与 AVFoundation 实现 Capability 的操作、状态、权限前置、资源、
  文件租约、Native Preview、缩略图和稳定 Failure 语义。
- 让 iOS 原生消费者不经过 Flutter 即可直接依赖 Package product。

## 非目标

- 不实现 Flutter Channel/Adapter、全屏 Native UI、Runner 注册或 Shoppe 页面。
- 不读取 Wire Dictionary，不 import Flutter，不把 AVFoundation 对象暴露到公共 API。
- 不修改 Info.plist/Entitlements/Host，不实现非 V1 编辑/上传/相册功能。

## 实现路径与所有权

本任务只写：

- `app/native/ios/MediaCapture/**`
- `docs/infrastructure/media-capture-ios.md`
- 本任务自己的测试、Review 与 evidence 文件

不得修改共享 Capability/Wire 文档、`app/packages/app_media_capture_bridge/**`、
`app/apps/demo/**`、root Validator、共享 Registry、CI、Makefile 或 Android 路径。

## 实现要求

1. 公共 API 遵守 Swift API Design，使用 Sendable value/sealed-style enum、async/throws、
   AsyncSequence 和稳定错误；initializer 注入 AVFoundation wrapper、文件系统、Clock、随机源和执行域。
2. actor 或等价明确隔离拥有 Session/Media registry；CSPRNG handle、严格 lookup、租约、TTL、grace、
   tombstone、restart 和并发竞态逐项符合最新 Capability。
3. Camera/Microphone 只由明确用户动作触发；照片/静音录像不请求麦克风，Photo Library 不请求。
   授权状态按 iOS 可表达语义映射 denied/restricted/permanently_denied，不虚构可重试能力。
4. AVFoundation capture、录像时限、镜头/闪光/对焦/缩放、interruption、空间与编码 failure 都映射
   稳定语义；CancellationError 继续传播，不伪装成用户取消或普通 Failure。
5. 媒体在 App 私有 temporary/cache 范围，确认前净化位置/设备 metadata；原始读取 callback-scoped，
   缩略图只对 active confirmed lease 生成固定 upright JPEG/poster policy 的受限净化 copy，不泄漏
   路径、原图或 AVFoundation 对象。
6. Swift Package 同时提供 `MediaCapture` transport-neutral Core product 与
   `MediaCaptureAppleRendering` presentation product。Core public symbol 不出现 UIKit、AVFoundation、URL
   或 CALayer；Rendering product 公开具体 `MediaCaptureRenderView: UIView`。两个 target 只用 Swift
   `package` access 传递强类型私有 source/backing endpoint，禁止 `_spi`、`AnyObject`、空 token 或
   外部 downcast。Live 实际安装 `AVCaptureVideoPreviewLayer`，photo 安装 decoded content，video 安装
   `AVPlayerLayer`；revoke/detach 清空 session/player/content 并移除 sublayer。actor registry 继续负责
   generation、identity、rotation/background/owner deinit revoke、callback gate 和 terminal cleanup。
7. Delegate/observer/continuation/session/file 都有明确所有者，弱引用和 stop/deinit cleanup 可测试；
   只有 Apple/UI API 需要时切 MainActor，编解码不占主线程。
8. 依赖只声明在 `Package.swift`；优先 Apple Framework，不引入无真实消费者的第三方包。

## 测试与验收

- Swift 单测覆盖完整状态机、权限、非法输入、幂等、取消/竞态、Clock TTL/grace、handle 安全、
  interruption、文件删除、两类 Render attachment generation/attach/detach/revoke/rotation/background/
  owner destroy、metadata 净化和确定性 poster/bounded thumbnail。
- AVFoundation/File/Clock/Executor 用窄 Fake；Fake 不冒充真机 Camera/权限验证。
- 原生 Consumer 测试只 import Package product，无 Flutter/Wire Dictionary。
- 普通 Consumer 同时 import 两个 product 并使用 concrete surface；内部测试验证真实 layer tree/source
  binding、replacement、detach/revoke 清空与 stale generation 不再修改 target。
- 必须使用 iOS SDK 对 `MediaCapture` scheme 执行 generic iOS Simulator `xcodebuild` compile，证明
  AVFoundation、UIKit-adjacent target 条件和 iOS 13 deployment target 可编译；无 booted Simulator
  不能跳过该 compile。
- 只有明确拆出的、host-compatible 且不 import iOS-only API 的纯 Swift target 才可补充使用
  `swift test/build`；它们不能替代 iOS SDK compile。存在可用 Simulator 时再运行 target tests 并留证，
  没有可用 Simulator时准确记录运行测试缺口。

## 验证命令

```bash
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCaptureAppleRendering -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode/Swift 工具链。generic iOS Simulator compile 是 mandatory，不依赖 booted Simulator；
运行 tests 只有在 Simulator 可用时执行并留证。Fake/Simulator 仍不能证明真机 Camera、Microphone 授权
UI、中断和性能，这些缺口留给 iOS Gate/最终集成，不得宣称已验证设备能力。
