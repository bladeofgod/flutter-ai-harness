---
executor: task-executor
platforms: []
workKinds: [documentation, planning]
blockedBy:
  - media-capture-flutter-package-registration
  - native-harness-architecture-foundation
securityReview: required
---

# 锁定 iOS Media Capture SwiftPM Host 接线路线

## 输入与事实来源

- Flutter 3.35.7 官方 SwiftPM Plugin 模板与当前 Xcode/iOS SDK。
- `docs/native-architecture.md`、现有 iOS Adapter、Export Adapter、Quality Gate 和最终 Integration 任务卡。
- 已确认探针事实：官方 SwiftPM Plugin Package 单独执行 generic iOS Simulator `xcodebuild` 时，
  `import Flutter` 无法解析；Flutter Plugin 必须由 Flutter Host 生成的
  `FlutterGeneratedPluginSwiftPackage` 注入 Flutter 构建依赖。
- 当前 Demo iOS Host 仍使用 CocoaPods，生产 Host 的 SwiftPM 迁移尚未执行。

## 决策

- iOS Media Capture 只采用 Flutter 3.35.7 官方 SwiftPM Plugin 路线，不增加 CocoaPods fallback。
- Plugin Package 的纯 Swift Bridge Core 与 Flutter 注册 Target 分开验证：前者可独立进行 iOS SDK
  compile/test，后者必须在 Flutter Host 图中编译。
- Adapter 和单平台 Gate 使用可清理的临时 Host fixture 验证 Plugin discovery；最终 Integration
  才迁移并提交真实 Demo Host 的 SwiftPM 接线和 no-codesign build 证据。

## 目标

- 修正“Plugin Package 可以单独解析 Flutter 模块”的错误验收前提。
- 锁定不依赖本机 framework path、全局 Flutter 配置或 CocoaPods fallback 的可执行 Host 路线。
- 让 Adapter、Export Adapter、iOS Gate 和最终 Integration 的所有权、命令与证据层级一致。

## 非目标

- 不实现 Adapter、Transfer Store、Host 接线或业务功能。
- 不修改 Dart Client、Capability/Wire、Core/UI、Runner、Podfile、Xcode project 或 Flutter Plugin 源码。
- 不把临时 Host fixture 当作真实 Demo Host 已迁移，也不把 SDK compile 当作真机 Camera 验证。

## 实现路径与所有权

本任务只写：

- `docs/native-architecture.md`
- `docs/tasks/done/media-capture-ios-bridge-adapter.md`
- `docs/tasks/media-capture-ios-export-bridge-adapter.md`
- `docs/tasks/done/media-capture-ios-quality-gate.md`
- `docs/tasks/media-capture-cross-runtime-integration.md`
- `docs/reviews/security-native-harness-agent-standards.md`（只追加本次独立影响复审并刷新摘要）
- 本任务 Review/Security/evidence

## 实现要求

1. 原生架构文档将 Media Capture iOS 路线锁定为 SwiftPM：Plugin manifest 保持
   `ios/app_media_capture_bridge/Package.swift`，只使用仓库相对 Core/UI Package dependency；删除把
   CocoaPods 继续视为该模块候选 fallback 的描述。
2. 文档明确 Flutter 官方 Plugin Package 不声明可独立解析的 Flutter binary target；
   `FlutterGeneratedPluginSwiftPackage` 由开启 SwiftPM 的 Flutter Host 生成并注入。因此不得用 Plugin
   Package 独立 `xcodebuild` 作为 Flutter API 编译证据，也不得把本机 `Flutter.xcframework` 绝对路径
   写入 manifest、脚本或 Xcode 配置。
3. Base Adapter 的 Package 拆为纯 Swift Bridge Core target 与 Flutter Plugin target。Codec、请求注册、
   lifecycle coordinator 和可替换 Core/UI 协议留在 Bridge Core；只有 Channel handler、Flutter result/
   event sink、registrar 和 presenting owner lookup 留在 Plugin target。
4. Base Adapter 验收改为：Bridge Core generic iOS Simulator SDK compile/test + 临时 Flutter Host
   no-codesign build。临时 Host 必须从仓库 Demo/锁定模板构造、可清理、使用仓库内 Plugin 路径，且
   只在临时副本的 `pubspec.yaml` 写入项目级 `flutter.config.enable-swift-package-manager: true`；不得修改
   真实 Host，也不得依赖或修改用户全局 Flutter SwiftPM 开关。
5. Export Adapter 延续同一 target/Host 路线；Transfer Store 与 sink 进入 Bridge Core，只有 Flutter
   callback 映射留在 Plugin target。删除 Plugin Package 独立编译命令。
6. iOS Quality Gate 分清 Core/UI/Bridge Core 的独立 iOS SDK compile 与临时 Host 中 Plugin compile；
   临时 Host 是单平台门禁的 Plugin discovery 证据，不得误述为真实 Runner 已接线。
7. 最终 Integration 独占真实 `app/apps/demo/ios/**` 迁移：使用 Flutter 生成的
   `FlutterGeneratedPluginSwiftPackage`、提交必要 Xcode project 变化，并执行 Demo Runner
   `flutter build ios --debug --no-codesign`。Host 只注册/装配，不承载 Wire 或能力状态。
8. 所有任务继续禁止 CocoaPods fallback、本机绝对 framework path、手工复制 Flutter binary、远程
   分支依赖和把 generated ephemeral package 入库；路线失败必须返回本架构边界复审。
9. `docs/native-architecture.md` 变化导致既有 Agent 标准 Security Review 摘要失效时，必须由独立
   Security Reviewer 重新核对 Agent 工具、任务路由、任务路径、网络、凭据、提交、推送和发布能力
   均未变化；确认原结论仍成立后才可追加影响说明并刷新原文件集合摘要。

## 同时编写的验证

- 留证官方 Flutter 3.35.7 SwiftPM Plugin 独立 package compile 的失败分类仅为缺少 Host 注入的
  `Flutter` module，不是 Core/UI、本地 Package path 或 Adapter 业务错误。
- 静态核对四张后续任务卡不再要求 Plugin Package 独立解析 `Flutter`，且分别保留 Bridge Core、临时
  Host、真实 Demo Host 三层证据。
- 核对依赖 DAG 无循环：本任务先于 Base Adapter；Export Adapter、Quality Gate 和最终 Integration
  继续通过现有依赖间接消费该决策。

## 验收标准

- 原生架构与四张后续任务卡只描述一条可执行 SwiftPM 路线，所有权和证据层级不冲突。
- Base/Export Adapter 不修改真实 Host；Quality Gate 用临时 Host；最终 Integration 才修改 Demo Host。
- 不存在 Plugin standalone compile、CocoaPods fallback、本机 Flutter binary path 或 generated
  ephemeral package 入库要求。
- 独立普通 Review 和 Security Review 均无 P0/P1。
- `make harness-check` 与 `git diff --check` 通过。

## 验证命令

```bash
make harness-check
git diff --check
```

## 环境限制

需要 macOS、Xcode 和锁定 Flutter 3.35.7 执行只读路线探针。临时 Host 的完整 build 由后续 Adapter/
Quality Gate 在 Plugin 实现存在后执行；真实 Runner build 和真机 Camera 验收分别属于最终 Integration
与人工真机验收。

## 执行结果

- [实现 Review](../../reviews/execute-media-capture-ios-swiftpm-host-architecture.md)
- [Security Review](../../reviews/security-media-capture-ios-swiftpm-host-architecture.md)
- [测试证据](../../reviews/test-evidence/media-capture-ios-swiftpm-host-architecture.log)
