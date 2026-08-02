---
task: media-capture-ios-bridge-adapter
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: iOS Media Capture Bridge Adapter

## 结论

最终独立普通 Review 通过，P0 0、P1 0、P2 0。Adapter 已按 Wire V3 映射基础拍摄、bounded thumbnail、
全屏 `present_capture_flow` 与 originating-request `dismiss_capture_flow`，并保持 Flutter/Native、UI owner、
Engine lease 和 Core 生命周期边界。

## Review 与修复

首轮独立 Review 发现 owner fallback 没有统一 claim 当前请求、权限预检晚于 UI、preview thumbnail/release
错误绕过 owner、idle Session 不监控 owner、非协作 Native await 永久持有 Controller，以及 evidence
路径/设备标识脱敏问题。实现统一 owner boundary，增加 250ms 精确 window/messenger hierarchy liveness，
将权限和硬件预检放到展示前，并以独立 call gate 接管迟到资源和敏感 thumbnail copy。

第二轮独立 Review 发现 boundary cleanup 仍可能裸等 presentation/cancel/release/close、预检未确认硬件、
Core 测试复制未复用安全排除规则，以及 opaque handle 误套 request ID ASCII 约束。实现增加不持有
Controller 的有界 cleanup coordinator、Camera/条件性 Microphone 硬件检查、统一 `safe-rsync-copy.sh`，
并按 Wire 仅以 UTF-8 长度校验出站 opaque handle。

最终修复让 Engine close 在同一个 monotonic 总预算内等待已登记资源与 pending request 的晚到资源清理，
正常路径保证 late lease 先 release、再 close Core；owner cleanup 在 Native cleanup 与 request drain 均
实际 settled 前保持 presentation poisoned。最终独立复审确认上述 finding 全部闭合。

## 验证

[`test-evidence/media-capture-ios-bridge-adapter.log`](test-evidence/media-capture-ios-bridge-adapter.log) 记录：

- 安全工作区复制夹具通过；嵌套 `.env*`、签名材料和越界符号链接均被排除。
- Bridge Core XCTest：43 tests，0 failures，0 skipped。
- `MediaCaptureBridgeCore` generic iOS Simulator Debug build：通过。
- 临时 Flutter Host no-codesign iOS build 与 SwiftPM plugin discovery：通过。
- `make lint`、`make harness-check`、`git diff --check`：全部退出码 0。
- evidence lint 确认命令和输出不含真实 Simulator ID、本机路径或凭据。

Fake、Simulator 和临时 Host 不证明真机 Camera/Microphone、系统权限 UI、硬件录像、最终 Demo Runner 接线
或 codesign 安装；这些仍由后续 Integration/Quality Gate 和用户真机验收负责。
