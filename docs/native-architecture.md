# 原生架构

## 当前状态

当前仓库只有 Flutter Demo 的 Android/iOS Host：Android 宿主位于
`app/apps/demo/android/`，iOS 宿主位于 `app/apps/demo/ios/`。仓库尚未创建通用
Native Module 或能力 Bridge Package；下文定义首个真实消费者出现后必须遵守的
布局和边界，不表示这些模块已经实现。

以下结构化块是 Harness 判断当前实现状态、布局、组件与依赖边的唯一输入。正文用于解释
约束，不作为实现状态推断来源。

<!-- native-architecture-contract:start -->
```json
{
  "schemaVersion": 1,
  "hosts": [
    {
      "platform": "android",
      "path": "app/apps/demo/android/",
      "status": "implemented"
    },
    {
      "platform": "ios",
      "path": "app/apps/demo/ios/",
      "status": "implemented"
    }
  ],
  "nativeModules": [],
  "bridgePackages": [],
  "layoutTemplates": {
    "androidNativeModule": "app/native/android/<module>/",
    "iosNativeModule": "app/native/ios/<Module>/",
    "flutterBridgePackage": "app/packages/app_<capability>_bridge/"
  },
  "components": [
    "host",
    "native_module",
    "dart_client",
    "android_bridge_adapter",
    "ios_bridge_adapter"
  ],
  "dependencyEdges": [
    {"from": "android_native_consumer", "to": "android_native_module"},
    {"from": "ios_native_consumer", "to": "ios_native_module"},
    {"from": "flutter_consumer", "to": "dart_client"},
    {"from": "dart_client", "to": "channel"},
    {"from": "channel", "to": "android_bridge_adapter"},
    {"from": "channel", "to": "ios_bridge_adapter"},
    {"from": "android_bridge_adapter", "to": "android_native_module"},
    {"from": "ios_bridge_adapter", "to": "ios_native_module"},
    {"from": "host", "to": "native_module"},
    {"from": "host", "to": "bridge_adapter_registration"}
  ],
  "forbiddenDependencyEdges": [
    {"from": "native_module", "to": "flutter"}
  ]
}
```
<!-- native-architecture-contract:end -->

## 目标与非目标

本契约用于让纯原生消费者和 Flutter 消费者复用同一平台能力，并使模块公共 API、
内部实现、依赖方向、生命周期和验证方式可以被声明与审查。Harness 不判断模块属于
业务还是基础设施，也不替项目决定模块粒度和所有者。

本契约不创建空 Native Core、业务模块或 Flutter Plugin，不选择具体能力、系统 API、
UI 框架、最低系统版本或 formatter/linter 版本，也不定义任何 Channel method、event、
Payload 或产品行为。只有真实模块任务可以补充这些事实。

## 术语与职责

| 术语 | 职责 | 禁止承担 |
| --- | --- | --- |
| Native Module | 用 Kotlin 或 Swift 暴露传输中立的原生公共 API，拥有能力状态机、资源和平台 SDK 交互 | import Flutter 类型、解析 Channel Payload、通过 Channel 调用自身能力 |
| Dart Client | 向 Flutter Consumer 暴露聚焦 API，拥有 Wire Model、Codec 和 MethodChannel/EventChannel 调用 | 直接依赖 Kotlin/Swift Module、承载平台 SDK 对象或原生资源生命周期 |
| Android Bridge Adapter | 依赖 Android Native Module，在 Android 边界映射 Wire DTO、Native Model、错误和取消 | 拥有被委托的能力、把协议映射推给 Host |
| iOS Bridge Adapter | 依赖 iOS Native Module，在 iOS 边界映射 Wire DTO、Native Model、错误和取消 | 拥有被委托的能力、把协议映射推给 Host |
| Host | 提供进程入口，接入平台生命周期，装配 Native Module，并注册对应平台 Bridge Adapter | 堆积业务状态机、资源生命周期或协议映射 |
| Native Consumer | 运行在 Android 或 iOS Runtime、直接调用对应 Native Module 的消费者 | 为调用原生能力绕经 Flutter 或 Channel |
| Flutter Consumer | 只调用 Dart Client 的 Flutter 业务或基础设施代码 | import 平台 Adapter 或原生 Module 实现 |

