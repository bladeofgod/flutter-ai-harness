---
executor: android-engineer
platforms: [android]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-android-core
  - media-capture-android-native-ui
  - media-capture-dart-client
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 实现 Android Media Capture Bridge Adapter

## 输入与事实来源

- 最新 Media Capture Wire Schema/Profile/详情和 Capability Contract。
- 已归档 Dart Client、Android Core、Android Native UI。
- `docs/native-architecture.md`、Kotlin/Android 与 Native Testing Skill。

## 目标

- 在聚焦 Flutter Plugin 的 Android 子目录实现 Wire DTO/Native Model 映射和 plugin 注册入口。
- 映射全部直接 Capability method/event、bounded thumbnail 和全屏 `present_capture_flow`。
- 正确处理 UI 线程、request/listener generation、资源 adoption、Engine/Activity 生命周期和 late cleanup。

## 非目标

- 不改变 Capability/Wire、Core/UI 行为或 Dart Client API。
- 不在 Adapter 中拥有 Camera 状态机、文件策略、缩略图编码或产品 UI。
- 不把 Capability 的 live preview attachment、unconfirmed preview render scope、RenderTarget Adapter
  或 owner generation 映射到 Channel；这些只由已 present 的 Android Native UI 直接消费。
- 不修改 Host/Manifest、共享 plugin pubspec、CI/Makefile、Shoppe Feature 或 iOS 实现。

## 实现路径与所有权

本任务只写：

- `app/packages/app_media_capture_bridge/android/**`
- `docs/bridge/media-capture-android.md`
- 本任务测试/Review/evidence

共享 `app/packages/app_media_capture_bridge/pubspec.yaml` 和 `lib/**` 由 Dart Client 固定；本任务只实现
其中声明的 Android plugin entry。不得修改 `app/native/android/**`、Host、共享 docs/Validator/
Registry 或其它 Runtime。

## 实现要求

1. MethodCall/EventChannel 入站即验证 Wire version/envelope/payload/type/range/unknown key/requestId/
   handle；原始 Map 不进入 Core/UI。所有 Native result/event 出站前再次验证并在 Android main thread
   回调 Flutter。
2. 使用显式 Mapper 在 Wire DTO、Core Model、Native UI flow outcome 之间转换；Capability Failure 与
   Wire error/details 完全按 Contract 闭合集合脱敏，不回显 payload、handle、bytes、路径或异常。
3. 实现固定容量 pending/completed request registry、完成槽预留、exactly-once completion、Event sink
   单订阅、listener generation 和 `bridge_lifecycle_coordinator` 线性化顺序。
4. `present_capture_flow` 只能使用当前 attached Activity/UI owner 全屏 present Android UI；重复 present、
   owner destroy/configuration、Engine detach、late confirmed lease 和 dismiss 逐项执行 Wire cleanup。
5. `read_media_thumbnail` 只调用 Core 最新受限 API并映射 bounded `Uint8List`；不打开原始 read scope，
   不提供 path/URI fallback，不缓存/记录 bytes 或 handle。
6. Engine detach 释放 attachment Session/lease/sink；Activity destroy 终止旧 owner Session、保留已交付的
   Engine lease、清理晚到资源。新 attachment/owner 使用新 generation，不继承旧 callback。
7. Gradle 只声明 Flutter API、Android Core/UI project dependency 与真实测试依赖；版本/路径相对仓库且
   与锁定工具链可复现，不把 Module include 写进 Host。

## 测试与验收

- 用 Fake Core/UI 测试所有 method/event、畸形/恶意 payload、错误 details、线程、容量、重复、listener、
  Engine detach、Activity destroy、presentation 三终态、late cleanup 和 thumbnail 上限。
- 竞态测试证明 resource adoption 先于 Flutter success，boundary 先赢时先 cleanup 且不二次完成。
- Adapter 编译不包含 Core 状态机/文件实现，Host 尚未接线时可独立构建测试。
- Dart/Android method、event、payload、error 和 plugin entry 与最新 Contract/pubspec 精确一致。

## 验证命令

```bash
app/apps/demo/android/gradlew -p app/packages/app_media_capture_bridge/android test lint
make harness-check
git diff --check
```

## 环境限制

需要 Android SDK/JDK 和 Flutter SDK；Fake 测试不证明真实 Activity presentation、Camera、权限或 Host
自动注册。平台 Gate 与最终 Integration 负责构建/运行证据。
