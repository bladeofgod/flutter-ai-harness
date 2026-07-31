# Android Media Capture 单平台验证

> 当前状态：2026-07-28 专项静态 Gate 已通过；本机没有 ready emulator，因此 instrumented test 未运行。
> 该结果不等价于 Flutter Host 构建或真机验收。

[返回原生架构](../native-architecture.md) ·
[Android Core 说明](../infrastructure/media-capture-android.md) ·
[Android Bridge Adapter 说明](../bridge/media-capture-android.md)

## 执行入口

Android 专项门禁使用 `app/native/android/media_capture_gate/` 内可提交的专用 Gradle 8.12 wrapper，不使用
系统 Gradle 或 Demo Host 中被忽略的生成 wrapper：

```bash
bash scripts/quality/media-capture-android.sh
```

调用环境必须提供 JDK 17 或更高版本、Android SDK 和仓库锁定的 Flutter 3.35.7。wrapper jar 和
distribution 分别校验 Gradle 官方 SHA-256；所有外部 artifact 使用 strict dependency verification
metadata。脚本还会拒绝错误的 wrapper/Flutter 版本、Gradle 输入摘要、动态依赖、本机仓库、本机绝对
路径、symlink、未批准的生产依赖和逆向模块引用，然后执行：

1. Core、Native UI、Bridge Adapter 三个独立 Gradle 工程的 `clean test lint assembleDebug
   assembleRelease`。
2. 三个工程的 `debugRuntimeClasspath` 依赖解析，保留可复现的实际依赖图；任何 Gradle build/settings/
   properties 或 verification metadata 变化都必须显式更新 reviewed digest。
3. 直接读取当前 Capability V3 与 Wire V2 JSON，再与 Android Core enum/API、Native UI config、Adapter
   method/event/error/channel/boundary 对齐；同时强制重跑 renderer、attachment、thumbnail、UI lifecycle、
   Bridge lifecycle 和 bounded transport 契约类，并逐类检查非空、0 skipped、0 failure。
4. 每次静态 Gate 都编译独立的无 Camera instrumented lifecycle/UI suite；只在恰好存在一个 ready emulator
   且没有物理设备连接时，以私下绑定的 emulator serial 运行。否则明确输出未运行原因，不记录设备 ID。

本平台 Gate 直接消费现有 Capability/Wire JSON，不创建 Android 私有副本。后续跨 Runtime Integration
仍负责新增同一组 Dart/Kotlin/Swift 共同消费的 JSON/golden case；它们补充跨 Runtime 编解码 parity，不
替代这里对当前权威 Contract 的平台绑定。

## 依赖图

生产依赖方向固定为：

```text
Android Core -> CameraX / ExifInterface / Coroutines
Native UI    -> Android Core / AndroidX UI-Lifecycle / Coroutines
Bridge       -> Android Core / Native UI / Flutter embedding API / AndroidX / Coroutines
```

- Core 不包含 Flutter、Channel、Wire Map 或其它仓库 module dependency。
- Native UI 不包含 Flutter 或 CameraX implementation API，只通过 Core 的类型化公共能力工作。
- Bridge 可以依赖 Core/UI 和 Flutter embedding，但不能取得文件路径、URI、CameraX provider 或 renderer
  内部 source。
- 三个 Gradle 工程只使用精确版本、`google()`、`mavenCentral()` 和 Bridge 所需的 Flutter 官方 Maven。
- 专项脚本为三个模块维护生产依赖 allowlist；新增依赖必须先说明用途并更新门禁，不能静默进入图中。

当前依赖均有生产用途：CameraX 四个 artifact 分别提供 camera2 backend、Lifecycle binding、录像和
`PreviewView`；ExifInterface 用于照片元数据清理；AndroidX Core/Lifecycle 用于权限、UI owner 和 Activity
边界；Coroutines 用于异步状态与资源清理；Flutter embedding 只存在于 Bridge transport。未被生产代码
使用的 Adapter `activity-ktx` 已由本门禁发现并移除。

