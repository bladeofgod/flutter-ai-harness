---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-core
securityReview: required
---

# 修正 iOS 镜头切换提交与能力快照

## 输入与事实来源

- 已归档的 `media-capture-ios-core` 与当前 iOS Native UI 独立 Review finding。
- `docs/infrastructure/media-capture-ios.md`、`swift-ios-standards`、`native-testing-strategy`。
- AVFoundation 镜头配置成功返回后，物理切换已经完成，不能由调用方取消或纯 Render lifecycle 回滚。

## 目标

- 明确平台 `switchCamera` 成功返回为镜头切换的不可回滚提交点。
- Core 在提交后保存新镜头 capability snapshot，并发送新的 `sessionReady`。
- Core 的拍照 flash mode 与新镜头 capability 默认值保持一致。
- 调用方取消或并发 display rotation 不能造成物理镜头与 Core snapshot 分叉。
- Session 已取消、终止或 operation generation 已被替代时，晚结果仍不得写回。

## 非目标

- 不修改全屏 Native UI、Flutter Bridge、Wire、Host、Android 或业务 Feature。
- 不改变拍照、录像、导出、租约、Render attachment 或权限协议。
- 不执行真机 Camera 验收；真机权限和硬件时序留给 iOS Quality Gate 与用户最终验收。

## 实现路径与所有权

本任务只写：

- `app/native/ios/MediaCapture/Sources/MediaCapture/MediaCaptureCore.swift`
- `app/native/ios/MediaCapture/Tests/MediaCaptureTests/MediaCaptureCoreTests.swift`
- `app/native/ios/MediaCapture/Tests/MediaCaptureTests/TestSupport.swift`
- `docs/infrastructure/media-capture-ios.md`
- 本任务自己的 Review 与 evidence 文件

不得修改 `MediaCaptureUI/**`、plugin `ios/**`、Capability/Wire、Host、共享 Registry、CI、Makefile 或
Android/Flutter Feature 文件。

## 实现要求

1. `switchCamera` 在平台成功返回后提交经过公共模型校验的新 snapshot，并按同一 Session handle 发送
   `sessionReady`；上层必须能据此刷新 flash、focus 与 zoom 能力。
2. 平台成功返回后不再以 caller Task cancellation 或纯 Render lifecycle epoch 淘汰结果；这两个信号不能
   撤销已经提交的 AVFoundation configuration。
3. 提交仍要求 Session 存在、处于 ready、同一 operation generation 且 operation 仍在途；cancel、terminal、
   restart 或后续 operation 不得被晚结果覆盖。
4. 不增加新的公共类型、第三方依赖、日志、媒体路径或 AVFoundation 公共暴露。
5. Native UI 对已 dequeue、仍等待 switch action 的 `sessionReady` 必须在 lifecycle cancellation 后重放，
   不能永久停留在 busy；该 UI 修复继续由 `media-capture-ios-native-ui` 任务拥有。

## 测试与验收

- Core XCTest 覆盖普通切换、新 capability event、unsupported camera、平台边界取消与并发 display rotation。
- 取消和旋转竞态使用受控 gate，必须证明操作返回原 Session、新 snapshot 已发送且 Session 继续可拍照。
- 执行完整 `MediaCapture-Package` Simulator XCTest，以及 Core 与 Apple Rendering generic iOS Simulator
  Debug build；证据通过仓库脚本脱敏。
- 独立普通 Review 和 Security Review 均为 P0 0、P1 0 后才可归档。

## 验证命令

```bash
(cd app/native/ios/MediaCapture && xcodebuild test -scheme MediaCapture-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' CODE_SIGNING_ALLOWED=NO)
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCapture -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
(cd app/native/ios/MediaCapture && xcodebuild -scheme MediaCaptureAppleRendering -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
make harness-check
git diff --check
```

## 环境限制

Simulator/Fake 和 generic SDK compile 不能证明真机 Camera 权限 UI、真实镜头切换、系统占用或后台硬件
时序；这些不作为本 correction 任务已验证能力。