模块的分类、粒度和业务归属由项目根据真实消费者决定。无论如何分类，已声明模块都必须
明确公共 API、内部实现、依赖方向、生命周期所有者和验证方式。

## 依赖方向

跨 Runtime 调用遵循以下单向关系：

```text
Android Native Consumer -> Android Native Module
iOS Native Consumer -> iOS Native Module

Flutter Consumer -> Dart Client -> Channel -> Android Bridge Adapter -> Android Native Module
Flutter Consumer -> Dart Client -> Channel -> iOS Bridge Adapter -> iOS Native Module

Host -> Native Module
Host -> Bridge Adapter registration
Native Module -x-> Flutter
```

Android 原生消费者和 iOS 原生消费者直接依赖各自平台的 Native Module，不需要 Flutter
Engine。Flutter Consumer 只依赖 Dart Client；Dart Client 只拥有 Wire Model 和 Channel
调用。两端 Bridge Adapter 分别依赖对应 Native Module，并在边界完成 Wire DTO 与
Native Model 映射。Native Module 不得 import Flutter 类型，也不得通过 Channel 反向
调用自身能力。

## 目录约定

通用原生代码在首个真实模块出现后按平台落位：

```text
app/native/android/<module>/
├── build.gradle.kts
└── src/

app/native/ios/<Module>/
├── Package.swift
├── Sources/
└── Tests/
```

需要跨 Runtime 的能力使用聚焦的 Flutter Plugin Package：

```text
app/packages/app_<capability>_bridge/
├── pubspec.yaml
├── lib/                         # Dart Client、Wire Model、Codec、Channel 调用
├── android/                     # Android Bridge Adapter 与注册入口
└── ios/                         # iOS Bridge Adapter 与注册入口
```

不得建立汇总所有原生能力的万能 `app_native` Package。只有单平台 Native Consumer 时，
无需为保持目录对称而创建 Flutter Plugin 或另一平台空模块；支持范围由真实任务声明。

## 公共 API 与内部实现

Native Module 的公共 API 使用所属语言的稳定值类型、结果类型、异步序列和取消句柄，
不暴露 Flutter Channel 类型、Wire Map、宿主类或不必要的系统 SDK 对象。平台 SDK 对象
留在内部实现，只有调用者确实需要拥有且生命周期清楚时才进入公共 API。

公共 API 必须说明：

1. 输入、输出和可观察事件的语义。
2. 调用线程、回调线程和并发保证。
3. 资源由谁创建、持有、停止和释放。
4. 错误、取消、重复调用及部分成功的行为。
5. 所需权限、文件范围和平台限制。

Bridge 的 Wire Model 是跨 Runtime DTO，不是 Native Module 的公共 Model。两端 Bridge
Adapter 显式映射二者，避免 Channel 约束污染直接原生消费者。

## 构建图与依赖声明

### Android

Android 默认使用 Kotlin、Gradle Kotlin DSL、Kotlin 结构化并发与 Flow、AndroidX。
具体 UI 技术和 System API 由真实模块决定。

```text
Android Native Consumer
        -> Native Module Gradle project

Flutter Host
        -> Flutter Plugin registration
        -> Android Bridge Adapter
        -> Native Module Gradle project
```

- Native Module 的插件、依赖和测试配置声明在
  `app/native/android/<module>/build.gradle.kts`。
- 参与构建的 Host 或纯原生工程在其 `settings.gradle.kts` 中显式 include 该 Module，
  并通过版本库相对 `projectDir` 定位；消费者在自己的 `build.gradle.kts` 中声明 project
  dependency。
- Android Bridge Adapter 的 Module dependency 声明在
  `app/packages/app_<capability>_bridge/android/build.gradle.kts`；注册入口留在该目录，
  Host 只通过插件注册接入。

首个真实模块必须用仓库锁定的 Flutter、Android Gradle Plugin、Kotlin 和 Gradle 组合验证
include 路径与 Plugin 构建接线，再把实际命令写入模块文档；本契约不提前锁定新版本。

### iOS

iOS 默认使用 Swift、Swift Concurrency、本地 Swift Package 与 Apple Framework。Flutter
Plugin 仍可由 CocoaPods 管理；具体 UI 技术和 System API 由真实模块决定。