## 竞态与契约矩阵

本地单测和 Robolectric 重点证明下列平台内语义，最终命令结果见
`docs/reviews/test-evidence/media-capture-android-quality-gate.log`：

| 范围 | 重点验证 |
| --- | --- |
| Session / lease | cancel、timeout、release、expiry、restart、cleanup retry、late result、exactly-once |
| Live surface | generation、single attach、replacement、detach、rotation、background、owner destroy |
| Photo/video preview | 私有 source、generation、retake/confirm、terminal cleanup、旧 callback 丢弃 |
| Renderer production wiring | CameraX `SurfaceProvider` 实际安装/清空、照片方向修正、真实 `VideoView` source/player target 清理 |
| Native UI | 拍照/录像、长按、三终态、surface retirement、Activity/Lifecycle、cleanup ownership |
| Bridge | 14 methods、5 events、权限身份、Activity/Engine replacement、bounded decode、严格 Wire V2 |
| Thumbnail | 64..512 edge、524288-byte bound、固定 video poster、并发/内存预算、metadata 拒绝 |

`MediaCaptureRenderViewTest` 和 Gate 注入的 `MediaCaptureRenderBackgroundGateTest` 直接针对 concrete
production surface 运行 Robolectric：live preview 安装真实 CameraX `Preview.setSurfaceProvider`，照片从
模块私有文件解码并物理旋转，视频把模块私有 source 交给真实 `VideoView` pipeline。replacement、detach、
background、owner destroy 和 terminal path 会使旧 mutation gate 失效并清空 provider/player/content；
旧 generation 不能再次修改 target。

## 分层结果

| 层级 | 本任务状态 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| Local unit（Debug/Release） | 通过：Core 66/66、UI 38/38、Adapter 37/37，0 skipped/failure | 类型化状态机、Contract JSON、Wire codec、边界容量和确定性竞态 | Android Framework/真实硬件行为 |
| Framework Fake | 通过，包含在上述双变体测试 | Camera/文件/权限异常与资源 ownership 顺序 | CameraX、系统权限 UI 和厂商实现 |
| Robolectric | 通过，包含在上述双变体测试 | Android Lifecycle/View、生产 wrapper 和 renderer 接线 | 真实出帧、编码器、设备性能 |
| Instrumented | APK 编译通过；运行未执行：没有 ready emulator | 有唯一 emulator 时验证 Activity recreate、Core/UI/Bridge load 和 Native-only surface API | 当前无运行结果不得当作通过 |
| Flutter Host | 未接线、未构建 | 后续证明 plugin registration、Manifest、Gradle 和 APK | 本专项 Gate 不是 Host build |
| 真机 | 未运行 | 后续验证 Camera/Microphone、权限、拍照、录像、中断与性能 | Fake/Robolectric 不能替代 |

## 设备与集成缺口

当前任务不修改 Android Host、Manifest 权限、Flutter plugin registration、根 Makefile 或 CI。这些共享入口
由跨 Runtime Integration 任务统一接线。本任务也不保存设备标识或真实媒体。

本次 Gate 同时完成三个工程的 lint、Debug/Release AAR assemble、`debugRuntimeClasspath` 解析、Gate
fixture lint/assemble/instrumented compile 和重点契约矩阵重跑。Core/UI/Adapter 的六个 AAR 均生成；未
发现动态版本、本机仓库、本机路径、未批准生产依赖或 dependency verification 漂移。

后续至少需要在明确授权的设备环境验证：

- Camera 权限允许/拒绝/永久拒绝，以及只在录音录像时请求 Microphone。
- 前后摄真实出帧、拍照、长按录像、60 秒自动停止、硬件/来电/后台中断。
- Activity 配置变更和进程恢复时 provider/player/lease 的实际释放。
- 大尺寸照片、视频 poster、并发 thumbnail 的内存峰值与性能。
- Flutter Debug Host 的标准 plugin registration、全屏 Native UI 和 Dart -> Adapter -> Core 闭环。
