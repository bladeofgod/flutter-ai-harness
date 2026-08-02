---
executor: ios-engineer
platforms: [ios]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-dart-client
  - media-capture-ios-core
  - media-capture-ios-dismiss-wire-support
  - media-capture-ios-native-ui
  - media-capture-ios-swiftpm-host-architecture
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 实现并验证 iOS Media Capture Bridge Adapter

## 输入与事实来源

- 最新 Media Capture Wire Schema/Profile/详情和 Capability Contract。
- 已归档 Dart Client、iOS Core、iOS Native UI。
- `docs/native-architecture.md`、Swift/iOS 与 Native Testing Skill。

## 目标

- 按已锁定的 SwiftPM Host 路线，在 Flutter Plugin iOS 子目录实现 Wire/Native 映射和 plugin 注册入口，
  并用锁定 Flutter 3.35.7/Xcode/iOS SDK 验证 Bridge Core 与临时 Host 两层构建。
- 映射直接 Capability method/event、bounded thumbnail 与全屏 `present_capture_flow`。
- 正确处理 MainActor callback、request/listener generation、resource adoption、Engine/UI owner 生命周期。

## 非目标

- 不改变 Contract、Core/UI 或 Dart Client，不在 Adapter 拥有能力/文件/UI 状态。
- 不把 Capability 的 live/unconfirmed preview attachment、RenderTarget Adapter 或 owner generation
  映射到 Flutter；已 present 的 iOS Native UI 直接消费这些 Native-only API。
- 不修改 Runner/Info.plist/Host、共享 pubspec、CI/Makefile、Shoppe 或 Android。
- 不修改真实 Demo Host，也不增加 CocoaPods fallback、本机 Flutter framework path 或手工 binary
  接线；临时 Host 路线失败时返回已归档的 SwiftPM Host 架构决策复审。

## 实现路径与所有权

本任务只写：

- `app/packages/app_media_capture_bridge/ios/**`
- `docs/bridge/media-capture-ios.md`
- 本任务测试/Review/evidence

Flutter Plugin manifest 固定为
`app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Package.swift`，依赖仓库相对的
iOS Core/UI Package products。不得修改共享 `pubspec.yaml`、`lib/**`、`app/native/ios/**`、Host、
共享 docs/Validator/Registry 或其它 Runtime。

Package 必须拆分为不 import Flutter 的 `MediaCaptureBridgeCore` target 与只拥有 Flutter 边界的
`app_media_capture_bridge` Plugin target。Codec、request registry、lifecycle coordinator、Core/UI
协议与实现包装位于 Bridge Core；Channel handler、Flutter result/event sink、registrar 和当前 presenting
owner lookup 位于 Plugin target。

## 实现要求

1. Flutter method/event 入站即闭合校验，再构造 Sendable 类型化 Model；Dictionary 不进入 Core/UI。
   出站验证所有值/bytes/整数/枚举后在 MainActor/main queue 恰好一次回调。
2. 显式 Mapper 和稳定 FlutterError/PlatformException details 遵守 Wire redaction；禁止强制转换、
   payload/handle/requestId/bytes/path/底层异常泄漏。
3. 实现固定容量 request registry、completion slot、Event sink generation 与统一 lifecycle coordinator；
   actor/明确隔离保证 callback、boundary、resource adoption 和 late cleanup 线性化。
4. `present_capture_flow` 只使用当前 presenting ViewController owner；处理 concurrent present、dismiss、
   scene/owner destroy、Engine detach、late lease 和三终态，不把 system failure 映射为用户取消。消费
   前置任务已提升的 Wire V3 `dismiss_capture_flow`：只接受 originating presentation request ID，幂等
   关闭匹配 flow；本卡不再修改共享 support matrix。
5. `read_media_thumbnail` 只映射 Core 的 bounded sanitized copy 到 `FlutterStandardTypedData`/契约 byte
   类型，不打开原始 read scope，不提供 URL/path fallback，不缓存或记录敏感数据。
6. Engine detach 与 ViewController owner destroy 的 Session/lease/sink 策略精确匹配 Wire；所有
   continuation/callback 只能 resume 一次，Task/observer/delegate 在 dispose 时释放。
