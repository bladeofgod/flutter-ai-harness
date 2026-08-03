---
task: media-capture-ios-export-bridge-adapter
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Package.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeController.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeModels.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureServices.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureTransferStore.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureWireCodec.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/app_media_capture_bridge/MediaCaptureBridgePlugin.swift
  - app/packages/app_media_capture_bridge/ios/tool/Package.core-tests.swift
  - app/packages/app_media_capture_bridge/ios/tool/copy-safe-workspace.sh
  - app/packages/app_media_capture_bridge/ios/tool/safe-rsync-copy.sh
  - app/packages/app_media_capture_bridge/ios/tool/test-safe-workspace-copy.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-host-route.sh
  - docs/bridge/media-capture-ios.md
implementationDigest: 906c8a2fe2ba8c554bc915bd1d2a2be26b10f2fc42a49dc7e8793581e76ed8ad
---

# Security Review: iOS Media Capture Transfer Bridge Adapter

> 后续 iOS Quality Gate 安全修正只加固本报告绑定的验证 helper：结构化 Bridge result、隔离 Host 环境、
> 固定日志输出、安全复制覆盖和 no-follow cleanup。独立 Security 复审为 P0/P1/P2 0/0/0；Transfer Store、
> Channel locator、容量、TTL 与 cleanup ownership 未变化，本报告按原文件集合刷新摘要。

## 结论

最终独立只读 Security Review 通过，P0 0、P1 0、P2 0。Reviewer 未读取普通 Review。入站 Flutter 不能
指定 path、URI、文件名、目录、descriptor 或 bytes；导出只发生在 App private transfer root，locator
只出现在成功 payload，不进入错误、Event、日志或 evidence。

## 已确认控制

- Store 逐级持有 no-follow directory FD；staging 使用 128-bit CSPRNG handle 和
  `openat(O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC)`，文件权限 0600、目录 0700，并设置 first-auth 文件保护。
- sink 每次写入核对 device/inode、regular file、link count 与实际长度；commit 使用 exclusive
  descriptor-relative rename，cleanup/restart sweep 使用 no-follow `fstatat/openat/unlinkat`。
- staging、final、root replacement、child/parent symlink、restart residue 和双 live Store 均有确定性测试；
  root 外文件不会被写入或删除，第二个 Engine 不会清扫第一个 Engine 的 active transfer。
- Controller 在 Core 前预留 4 active/100 MiB；50 MiB+1 仍遵守统一预留与 staging 顺序，再由 Core 返回
  `media_export_too_large`。TTL 300 秒在 URI 就绪后相邻采样 epoch/monotonic，并在 Flutter callback 前登记。
- release 原子 claim、并发 join、4096 tombstone、删除失败 retained cleanup、detach/late result 与 source
  lease 独立性均 fail closed；错误 details 不回显 handle、URI、path 或底层异常。
- 临时复制大小写不敏感拒绝环境文件、证书、私钥和敏感 xcconfig；Core/Host helper 自行脱敏 home、repo、
  temp、Simulator ID 和 UUID，并在残余敏感值存在时失败。

## 既有报告影响

Base iOS Adapter 报告的两个 P2 已由本任务关闭；独立影响复核确认其原 12 文件边界继续成立，Transfer
Store 只绑定本任务报告。旧报告已刷新 digest 和结论，不反向扩大其实现文件集合。

## 验证边界

最终 evidence 为 69 项 Simulator XCTest、0 失败，generic Bridge Core build、临时 Flutter Host build、
lint、diff 和 evidence lint 均通过。Simulator 不能替代真机文件保护、存储压力、系统权限和硬件中断验证。

后续严格并发 correction 在重叠 Controller 中只为与 transfer store 无关的私有 presentation 状态增加
MainActor 隔离；reservation、staging、TTL deadline、cleanup、tombstone 和 locator 规则均未改变。TTL
回归测试扩大 callback/TTL 时间差并使用小于新 TTL 的有界条件等待，继续证明 deadline 在 callback 前开始，
同时消除调度抖动。本报告摘要机械更新到当前共享实现快照。

## iOS 综合修正后的最终复审

Bridge helper 现在只接受与 available iPhone Simulator 精确匹配的受限标识；结构化结果只输出固定分类、
整数计数和白名单测试标识，原始日志、failure text、路径、UUID 与设备标识继续保留在私有临时目录。仅无
结构化测试失败时重试一次，精确 69/69 才通过。独立 Security Reviewer 确认 P0/P1/P2 0/0/0。
