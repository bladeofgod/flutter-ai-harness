---
executor: ios-engineer
platforms: [ios]
workKinds: [bridge-adapter]
blockedBy:
  - define-media-capture-wire-generation
securityReview: required
---

# 迁移 iOS Media Capture Wire 生成代码

## 输入与事实来源

- `define-media-capture-wire-generation` 的 Contract manifest、generator 和 Swift renderer。
- `app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/` 的 Bridge Core codec/controller/models、
  SwiftPM targets和 XCTest。
- iOS Native Module 保持手写的 Capability、actor/main actor、资源和文件生命周期契约。

## 目标

- 生成并接入 iOS Runtime 的稳定 Wire 标识、枚举、payload descriptor、字段范围和基础 codec。
- 删除 Swift Adapter 内重复的手工协议表，同时保持 main actor callback、Native mapping、transfer store、
  presentation 和 lifecycle coordinator 行为不变。

## 非目标

- 不修改 Contract/generator、Dart/Android、iOS Native Module、Runner/Info.plist 或 Capability。
- 不生成 AVFoundation/UIKit、actor/task ownership、owner generation、late cleanup、文件系统或 transfer store。
- 不改变 Wire V3 shape、错误 details、权限或 Native UI 流程。

## 实现要求

1. 只通过 `--runtime ios` 生成约定 `*.generated.swift`，禁止手工修改；SwiftPM target显式编译仓库内生成文件，
   不依赖 DerivedData、绝对路径或 Flutter binary copy。
2. 手写 Codec/Controller 使用生成 version/channel/method/event/result/error、field descriptor和 scalar/
   envelope primitive。删除 manifest 已拥有的重复集合；Capability Failure 映射、MainActor、controller、
   transfer/presentation 状态机继续手写。
3. Swift 名称 escaping、Int64、NSNumber/Bool 区分、NSNull/nullable、Data/Flutter bytes和闭合 enum必须
   fail-closed；错误或日志不回显 payload、URI、handle、bytes、对象 description 或 raw Error。
4. 保持 17 methods/5 events、全部恶意 vector、URI/handle/thumbnail、error source/redaction、Engine detach、
   ViewController destroy 和 exactly-once completion 的行为证据。
5. XCTest 新增生成 drift、descriptor 与 Contract coverage；现有 codec/controller/transfer测试继续验证真实
   行为。Swift golden 必须来自共享 vector，不复制第四份手写期望表。

## 写入所有权

- `app/packages/app_media_capture_bridge/ios/**`
- `docs/bridge/media-capture-ios.md` 中生成边界与真实验证状态

不得修改 `app/native/ios/**`、Dart/Android、共享 Contract/generator、Runner 或最终集成文档。

## 验收与验证

```bash
cd app && dart run tool/generate_media_capture_wire.dart --runtime ios --check
bash scripts/quality/media-capture-ios.sh
make harness-check
git diff --check
```

## 环境限制

需要 macOS、Xcode 和锁定 Swift toolchain。Simulator XCTest/compile 不替代真机 Camera/权限，但本卡未改变
Native Capability；没有可用 Xcode 时任务不能宣称 iOS 迁移完成。
