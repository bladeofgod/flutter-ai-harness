---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-core
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 实现 iOS 全屏 Media Capture Native UI

## 输入与事实来源

- 已归档 iOS Core 与最新 Native UI Flow Wire。
- 用户批准的微信式交互方向；Shoppe primary `#004CFF` 与黑色相机画布语义。
- `docs/native-architecture.md`、Swift/iOS 与 Native Testing Skill。

## 目标

- 实现由 iOS presenting ViewController 全屏呈现、直接调用 Swift Core 的原生拍摄器。
- 支持点击拍照、长按录像、滑动缩放、切镜头、闪光、点按对焦、预览、重拍、确认、取消。
- 通过 Swift UI flow coordinator 交付 confirmed/cancelled/failure 单一终态。

## 非目标

- 不复制微信品牌/资产/文案/逐像素布局，不等待专用 Figma。
- 不在 UI 中拥有 Capability 状态机/文件租约或 Wire Dictionary。
- 不实现 Flutter Adapter、Runner/Info.plist、Shoppe 页面或 V1 外编辑能力。

## 实现路径与所有权

本任务只写：

- `app/native/ios/MediaCaptureUI/**`
- `docs/native/media-capture-ios-ui.md`
- 本任务测试/Review/evidence

不得修改 iOS Core、plugin `ios/**`、Capability/Wire、Host、共享 docs/Registry、root Validator、CI、
Makefile 或 Android/Flutter Feature 文件。

## 实现要求

1. 使用与 iOS 13/锁定 Xcode 兼容的全屏 Native UI，黑色 capture canvas、白色高对比控制、
   `#004CFF` 选中/确认语义和 SF Symbols；不得复制微信品牌资源。
2. UI 状态由 Core capability snapshot 驱动；手势、拍照/录像互斥、自动时限、focus `[0,1]`、zoom
   范围、切镜头/闪光和预览/重拍/确认/取消逐项与 Android/Wire 语义一致。长按进入 recording 后隐藏
   切镜头控件，停止/取消录制并回到允许状态后再按 snapshot 恢复。
3. Live camera 与确认前 preview 只组合 `MediaCaptureAppleRendering` 提供的 concrete
   `MediaCaptureRenderView` 和 Core attachment API；UI 不实现基础 Render Adapter，也不持有
   `AVCaptureSession`/preview layer/player layer/sample buffer、原始 read scope 或路径。
   确认只交付 Core lease metadata，取消是正常终态；Capability Failure、presentation failure 与
   system interruption 不冒充取消。
4. presenting ViewController generation、dismiss、rotation、scene background/foreground、owner
   deallocation 与 concurrent present 遵守 Flow Wire；每条路径只 resume continuation/complete 一次。
   公开 `awaitResult` 必须响应 structured cancellation、触发非用户取消的终态清理并传播
   `CancellationError`。
5. `@MainActor` 仅拥有 UI/presentation，Core/编码不在主线程。Task、AsyncSequence、UI owner、
   RenderTarget Adapter 和 backing view/layer 均可取消/释放；Camera session/preview pipeline 仍由 Core
   独占。禁止强制解包和未追踪 detached task。
6. VoiceOver label、Dynamic Type、Safe Area、横竖屏、窄屏和控制可达性有测试；不增加可见教程文案。

## 测试与验收

- Swift coordinator/unit tests 覆盖手势、状态、三终态、权限/Failure、时限、重复回调、dismiss、
  owner generation、single attach、detach/revoke、deinit、rotation、scene background/foreground 重新
  attach 和 cleanup。
- 平台 UI 测试用 Fake Core 验证控件/无障碍/状态，不冒充真机 Camera preview。
- Package 只依赖 Swift Core/Apple UI Framework，无 Flutter/Wire Dictionary。
- Review 确认微信式交互方向与 Shoppe 色彩语义，但没有品牌或像素复制。
- 必须对 `MediaCaptureUI` scheme 执行 generic iOS Simulator `xcodebuild` compile，证明 UIKit、iOS 13
  target、SF Symbols/布局和 Core Package dependency 使用 iOS SDK 编译。无 booted Simulator 不能跳过；
  可用 Simulator 上再运行 UI/lifecycle tests 并留证。`swift test/build` 只可补充纯 Swift host-compatible
  target，不能作为本 UI 模块的唯一证据。

## 验证命令

```bash
(cd app/native/ios/MediaCaptureUI && xcodebuild -scheme MediaCaptureUI -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode/Swift。generic iOS Simulator SDK compile mandatory 且不依赖 booted Simulator；运行测试
按可用 Simulator 留证。Package/Fake/Simulator 不能证明真机 Camera、系统权限 UI 或硬件录像性能，
这些结果由 iOS Gate 记录，未运行时不得宣称通过。
