---
executor: ios-engineer
platforms: [ios]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-export-dart-client
  - media-capture-export-wire-evolution
  - media-capture-ios-bridge-adapter
  - media-capture-ios-export-core
securityReview: required
---

# 实现 iOS Media Capture Transfer Bridge Adapter

## 输入与事实来源

- Wire V3 transfer methods、Capability V4 sink、Dart Client 和已验证的 iOS Plugin/Host 路线。
- iOS Application Support/Caches 私有目录与 FileManager 原子文件操作边界。
- 现有 iOS Adapter MainActor/lifecycle coordinator 和 Engine/ViewController generation。

## 目标

- 在 iOS Plugin Adapter 实现 App 私有 transfer store、temporary file URL 与 Wire V3 materialize/release。
- 保持与 Android 完全相同的容量、TTL、source lease 和 cleanup 语义。
- 用 iOS SDK compile/tests 证明 SwiftPM Plugin、Core sink、Flutter codec 和 Host 依赖图成立。

## 非目标

- 不修改 Capability/Wire/Dart Client/Core、Runner/Info.plist、Feature 或 Android。
- 不接受 Dart 指定 path/URL，不保存 Photos，不增加 Entitlement，不通过 Channel 传 raw Data。
- 不把 transfer URL 当作持久消息资源。
- 不修改真实 Demo Host，不增加 CocoaPods fallback 或本机 Flutter framework path。

## 实现要求

1. 在 FileManager 提供的 App private caches 下创建固定 plugin export root，解析符号链接并校验
   standardized/resolved URL 仍在根内；随机文件名不使用用户/源文件名。
2. lifecycle coordinator 先预留 4 active/100 MiB/请求完成槽，再创建 staging 和实现 Core sink；容量
   不足时不调用 Core。
3. sink 以 bounded FileHandle write 写 staging，commit 前核对 MIME/实际长度/50 MiB，synchronize/close
   后同卷 replace/move 原子 commit。登记 export/TTL 后才在 MainActor 回调 Flutter。
4. 成功 `fileUri` 由 Foundation URL API 生成 absolute normalized `file:` URI并做 Wire 出站校验；日志、
   FlutterError details、event、evidence 不得包含 URL/path。
5. release/TTL/Engine detach/plugin detach/App restart/late completion 先 abort/delete并写 tombstone；删除
   failure 有界重试。source lease 不因 materialize 或 export release 自动释放。
6. 与 Android 保持相同 failure、容量、TTL、tombstone 和顺序；平台差异只限 Foundation/MainActor API。
7. Transfer Store、Core sink、容量/TTL/tombstone 与 cleanup 都进入既有 `MediaCaptureBridgeCore`
   target；Plugin target 只增加 Flutter payload/result 映射，不复制资源状态机。
8. 沿用 Base Adapter 的临时 Host 验证入口证明 Flutter Plugin target；不修改真实 Host。若既有
   SwiftPM 路线失败，返回 SwiftPM Host 架构决策复审，不能现场增加 CocoaPods fallback。

## 测试与验收

- Fake Core/temporary cache 测试成功、release、TTL、容量、restart、detach、symlink/traversal、长度漂移、
  write failure、late result、MainActor completion 和 redaction。
- Swift/Dart contract vectors 与 Android 同值；成功 payload 外没有 URL/path，输出 URL位于 canonical root。
- Bridge Core generic iOS Simulator compile/tests 与临时 Flutter Host no-codesign build 通过；不得把临时
  Host 误述为真实 Demo Runner 已接线。

```bash
(cd app/packages/app_media_capture_bridge/ios/app_media_capture_bridge && xcodebuild -scheme MediaCaptureBridgeCore -destination 'generic/platform=iOS Simulator' -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build)
bash app/packages/app_media_capture_bridge/ios/tool/verify-host-route.sh
make harness-check
git diff --check
```

## 环境限制

需要 macOS/Xcode/Flutter。Bridge Core SDK compile 与临时 Host build mandatory；真实 Runner build
属于最终 Integration，没有真机时不宣称 Camera 或真实视频导入已验证。

## 执行结果

- iOS Adapter 已实现 Wire V3 materialize/release、App private descriptor-relative transfer store、
  4 active/100 MiB/50 MiB、300 秒 TTL、release claim/tombstone 和 restart/detach/late cleanup。
- 独立普通 Review 与 Security Review 最终均为 P0/P1/P2 0；Base Adapter 两个既有 P2 已关闭并刷新摘要。
- 最终 evidence：安全复制 fixture、69 项 XCTest、generic Bridge Core build、临时 Flutter Host
  SwiftPM/no-codesign build、lint、Harness 和 diff check 全部通过，证据脱敏检查通过。
- 真实 Demo Runner 接线、codesign 安装、Camera/Microphone 与真机文件保护仍由 Quality Gate、最终
  Integration 和人工真机验收承担。
