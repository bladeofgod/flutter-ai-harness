---
executor: android-engineer
platforms: [android]
workKinds: [integration]
blockedBy:
  - media-capture-android-bridge-adapter
  - media-capture-android-native-ui
  - media-capture-android-quality-gate
  - media-capture-flutter-package-registration
securityReview: required
---

# 接入 Android Media Capture Host

## 输入与事实来源

- 已归档 Android Core、Native UI、Bridge Adapter 和 Android 专项质量门禁。
- 已登记到 Demo 依赖图的 `app_media_capture_bridge` Flutter Plugin。
- `docs/native-architecture.md`、Android Bridge 详情和锁定 Flutter/Gradle/Kotlin 工具链。
- 用户提供的 Android 真机只用于运行验证；设备标识和真实媒体不得写入证据。

## 目标

- 在 Demo Android Host 中以仓库相对 Gradle project 接入 Core/UI，并让标准 Flutter plugin loader
  自动构建和注册 Android Adapter。
- 增加最小 Camera/Microphone 权限声明，完成真实 Android Debug APK 的依赖图与注册编译验证。

## 非目标

- 不修改 Core/UI/Adapter 生产实现、Dart Client、Flutter Feature、iOS Host、Wire/Capability、根 CI
  或共享最终集成状态。
- 不在 `MainActivity` 中实现 Wire 映射、状态机、文件租约、权限预请求或业务导航。

## 实现路径与所有权

本任务只写：

- `app/apps/demo/android/**`
- `docs/native/media-capture-android-host-verification.md`
- 本任务测试、Review 和 evidence

## 实现要求

1. `settings.gradle.kts` 使用仓库相对 `projectDir` include Android Core/UI；Adapter 继续由 Flutter plugin
   loader 根据 Package metadata 接入，不复制源码或使用本机绝对路径。
2. Host Manifest 只声明 `CAMERA`、`RECORD_AUDIO`；不声明相册/广泛存储权限，不在 App 启动时请求。
3. `MainActivity` 保持纯 Host；标准自动注册能获得当前 Activity/Lifecycle owner，不增加业务逻辑。
4. Debug APK 构建必须解析 Adapter -> UI/Core 的真实 project dependency，并在 merged manifest/构建产物
   中证明 Plugin 与权限已进入 Host。
5. 在可用真机上安装 Debug APK；真实拍摄交互由后置订单评价 Consumer 接入后执行，本任务不能用启动
   App 冒充 Camera 已验证。

## 测试与验收

- Android 专项门禁继续通过。
- Demo Debug APK 构建并安装成功，Host 构建日志能证明 Plugin、Core/UI 依赖参与构建。
- Host 没有手工 Channel/业务状态，Manifest 没有存储或相册权限。
- 文档区分 Host 编译/安装与后续真机 Camera 行为证据。

## 验证命令

```bash
bash scripts/quality/media-capture-android.sh
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
adb install -r app/apps/demo/build/app/outputs/flutter-apk/app-debug.apk
make harness-check
git diff --check
```

## 环境限制

安装只证明 APK 可部署。订单评价入口未完成前不能从 App 发起拍摄；真机 Camera、权限、缩略图和资源释放
由后置 Flutter Consumer 任务验证，且证据不得记录设备 ID 或真实媒体。
