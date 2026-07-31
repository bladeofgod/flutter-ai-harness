---
executor: ios-engineer
platforms: [ios]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-dart-client
  - media-capture-ios-core
  - media-capture-ios-native-ui
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 实现并验证 iOS Media Capture Bridge Adapter

## 输入与事实来源

- 最新 Media Capture Wire Schema/Profile/详情和 Capability Contract。
- 已归档 Dart Client、iOS Core、iOS Native UI。
- `docs/native-architecture.md`、Swift/iOS 与 Native Testing Skill。

## 目标

- 按原生架构的候选 SwiftPM Host 路线，在 Flutter Plugin iOS 子目录实现 Wire/Native 映射和 plugin
  注册入口，并先用锁定 Flutter 3.35.7/Xcode/iOS SDK 验证该路线可被 Host 发现和编译。
- 映射直接 Capability method/event、bounded thumbnail 与全屏 `present_capture_flow`。
- 正确处理 MainActor callback、request/listener generation、resource adoption、Engine/UI owner 生命周期。

## 非目标

- 不改变 Contract、Core/UI 或 Dart Client，不在 Adapter 拥有能力/文件/UI 状态。
- 不把 Capability 的 live/unconfirmed preview attachment、RenderTarget Adapter 或 owner generation
  映射到 Flutter；已 present 的 iOS Native UI 直接消费这些 Native-only API。
- 不修改 Runner/Info.plist/Host、共享 pubspec、CI/Makefile、Shoppe 或 Android。
- SwiftPM Host 路线尚不是无条件既定事实：若锁定 Flutter/Xcode 无法发现或 generic iOS Simulator
  compile 该 Plugin，必须停止并回到独立架构决策任务；不得在本卡现场增加未审查 CocoaPods fallback。

## 实现路径与所有权

本任务只写：

- `app/packages/app_media_capture_bridge/ios/**`
- `docs/bridge/media-capture-ios.md`
- 本任务测试/Review/evidence

Flutter Plugin manifest 固定为
`app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Package.swift`，依赖仓库相对的
iOS Core/UI Package products。不得修改共享 `pubspec.yaml`、`lib/**`、`app/native/ios/**`、Host、
共享 docs/Validator/Registry 或其它 Runtime。

## 实现要求

1. Flutter method/event 入站即闭合校验，再构造 Sendable 类型化 Model；Dictionary 不进入 Core/UI。
   出站验证所有值/bytes/整数/枚举后在 MainActor/main queue 恰好一次回调。
2. 显式 Mapper 和稳定 FlutterError/PlatformException details 遵守 Wire redaction；禁止强制转换、
   payload/handle/requestId/bytes/path/底层异常泄漏。
3. 实现固定容量 request registry、completion slot、Event sink generation 与统一 lifecycle coordinator；
   actor/明确隔离保证 callback、boundary、resource adoption 和 late cleanup 线性化。
4. `present_capture_flow` 只使用当前 presenting ViewController owner；处理 concurrent present、dismiss、
   scene/owner destroy、Engine detach、late lease 和三终态，不把 system failure 映射为用户取消。补齐
   Wire V3 `dismiss_capture_flow`：只接受 originating presentation request ID，幂等关闭匹配 flow，并把
   当前 support matrix 从 iOS unsupported 更新为 supported。
5. `read_media_thumbnail` 只映射 Core 的 bounded sanitized copy 到 `FlutterStandardTypedData`/契约 byte
   类型，不打开原始 read scope，不提供 URL/path fallback，不缓存或记录敏感数据。
6. Engine detach 与 ViewController owner destroy 的 Session/lease/sink 策略精确匹配 Wire；所有
   continuation/callback 只能 resume 一次，Task/observer/delegate 在 dispose 时释放。
7. 候选 SwiftPM manifest 只声明 Flutter API、Core/UI products 与真实测试依赖；相对路径、Flutter
   plugin discovery 和 iOS 13 最低平台必须在 Flutter 3.35.7/Xcode 工具链验证，不依赖本机配置。
   验证失败即阻塞，不得自行切换 CocoaPods。

## 测试与验收

- Fake Core/UI 覆盖所有 method/event、恶意 Dictionary、error details、MainActor、容量/重复、listener、
  detach/destroy、三终态、late cleanup 和 thumbnail 上限。
- 并发测试证明 adoption-before-success 和 boundary-before-late-cleanup；无双 resume/completion。
- Adapter SwiftPM 独立 build/test，无 Core 状态机复制，entry 与 Dart pubspec/Wire 一致。
- 必须对 Adapter plugin scheme 执行 generic iOS Simulator `xcodebuild` compile，证明 Flutter iOS-only
  API、UIKit/MainActor、Core/UI products 与 iOS 13 target 使用 iOS SDK 编译；无 booted Simulator 不能
  跳过。存在可用 Simulator 时再执行运行 tests；`swift test/build` 只可补充明确 host-compatible 的纯
  Swift codec target，不能作为 Adapter 或 Flutter API 的唯一证据。

## 验证命令

```bash
(cd app/packages/app_media_capture_bridge/ios/app_media_capture_bridge && xcodebuild -scheme app_media_capture_bridge -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode/Swift/Flutter。generic iOS Simulator SDK compile mandatory 且不依赖 booted
Simulator；运行 tests 按可用 Simulator 留证。Fake/Package compile 不能证明真实 ViewController、
Camera、权限或 Runner 注册；iOS Gate 负责验证候选 Host 路线，最终 Integration 只消费已验证路线。
