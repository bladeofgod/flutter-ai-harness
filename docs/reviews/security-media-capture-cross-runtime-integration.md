---
task: media-capture-cross-runtime-integration
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - .github/workflows/ci.yml
  - Makefile
  - README.md
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/apps/demo/pubspec.yaml
  - app/apps/demo/ios/Podfile.lock
  - app/apps/demo/ios/Flutter/AppFrameworkInfo.plist
  - app/apps/demo/ios/Runner.xcodeproj/project.pbxproj
  - app/apps/demo/ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
  - app/apps/demo/ios/Runner/AppDelegate.swift
  - app/apps/demo/ios/Runner/Info.plist
  - app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt
  - app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json
  - app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift
  - docs/bridge/contracts/media-capture.wire.json
  - app/tool/harness_check.dart
  - app/lib/harness_validator.dart
  - app/lib/src/harness_validator.dart
  - app/lib/src/implementation_digest.dart
  - scripts/quality/test-harness.sh
  - scripts/quality/media-capture-android.sh
  - scripts/quality/media-capture-ios.sh
  - scripts/flutter-tool.sh
  - scripts/install-ripgrep.sh
  - docs/README.zh-CN.md
  - docs/architecture.md
  - docs/bridge/media-capture.md
  - docs/bridge/media-capture-android.md
  - docs/bridge/media-capture-ios.md
  - docs/infrastructure-modules.md
  - docs/infrastructure/media-capture.md
  - docs/infrastructure/media-capture-android.md
  - docs/infrastructure/media-capture-ios.md
  - docs/infrastructure/media-resources.md
  - docs/native-architecture.md
implementationDigest: 99f76f3de5525b46e7111bf052f4f394c22d3adebb1017f23dd65d4fee3e3af8
---

# Security Review：Media Capture 跨 Runtime 最终集成

## 结论

独立 Security Review 与修复复审通过，P0 0、P1 0、P2 0。Security Reviewer 未依赖普通 Review 结论，
只读核对 Host 权限与依赖边界、外部媒体输入、transfer/store ownership、跨 Runtime golden、CI、Harness、
文档和 evidence，没有修改实现。

## 已确认边界

- Android/iOS Host 只负责权限声明、模块装配和标准 Plugin 注册，不解析 Wire、不保存媒体 locator，也没有
  增加 Photo Library/shared storage 权限、Entitlement、CocoaPods fallback 或本机 framework path。
- 外部 picker/Camera 结果进入平台私有 transfer root 后才通过 scoped handle 暴露；URI canonicalization、
  symlink/traversal、MIME、长度、配额、TTL、tombstone、restart/detach/late cleanup 和无路径日志均由三端
  vectors、平台 Gate 与 Harness 交叉约束。
- Store commit 后释放 transfer/source lease，消息只持有 `MediaResourceId`；会话 reset、消息删除和 Registry
  dispose 按 owner 顺序卸载 Thumbnail/Viewer 并释放最终资源，没有把临时路径作为消息身份传播。
- golden 绑定 Dart/Kotlin/Swift 消费者的路径和实现摘要；Harness 对契约与消费者漂移失败关闭，防止只保留
  测试文件名或局部断言造成伪通过。
- Info.plist 使用结构化 XML 校验唯一、非空字符串权限说明；CI 与证据脚本不记录真实媒体、URI、handle、
  设备 ID、主机路径、公司设计信息或凭据，也没有增加签名、发布、commit 或 push 能力。

## Workspace 消费检查器影响

本轮只增加根工具的静态 AST 消费盘点和架构命令说明。`analyzer 10.0.1` 已存在于 lockfile，版本、来源和
SHA-256 未变；未修改 Wire、Host、平台权限、CI 或发布能力。消费模式当前不接入默认 lint，不影响跨
Runtime 构建路径。

## 剩余边界

Android API 23 instrumented、Camera/Gallery 主动流程和 iOS 真机 Camera/Microphone、系统权限 UI、硬件中断、
真实帧及性能仍需人工设备验收。现有构建、Simulator 与静态门禁只证明可编译、契约和软件层行为，不把这些
结果提升为硬件能力已通过。