```text
iOS Native Consumer
        -> local Swift Package product

Flutter Host
        -> Flutter Plugin registration
        -> iOS Bridge Adapter
        -> local Swift Package product
```

- Native Module 的 Product、Target、平台依赖和测试 Target 声明在
  `app/native/ios/<Module>/Package.swift`。
- 纯原生消费者在自身 `Package.swift` 或 Xcode Package Dependencies 中直接声明本地
  Package 与 Product dependency。
- iOS Bridge Adapter 源码与注册入口位于
  `app/packages/app_<capability>_bridge/ios/`。Flutter 3.35.7 的 SwiftPM Plugin manifest
  固定位于
  `app/packages/app_<capability>_bridge/ios/app_<capability>_bridge/Package.swift`；该 manifest
  通过版本库相对路径（从 manifest 目录到 Module 时为
  `../../../../native/ios/<Module>`）声明本地 Native Package 和 Product dependency。
- 若沿用 CocoaPods，Native Module 在
  `app/native/ios/<Module>/<Module>.podspec` 提供可解析的 Pod；Plugin 的
  `app/packages/app_<capability>_bridge/ios/app_<capability>_bridge.podspec` 只使用
  `s.dependency '<Module>'` 声明名称依赖，不传递 `:path`。最终 Flutter Host 在
  `app/apps/demo/ios/Podfile` 使用仓库相对
  `pod '<Module>', :path => '../../../native/ios/<Module>'` 提供本地来源。

首个真实模块必须先用仓库锁定的 Flutter、Xcode、Swift 和 CocoaPods 组合验证所选接线
方式，并在 SwiftPM 与 CocoaPods 两条路线中选择且只保留一条。无论选择哪种集成，
Adapter 到 Native Module 的构建依赖必须
进入版本控制，不得靠本机配置，也不得把 Wire 映射退回 Runner 或 AppDelegate。

## Host 装配

Host 只负责：

1. 进程和 Flutter Engine 入口。
2. 把 App/Scene/Activity 生命周期信号交给需要它的模块。
3. 创建进程级依赖并装配 Native Module。
4. 通过插件注册机制或显式装配点注册对应平台 Bridge Adapter。

当前 Android `MainActivity` 只是 `FlutterActivity`，iOS `AppDelegate` 只调用生成的插件
注册入口；这说明宿主已存在，不说明任何通用原生能力已经接线。后续实现不得把业务
状态机、采集会话、文件所有权或 Wire DTO 映射堆积在 `MainActivity`、`AppDelegate`
或 Runner 中。

## Bridge 边界

具体跨 Runtime 协议以 [`bridge/README.md`](./bridge/README.md) 及对应能力契约为准。
Dart Client 负责 Wire API；Android Bridge Adapter 与 iOS Bridge Adapter 负责各自边界
的 DTO/Model、错误和取消映射；Native Module 拥有实际能力。Bridge 只是适配层，不能
成为直接原生消费者的必经路径。

Channel 回调必须切回平台 UI 线程，但这不意味着 Native Module 的工作必须运行在 UI
线程。Adapter 负责遵守 Channel 线程要求，并把工作委托给模块声明的执行上下文。

## 生命周期与线程

- Native Module 明确进程级、页面级、会话级或单次调用级所有者；资源生命周期不得由
  GC、Engine 是否仍连接或 Host 类的偶然存活决定。
- Android 使用父级 `CoroutineScope`、结构化并发和 Flow；所有子任务随模块或会话关闭
  而取消，不创建无所有者的全局协程。
- iOS 使用 structured task、`async`/`await`、`AsyncSequence` 和必要的 Actor 隔离；
  不创建无法追踪或取消的 detached work。
- Host 只转发生命周期信号。Native Module 决定资源暂停、恢复和释放语义；Bridge
  Adapter 处理 Engine attach/detach、listener start/cancel 与模块会话之间的映射。
- UI/System API 要求主线程时必须显式切换；CPU 或 I/O 工作不得长期占用主线程。
- stop、cancel、detach 和 dispose 必须可重复调用，并在并发竞态下保持确定行为。

## 错误与取消

Native Module 使用平台原生的有类型错误表达能力语义，保留可诊断 cause，但公共错误
不得泄漏凭据、用户数据、绝对文件路径或底层 SDK 私有对象。Dart Client 不直接认识
这些类型；Bridge Adapter 按对应 Wire 契约映射为稳定 error code、message 和脱敏
details。

