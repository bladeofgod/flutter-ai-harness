---
executor: task-executor
platforms: [flutter]
workKinds: [flutter, harness]
blockedBy:
  - flutter-media-resource-foundation
securityReview: required
---

# 实现 Flutter 图片与视频媒体预览组件

## 输入与事实来源

- 已完成的 `app_media` Store、`MediaResourceId` 与 `app_ui` Token。
- 用户批准：通用 Flutter 基础件同时支持图片和视频预览；消息气泡点击后可以查看或播放真实资源。
- 用户批准分阶段验收：本任务先完成 Flutter 行为与 Android Host 构建；iOS Plugin/Host 构建、Pod
  锁定和运行验证在后续 iOS/跨 Runtime 任务执行。
- 用户接受 `flutter_video_thumbnail_plus` 第三方原生实现的已知内部风险；本任务只验证公开依赖锁定、
  Flutter 边界约束和 Android 可构建性，不修改或 fork 第三方源码。
- 当前 Support 媒体气泡在无 thumbnail 时只显示黑色占位，视频播放图标没有交互。

## 目标

- 在 `app_media` 实现按 `MediaResourceId` 加载的通用媒体缩略图与全屏预览 Widget。
- 图片显示真实内容并支持缩放；视频显示真实可解码帧并提供完整 V1 播放控制和生命周期管理。
- 提供窄 `MediaPlaybackProbe` 与 `MediaPosterService`，让业务在接纳消息前验证视频并生成 bounded poster。
- 向 Feature 暴露业务无关 Widget/Controller 接口，不持有消息或 Route 规则。

## 非目标

- 不实现 Support 页面、GoRouter route、选择器、上传、编辑、滤镜、投屏、后台音频或网络媒体。
- 不把视频 Controller、File URI 或底层播放器异常暴露给 `app_data` 或消息 Entity。
- 不增加 UI Spec/App Operator 门禁；运行验证由人工后续独立安排。

## 实现要求

1. 使用 Flutter 官方 `video_player` 的当前兼容稳定版本作为视频解码/播放引擎；使用一个经过许可证、
   维护状态和双端构建验证的公开 thumbnail provider 实现视频 poster，不手写 codec、平台 texture 或
   native player。依赖只写 `app_media/pubspec.yaml` 并锁定解析结果；Security Review 必须覆盖两项依赖。
2. `MediaPlaybackProbe` resolve并 retain资源，用 `video_player` 完成一次初始化、读取实际 duration 后立即
   dispose/release，返回闭合 playable/unsupported/failure；`MediaPosterService` 使用 reviewed provider
   生成 bounded sanitized poster。两者不暴露 Controller、URI 或底层异常。
3. `MediaResourceThumbnail` 接受 Resource ID、可选 bounded poster、Store 和稳定尺寸约束。图片从
   canonical file 或 poster 解码；视频只显示 sanitized poster 与标准播放图标，不为每条气泡常驻
   `VideoPlayerController`。poster 缺失/失败显示明确视频占位，不以黑框冒充真实帧。
4. loading 使用稳定占位尺寸；resolve/decode/player failure 显示明确错误图标和 Semantics，不永久显示无解释
   黑框。late resolve/init 在 Widget dispose 后只清理资源，不 setState。
5. `MediaPreviewPage` 或等价根 Widget 接受 Resource ID/Store。图片使用 `InteractiveViewer` 完成适配、
   双指缩放和平移；视频支持播放/暂停、中心按钮、进度拖动、当前/总时长和结束后重播。
6. Viewer 默认黑色内容背景但控件使用 `app_ui` 可读 Token；顶部关闭区域和底部控制区覆盖 Safe Area，
   320x568、375x812、横屏和 1.3x 字号不溢出或遮挡。图标按钮提供 tooltip/Semantics。
7. 视频默认不在缩略图自动播放；全屏初始暂停。Route 不可见、App inactive/paused/detached 时立即暂停，
   resumed 不自动续播；dispose 恰好一次释放播放器和 observer。
8. Thumbnail、Probe、Poster Service 与 Viewer 都必须在 resolve/decode/poster/player 异步范围开始前各自 retain，完成、取消、
   初始化失败、Widget 卸载或 late completion 时 release exactly once；它们不得删除消息持有的原始
   引用。会话删除资源时必须先发布 UI 状态并卸载消费者，再 release owner reference。
9. poster generator 全局最多 2 个并发 job、每个 10 秒 deadline，输出 JPEG/PNG 最长 524,288 bytes、
   最大边 512px；排队 Widget 离屏/卸载时取消，取消协作失败的 late result 只清理不交付。全屏同时最多
   一个 active video player；打开新 Viewer 前先 dispose 旧实例。
10. 视频在业务接纳前以及直接进入 Viewer 时执行真实 platform decoder probe；MP4/MOV 初始化失败返回 `unsupported_media` 或
   `playback_failed`，不得在消息发送验收中把容器检查当成可播放证据。
11. 不记录 Resource ID、file URI、媒体内容、底层播放器 details 或用户文件名。错误只暴露稳定、可展示的
   `missing`、`invalid`、`decode_failed`、`playback_failed` 等类型化状态。
12. 本阶段必须完成 Android Debug Host build。iOS Plugin discovery、CocoaPods 依赖图与 no-codesign
    Debug Host build 由 `media-capture-cross-runtime-integration` 在 iOS Bridge/Host 就绪后统一验证，
    本任务不得用未完成的 iOS Bridge 接线阻断 Android/Flutter 交付。

## 测试与验收

- Widget/Service/Controller 测试覆盖图片成功、缩放边界、probe success/unsupported/late dispose、poster
  并发/超时/离屏取消、视频首帧、
  play/pause/seek/replay、App 生命周期、消息删除竞态、resolve/decode failure、late callback、dispose 和
  Thumbnail/Viewer retain/release exactly once。
- 使用 Store Fake 和播放器抽象 Fake 做确定性测试；Fake 不能冒充平台真实解码。
- Golden/布局测试至少覆盖 320x568、375x812、横屏、大字号、Safe Area 和长时长文案。
- Android Debug Host build 证明本阶段 plugin 可被发现；没有真实设备时不宣称硬件解码已运行。
- iOS Host build 与真实播放器/thumbnail 运行结论明确后置到 iOS/跨 Runtime 任务。

```bash
TOOL_WORKDIR=app/packages/app_media bash scripts/flutter-tool.sh test
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
make format
make analyze
make test
make lint
make harness-check
git diff --check
```

## 环境限制

Android 平台编译需要对应 SDK。无设备时静态 Widget/Fake 与 Host build 不能证明真实视频首帧、
音视频同步或系统解码器行为；iOS Host build 和双端运行证据由最终跨 Runtime 任务补齐。