## iOS 综合修正后的最终复审

本轮没有修改 Capability/Wire 结构或 Flutter/Android 消费语义。iOS 对焦转换保持 Native-only；audio
input 生命周期和 retake 文件状态边界进一步收紧；Bridge Gate 的 Simulator 输入、结构化诊断与单次重试
均 fail closed。独立 Security Reviewer 确认 P0/P1/P2 0/0/0；完整 Gate 以 107/52/69 精确测试数通过，
方向适配明确不在本轮范围内。

## Workspace SwiftPM Bootstrap 配置复核

Workspace 根 `app/pubspec.yaml` 现在与 Demo Host 一样使用项目级
`flutter.config.enable-swift-package-manager: true`，使 Melos 从 Workspace 根执行的 `flutter pub get`
不依赖用户或 CI Runner 的全局 Flutter 配置。该配置没有新增 Package、远程 URL、脚本、CI 权限或发布
能力，`pubspec.lock` 内容保持不变；Bridge 仍只通过仓库内本地 Package 和相对路径接线。

隔离 `HOME`/XDG 配置下的 `melos bootstrap` 与完整 `make bootstrap` 均通过，确认默认 Runner 环境不会
再因 SwiftPM 全局开关缺失而失败。既有依赖来源、Host、Plugin discovery 和安全结论不变，当前
P0/P1/P2 仍为 0/0/0；独立增量安全复核未发现新的供应链、凭据或外部写入通道风险，本报告按原
implementationFiles 集合重新绑定摘要。

## Flutter 3.41.9 UIScene Host 复审

Flutter 3.41.9 将 Runner 迁移到单场景 `FlutterSceneDelegate`，`AppDelegate` 通过
`FlutterImplicitEngineDelegate` 把原有生成插件集注册到隐式 Engine 的 registry。Camera、
Microphone 和 Photo Library 用途说明不变，没有新增 Entitlement、后台模式、多窗口、远程代码
或动态插件路径。`AppFrameworkInfo.plist` 移除 Framework 元数据中的最低系统字段，Runner
deployment target 未改变。

Harness 只接受单一 `didInitializeImplicitFlutterEngine` 回调和单一
`engineBridge.pluginRegistry` 注册，并用失败 Fixture 拒绝旧 `with: self` 及重复装配。独立
Security Reviewer 确认 P0/P1/P2 0/0/0；iOS 原生 Gate、临时 SwiftPM Host 和真实 Runner
no-codesign Debug Build 通过。真机首次 scene 激活、权限 UI 和后台恢复仍属人工验收边界。

## CI 原生门禁工具链修正复审

三个 CI Job 统一通过仓库脚本安装 ripgrep 15.1.0。Linux x64、macOS ARM64 和 macOS x64 分别绑定
官方 GitHub Release 资产及固定 SHA-256；内容在解压前校验，未知平台失败关闭。安装只写
`RUNNER_TEMP` 并通过受控 `GITHUB_PATH` 暴露，不执行 `sudo`、APT 或 Homebrew 安装脚本。下载限制
HTTPS/TLS、连接和总超时以及有限重试，不会在失败时回退到未校验来源。

iOS Gate 改由仓库 Flutter wrapper 解析 SDK，继续精确拒绝非 3.41.9 版本。独立 Security Reviewer
复审确认此前未固定系统包的 P2 已关闭，当前 P0/P1/P2 为 0/0/0。剩余信任边界是 GitHub Release、
Runner 自带 TLS/归档/摘要工具和托管 Runner；Release 不可用时 CI 会明确失败。

## CI 原生平台门禁增量复审

Android 只为 JUnit BOM 5.10.2 与 5.9.2 的既有 `.module` artifact 增加 Gradle 官方生成的 SHA-256，
repository、版本与 strict verification 策略不变。iOS Core/UI Simulator test 增加固定 destination 等待，
并只对没有结构化 failed test 的基础设施类失败重试一次；缺失或不可读 result bundle 也只获得这一次
重试，第二次仍须精确通过全部测试。