7. SwiftPM manifest 只声明两个本地 target、Core/UI products 与真实测试依赖，不声明本机 Flutter
   binary path、远程包装依赖或 CocoaPods fallback。Bridge Core 的相对 Package 路径和 iOS 13 target
   使用 generic iOS Simulator SDK compile；Flutter API 与 plugin discovery 使用临时 Host build 验证。
8. 在 `ios/**` 内提供可审查的临时 Host 验证入口：从当前仓库 App Workspace 构造可清理副本，排除
   build、`.dart_tool`、Pods 与 ephemeral 产物，只在临时 `pubspec.yaml` 副本的 `flutter.config` 下写入
   `enable-swift-package-manager: true`，再用锁定工具链执行 no-codesign iOS build。入口不得读取结果来
   猜测或修改用户全局 Flutter 配置，不得修改真实 Host 或入库生成 package。临时目录必须由系统
   `mktemp` 创建并收紧为仅当前用户访问；复制清单必须排除 `.env*`、签名证书/私钥、Provisioning
   Profile、钥匙串导出物、`xcuserdata` 和其它未声明本地材料。`trap` 必须覆盖成功、失败及 HUP/INT/TERM
   信号退出的清理，命令输出与证据不得记录临时目录或生成产物中的本机绝对路径。

## 测试与验收

- Fake Core/UI 覆盖所有 method/event、恶意 Dictionary、error details、MainActor、容量/重复、listener、
  detach/destroy、三终态、late cleanup 和 thumbnail 上限。
- 并发测试证明 adoption-before-success 和 boundary-before-late-cleanup；无双 resume/completion。
- `MediaCaptureBridgeCore` 独立 build/test，无 Core 状态机复制，entry 与 Dart pubspec/Wire 一致。
- 必须对 Bridge Core scheme 执行 generic iOS Simulator `xcodebuild` compile，证明 UIKit/MainActor、
  Core/UI products 与 iOS 13 target 使用 iOS SDK 编译；Flutter iOS API 和 Plugin target 由临时 Flutter
  Host no-codesign build 证明。无 booted Simulator 不能跳过这两类编译；存在可用 Simulator 时再执行
  不依赖真实 Camera 的运行 tests。

## 验证命令

```bash
(cd app/packages/app_media_capture_bridge/ios/app_media_capture_bridge && xcodebuild -scheme MediaCaptureBridgeCore -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
bash app/packages/app_media_capture_bridge/ios/tool/verify-host-route.sh
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode/Swift/Flutter。Bridge Core generic iOS Simulator SDK compile 与临时 Flutter Host
no-codesign build 均为 mandatory 且不依赖 booted Simulator；运行 tests 按可用 Simulator 留证。Fake、
Bridge Core 与临时 Host 不能证明真实 Camera、权限或 Demo Runner 已迁移；最终 Integration 负责真实
Host 接线，真机验收由用户执行。

## 执行结果

- iOS SwiftPM Plugin 已实现，Bridge Core 与 Flutter target 分层，映射 Wire V3 基础拍摄、thumbnail、
  presentation/dismiss 和 Event Channel。
- owner/Engine 生命周期、权限与硬件预检、late resource cleanup、thumbnail bytes 和临时验证工作区均已
  实现并通过聚焦测试。
- 测试证据：[`../../reviews/test-evidence/media-capture-ios-bridge-adapter.log`](../../reviews/test-evidence/media-capture-ios-bridge-adapter.log)。
- 普通 Review：[`../../reviews/execute-media-capture-ios-bridge-adapter.md`](../../reviews/execute-media-capture-ios-bridge-adapter.md)，P0/P1/P2 均为 0。
- Security Review：[`../../reviews/security-media-capture-ios-bridge-adapter.md`](../../reviews/security-media-capture-ios-bridge-adapter.md)，P0/P1 为 0；2 个 P2 已记录 `ios-engineer` 负责人。
- 真机 Camera/Microphone、权限 UI、最终 Demo Runner 接线和 codesign 安装仍按任务边界留给后续
  Integration/Quality Gate 与用户验收。
