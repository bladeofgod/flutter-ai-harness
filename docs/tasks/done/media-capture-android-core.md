---
executor: android-engineer
platforms: [android]
workKinds: [native]
blockedBy:
  - media-capture-render-surface-capability-evolution
securityReview: required
---

# 实现 Android Media Capture Native Core

## 输入与事实来源

- 最新 Capability V3、Schema/详情文档与本任务现有 Review 历史。
- `docs/native-architecture.md`、`kotlin-android-standards`、`native-testing-strategy`。
- 锁定 Host 工具链：Flutter 3.35.7、AGP 8.9.1、Kotlin 2.1.0、Gradle 8.12、Java 11；CameraX
  具体兼容版本由本任务使用该工具链构建验证后固定。

## 目标

- 在独立 Android Native Module 中实现 transport-neutral、类型化的 Media Capture Core。
- 使用 Kotlin、Gradle Kotlin DSL、Coroutine/Flow、AndroidX/CameraX，实现 Capability 的操作、状态、
  权限前置、资源、文件租约、Native Preview、缩略图和稳定 Failure 语义。
- 让 Android 原生消费者不经过 Flutter 即可直接依赖并测试该模块。

## 非目标

- 不实现 Flutter Channel/Adapter、全屏 Native UI、Host 注册或 Shoppe 页面。
- 不读取 Wire key/Map，不 import Flutter，不把 CameraX 对象暴露到公共 API。
- 不修改 Android Manifest/Host 权限，不等待专用 Figma，不实现滤镜、美颜、裁剪、上传或相册。

## 实现路径与所有权

本任务只写：

- `app/native/android/media_capture/**`
- `docs/infrastructure/media-capture-android.md`
- 本任务自己的测试、Review 与 evidence 文件

不得修改 `docs/infrastructure/media-capture.md`、Capability/Wire Schema/Profile、
`app/packages/app_media_capture_bridge/**`、`app/apps/demo/**`、root Validator、共享 Registry、CI、
Makefile 或 iOS 路径。需要共享契约变更时停止并新建契约任务。

## 实现要求

1. 公共 API 使用 Kotlin sealed/value types、稳定错误和可取消异步模型，逐项映射最新 Capability；
   构造注入 CameraX wrapper、文件系统、Clock、随机源、Dispatcher 和 CoroutineScope。
2. 使用平台 CSPRNG 创建至少 128-bit、最长 128 字符、module-instance scoped 且永不复用的 Session/
   Media handle；只做 strict registry lookup，不从路径派生或拼接。
3. 单活动 Session、每 handle Media 状态机、重复 stop/cancel/release、300 秒 tombstone、预览 TTL、
   24 小时 lease、60 秒 read grace、restart 清理和失败 cleanup 必须与 Contract 一致，并覆盖竞态。
4. Camera/Microphone 只在明确用户动作和所需模式下请求/使用；Core 暴露权限状态/请求前置，不在
   初始化时弹权限。Photo Library 不请求。
5. 媒体写入 App 私有临时区；确认前清理位置/设备元数据。原始读取只在 callback scope 内；最新
   缩略图 API 只为 active confirmed lease 生成不超过契约尺寸/字节的 upright JPEG 净化 copy，按
   固定 poster-frame policy 返回完整元数据，不泄漏原图、路径。
6. 实现 Capability V3 live/unconfirmed attachment 与 concrete platform render surface。模块提供具体
   `MediaCaptureRenderView`；其内部拥有 CameraX `PreviewView`/SurfaceProvider、photo renderer 与 video
   player surface，Core capability model 不暴露这些对象。Live 必须真实安装 `Preview.setSurfaceProvider`，
   photo/video preview 必须真实加载模块私有 source。UI 只持有模块 surface，不能访问 provider、CameraX
   source、Session、路径或原始 read scope。不得保留外部无法消费的 marker-source/空 Adapter 假边界。
   Core registry 继续拥有 generation、identity、强 binding、revoke/detach 和 terminal cleanup。
7. CameraX capture、录像时限、镜头/闪光/对焦/缩放、系统中断与 encoding/storage failure 都映射
   稳定 Capability 语义。Coroutine cancellation 必须传播，UI/System API 才切 Main Dispatcher。
8. 依赖只写模块自身 Gradle 文件并固定可复现版本；记录来源、版本和锁定 Host 工具链构建结果。

## 测试与验收

- Kotlin 单测覆盖所有状态/operation、非法输入、权限状态、幂等 close、并发 session、取消、Clock
  驱动 TTL/grace/tombstone、CSPRNG registry、文件 cleanup、两类 Render attachment generation/
  attach/detach/revoke/rotation/background/owner destroy、EXIF 净化和确定性 poster/bounded thumbnail。
- CameraX/File/Clock/Dispatcher 使用窄 Framework Fake；Fake 通过不得宣称真实相机/权限已验证。
- Android 原生消费者测试直接调用 Core，编译图中不存在 Flutter import 或 Wire Map。
- Robolectric/production wrapper 测试证明 surface provider 安装、photo/video renderer、replacement、
  detach content clear、owner destroy 与 stale generation gate；Fake 不冒充真机实际出帧。
- 模块测试和 lint 在锁定 Gradle/JDK 工具链通过，依赖解析可复现。

## 验证命令

```bash
app/apps/demo/android/gradlew -p app/native/android/media_capture test lint assembleDebug assembleRelease
make lint
make harness-check
git diff --check
```

## 环境限制

归档证据使用 Android SDK、JDK 和可解析的公开 Maven 依赖；不要求 Flutter Host 接线。Local/Fake 测试不能
证明真实 Camera、Microphone 权限框、硬件中断或录像性能，这些在 Android Gate/最终集成中准确留证。
