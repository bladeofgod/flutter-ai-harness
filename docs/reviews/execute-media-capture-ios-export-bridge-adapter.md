---
task: media-capture-ios-export-bridge-adapter
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: iOS Media Capture Transfer Bridge Adapter

## 结论

最终独立普通 Review 通过，P0 0、P1 0、P2 0。Wire V3 materialize/release 已接入 iOS Core sink、App
private transfer store 和 Flutter Plugin；图片、视频、容量、TTL、release claim、detach、restart 与 late
completion 均保持 source lease 独立并按契约收敛。

## Review 与修复

首轮 Review 指出多 Engine startup sweep、callback 后才启动 TTL、50 MiB+1 failure 顺序、Fake write
failure 和 MainActor 文件 I/O。实现增加进程级 root coordinator、callback 前 monotonic deadline、统一
pending/active 容量预留、真实 sink.write failure 注入，并把 reservation/URI/delete 放到 utility task。

Security Review 发现路径检查与文件操作之间存在 symlink/TOCTOU。Store 改为从创建到 commit 持有同一
FD，使用 `openat(O_EXCL|O_NOFOLLOW)`、`fstat/fstatat`、`renameatx_np(RENAME_EXCL)` 和 `unlinkat`；三类
确定性 replacement 测试证明 staging、final、root 被替换时不会写入或删除 root 外文件。

复审进一步收紧了 oversized 请求的容量顺序、epoch/monotonic 同点采样、App restart 自动 sweep 和
preparation barrier。最终 Store 构造后立即调度并跟踪 utility preparation，多个 live Engine 共享准备
状态；generation close 不会重新开放当前 attachment，但允许已开始的进程级 sweep 安全完成。

## 验证

[`test-evidence/media-capture-ios-export-bridge-adapter.log`](test-evidence/media-capture-ios-export-bridge-adapter.log)
记录：安全复制 fixture 通过；Bridge Core 69 项 XCTest、0 失败；generic iOS Simulator SDK build、临时
Flutter Host SwiftPM/no-codesign build、lint 和 diff check 全部通过。验证脚本自行脱敏 home、repository、
temporary path、Simulator ID 与 UUID，并通过 evidence lint。

Simulator/Fake/临时 Host 不证明真实 Camera/Microphone、文件保护、系统中断、最终 Demo Runner 接线或
codesigned 真机安装；这些由后续 iOS Quality Gate、Cross-runtime Integration 和用户真机验收负责。