取消是生命周期事件，不默认等同于能力失败。每份模块和 Bridge 契约必须说明调用方取消、
Host 退后台、Engine detach、系统中断和资源被回收时的结果、终止事件及清理顺序。

## 文件与权限

- Android Manifest、iOS Info.plist/Entitlements 中的权限声明属于最终 Host；模块文档列出
  必需项和理由，Host 任务负责按真实产品范围接入。
- Native Module 可以提供权限状态或前置条件 API，但是否以及何时弹出系统授权 UI 由
  产品流程决定，不在模块初始化时隐式触发。
- 模块产生的临时文件、缓存和持久文件必须声明目录、保留期限、清理责任和并发访问规则。
- 跨 Channel 优先传输必要的基础类型、`Uint8List` 或有明确作用域的文件引用；不得传输
  平台 SDK 对象，也不得把不受控绝对路径当作长期公共标识。
- 权限拒绝、受限、仅部分授权和系统设置变化必须有稳定语义，不能静默降级为成功。

## 平台差异

Android 与 iOS 可以因系统能力、生命周期或授权模型产生有意差异，但差异必须写入模块
文档和 Bridge 契约，并由消费者显式处理。不得为了表面一致而隐藏能力缺失，也不得在未
声明的平台创建无行为的占位实现。

模块公共语义应尽量一致；具体类型、线程机制和资源句柄保持平台原生。跨 Runtime 需要
一致的部分由 Wire 契约定义，而不是要求两个 Native Module 共用 Flutter 类型。

## 依赖治理

- 优先使用平台官方公开 API、AndroidX、Apple Framework 和可复现的公开依赖。
- 原生依赖必须声明在实际消费者所属的 Gradle 或 Swift Package/Plugin 构建清单中；
  不在 Host 全局添加未使用依赖。
- 首个真实模块根据锁定工具链验证兼容版本、最低系统版本和构建接线；验证前不凭空固定。
- 新依赖需要记录来源、版本约束、许可证、平台要求和替换边界，不依赖本机绝对路径。
- 只有至少两个真实 Native Module 需要同一稳定能力，且下沉能保护依赖边界时，才考虑
  提取共享 Core；不得预建空 Core 或万能基础层。

## 测试层级与验证

1. Native Module 单元测试：不启动 Flutter，覆盖公共 API、状态机、并发、错误、取消和
   资源释放。
2. Bridge Adapter 测试：用 Native Module Fake 覆盖 Wire DTO/Native Model 映射、错误、
   listener 生命周期和线程切换；不得把 Fake 作为生产实现。
3. Dart Client 测试：覆盖 Codec、Channel 调用、事件订阅、取消与稳定错误映射。
4. Host/构建测试：构建所有声明支持的平台，验证 Module dependency 和插件注册可解析。
5. 端到端测试：有真实 Bridge 契约后，按声明平台验证同一公共行为和有意差异。

原生改动必须构建受影响平台。环境不可用时，任务证据明确列出未验证平台和文件；Harness
静态门禁不能替代 Gradle/Xcode 编译或原生测试。

## 任务所有权

- 新建或改变 Native Module 时，任务卡必须声明模块公共 API、消费者、项目认定的分类与
  所有者、生命周期、依赖、平台范围和验证命令，并同步本契约或对应模块详情文档。
- 新建或改变 MethodChannel/EventChannel Wire Contract 时，先更新 `docs/bridge/`，使用
  `bridge-engineer` 设计结构化协议并验收所有声明 Runtime；Bridge 不拥有 Native Capability。
- Android/iOS 单平台 Native Module、Bridge Adapter 和平台门禁分别由 `android-engineer`、
  `ios-engineer` 执行；Dart Client 使用 `task-executor`。实际工作扩展到另一平台或跨 Runtime
  集成时必须停止、更正结构化范围并重新拆卡。
- 基础能力只有出现真实复用或治理需求后才进入
  [`infrastructure-modules.md`](./infrastructure-modules.md)；进入索引不改变其原生边界。
- 架构 Review 检查依赖方向、公共类型、生命周期与验证证据，不替项目重新划分业务归属。