iOS 最终诊断仅输出固定类别与整数计数，不传播 result JSON、路径、Simulator 标识或构建日志。独立
Security Reviewer 确认两端增量均为 P0/P1/P2 0/0/0。Android strict 配置阶段与 iOS 107/52/69
Simulator 运行层通过；本机 Xcode 26.5 临时 Host 失败保持单独记录，最终 Xcode 16.4 结论以 CI 为准。

## CI 平台专属工具与 Simulator 生命周期复审

Android metadata 进一步固定既有 AGP 8.9.1 的 AAPT2 Linux JAR；摘要由 Gradle 官方流程生成，临时解析
configuration 已移除，最终依赖图、repository 和 strict verification 策略不变。平台 classifier 扫描确认
当前仅 AAPT2 需要 osx/linux 双摘要，两者均已覆盖。

iOS Gate 使用 `simctl bootstatus -b` 显式完成 selected available Simulator 的冷启动，只在初始非 Booted
时记录 Gate ownership，并在正常退出或信号中恢复 shutdown；用户原本 Booted 的设备不受 cleanup 影响。
xcodebuild Core/UI 运行关闭并行测试，原有精确计数和一次基础设施重试边界不变。标识与原始 boot/build
输出继续脱敏，本地中断验证确认没有残留 Booted Simulator 或构建进程。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。

## 2026-08-04 CI Check 超时预算增量复核

`check` Job 的有界超时由 20 分钟调整为 30 分钟，以容纳完整 Repository Check 在冷 Runner 上的正常
执行时间。检查命令、通过标准、权限、依赖来源、网络访问和并发取消策略均未改变；超时后仍由 GitHub
Actions 失败关闭。该调整不扩大既有信任边界，P0/P1/P2 仍为 0/0/0，摘要按当前
implementationFiles 重新绑定。

## Validator Library 路径迁移复审

2026-08-06 独立安全复审确认 Validator 仅拆分为不可变 Library 结果和薄 CLI，未放宽本报告的既有安全约束。绑定已覆盖公开入口、真实 Validator、摘要计算器、CLI 和 Shell Fixture。

## Workspace 冗余依赖清理影响

Demo 移除了对 Bridge 的冗余直连，但 `app_features -> app_media_capture_bridge` 保持不变；pub graph、两端
Plugin discovery 与生成注册器都证明传递可达，Android Debug APK 和 iOS 无签名 Debug App 均构建通过。
Host、Wire、权限、Entitlement、媒体 locator 与 cleanup 未修改，P0/P1/P2 维持 0/0/0。

## Wire 生成 Profile 影响复审

2026-08-06 复审确认生成工具只产生闭合 descriptor 与无副作用 primitive，未迁移或修改三端生产 Codec、Host、权限、Entitlement、媒体 locator、线程或 cleanup。Wire V3/Capability V4 projection 不变，P0/P1/P2 维持 0/0/0。

## Wire Formatter 工具依赖影响

根 Workspace 精确固定 `dart_style 3.1.7`，只供 Wire generator 内存格式化使用，不进入 Dart Runtime
Package、Android/iOS Host 或 Native 产物。formatter 不再启动子进程或创建系统临时文件；Host、权限、
Entitlement、媒体 locator 与 cleanup 均未修改，P0/P1/P2 维持 0/0/0。

## 2026-08-07 Android Transfer 发布兼容性增量复审

共享 Android Transfer Store 从 hard-link/no-replace 发布改为最终路径 exclusive create；独立报告
`security-media-capture-android-transfer-publish-compatibility-correction.md` 结论为 P0/P1/P2 0/0/0。
跨 Runtime Wire、Dart Client、iOS、Host、权限、Entitlement 和媒体 locator 边界未扩大；本报告摘要按当前
implementationFiles 重新绑定。无 ready emulator 的设备矩阵缺口保持明确记录。

## README Harness 定位说明影响

2026-08-07 中英文 README 只新增 Harness 主体、参考实现和当前技术栈适配关系的定位说明。该文档变更
不修改命令、Agent 权限、依赖来源、Host、Wire、平台权限、媒体 locator 或资源生命周期；本报告摘要按
既有 implementationFiles 重新绑定，原安全结论和人工设备验收边界不变。
