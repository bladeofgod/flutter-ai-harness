---
executor: ios-engineer
platforms: [ios]
workKinds: [quality-gate]
blockedBy:
  - media-capture-ios-bridge-adapter
  - media-capture-ios-core
  - media-capture-ios-native-ui
securityReview: required
---

# 建立 iOS Media Capture 单平台质量门禁

## 输入与事实来源

- 已完成 iOS Core、Native UI、Bridge Adapter 及各自 Review/Security/evidence。
- 最新 Capability/Wire Contract、Swift/iOS 与 Native Testing Skill。
- 当前 macOS 15 CI、Flutter 3.35.7、iOS no-codesign Debug build 基线。

## 目标

- 建立可重复执行的 iOS 专项门禁，统一运行 Core/UI/Adapter 的 generic iOS Simulator SDK compile、
  可用 Simulator tests、候选 Flutter Host 路线验证和依赖检查。
- 验证三层语义、actor/MainActor/lifecycle、资源 cleanup 与 package graph，并准确记录模拟器/真机缺口。
- 为最终 Integration 提供一条可接入 Makefile/CI 的平台脚本和脱敏证据。

## 非目标

- 不修改 Contract、Dart Client、Runner/Info.plist、共享 docs/Registry、root Validator、CI/Makefile。
- 不在 Gate 中实现功能或用 Fake 冒充真机 Camera/权限；缺陷回到对应实现任务修复/复审。
- 不执行 Android 或跨 Runtime 最终验收。

## 实现路径与所有权

本任务只写：

- `scripts/quality/media-capture-ios.sh`
- `app/native/ios/MediaCaptureGate/**`（仅必要的跨 Package test target/fixture）
- `docs/native/media-capture-ios-verification.md`
- 本任务 Review/Security/evidence

不得编辑 Core/UI/Adapter 生产代码、Host 或共享聚合入口；最终 Integration 独占这些聚合写入。

## 门禁要求

1. 脚本使用严格 shell、仓库相对路径和当前 `xcrun/xcodebuild`，必须分别对 Core `MediaCapture`、
   Rendering `MediaCaptureAppleRendering`、UI `MediaCaptureUI`、Adapter `app_media_capture_bridge` scheme 执行
   `-destination 'generic/platform=iOS Simulator' -sdk iphonesimulator` Debug compile，再运行 contract
   vectors、Sendable/concurrency warning 和 Package graph 检查。每次 `xcodebuild` 都必须在对应 Package
   目录的子 shell 中执行：`app/native/ios/MediaCapture`、`app/native/ios/MediaCaptureUI`、
   `app/packages/app_media_capture_bridge/ios/app_media_capture_bridge`；不得从仓库根运行无 project/
   workspace context 的裸 `xcodebuild`。任一 generic compile 失败即非零。
2. 验证 Core 无 Flutter，UI 只依赖 Core，Adapter 依赖 Core/UI/Flutter API；Package.swift 不含本机绝对
   path、分支依赖或未批准第三方来源，最低平台与 Host iOS 13 基线兼容。
3. 聚焦竞态覆盖 session/lease cleanup、两类 Native Preview attachment 的 generation/single attach/
   detach/revoke/rotation/scene/owner destroy、ViewController/Engine lifecycle、exactly-once、固定 poster/
   thumbnail bounds、permission/interruption 与 UI 三终态；不得更改共享 Contract 来掩盖平台差异。
4. 验证 Capability V3 concrete `MediaCaptureRenderView` 的 production 接线：live preview layer 进入模块
   view 的 layer tree并绑定私有 Session，photo/video preview 使用模块私有 content/player；replacement、
   detach、scene background、owner destroy 后 layer/session/player/content 清空，旧 generation 不得修改
   target。Simulator compile/test 只证明接线，真机 Gate 另行证明实际 live frame。
5. 使用锁定 Flutter 3.35.7/Xcode 在临时、可清理的 Host fixture 验证候选 SwiftPM Plugin discovery、
   Core/UI product dependency 和 generic iOS Simulator Host compile。路线不受支持时 Gate 失败并要求
   独立架构决策，禁止现场添加 CocoaPods fallback；Integration 只能引用本 Gate 已验证的唯一路线。
6. 若有可用 Simulator，运行不要求真实 Camera 的 lifecycle/UI tests；无 booted/可用 Simulator 时可
   记录运行测试未执行，但绝不能跳过第 1、4 项 generic iOS SDK compile。`swift test/build` 只用于
   明确 host-compatible 的纯 Swift target，不能替代 UIKit/Flutter iOS target 证据。Camera/Microphone/
   系统授权/硬件中断/性能仅真机可验证，证据必须脱敏。
7. 验证文档分清 Swift unit、Framework Fake、generic iOS SDK compile、Simulator runtime、临时 Host
   route、Runner（尚未接线）和真机层级，不能把本门禁
   误述为 Flutter iOS Host build。

## 验收标准

- 专项脚本在 macOS/Xcode 环境一次命令通过且失败可复现；即使没有 booted Simulator，Core、
  Rendering、UI、Adapter 四个模块和
  临时 Host 的 generic iOS Simulator compile 仍全部通过。
- Core/UI/Adapter 与最新 Contract 一致，无跨 Runtime 越权或资源/并发 P0/P1。
- iOS Gate 报告可供最终 Integration 引用；Runner 注册/no-codesign build 仍明确未验证。

## 验证命令

```bash
bash scripts/quality/media-capture-ios.sh
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode/Swift/Flutter。缺少 booted Simulator 只允许跳过运行 tests，不允许跳过 generic iOS
SDK compile 或临时 Host 路线验证；真机缺失时准确列出系统能力风险。最终 Runner no-codesign build
由跨 Runtime Integration 使用本 Gate 已验证的唯一接线路线完成。
