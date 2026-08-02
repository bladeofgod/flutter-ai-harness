---
executor: ios-engineer
platforms: [ios]
workKinds: [native]
blockedBy:
  - media-capture-ios-core
  - media-capture-ios-native-ui
securityReview: required
---

# 收敛 iOS Media Cleanup 永久终态

## 输入与问题

iOS Native UI Security Review 发现，late confirmed lease cleanup 只把 `media_invalid` 视为已经收口，而
Core 在 closed、restart、expiry 或其它永久状态下仍可能返回 `invalid_state`。进程级 cleanup owner 会把
它当作暂时失败无限重试，永久持有 Core、handle、Task 与 presentation slot。

## 目标

- 为 `releaseMedia` 定义可判定的成功、永久终态与暂时不可用结果。
- Core 已关闭且媒体已清除、lease 已过期或 handle 已不可恢复时返回稳定的永久终态；teardown/restart
  中的暂时状态保持可重试语义。
- Cleanup owner 只重试明确的 transient Failure，永久终态停止任务并释放 deferred hold/slot。

## 范围

- `app/native/ios/MediaCapture/**` 中 release/expiry/restart/close 的 Failure 与测试。
- `app/native/ios/MediaCaptureUI/**` 中 cleanup owner 的终态分类与测试。
- 对应 iOS Core/UI 文档、本任务 Review、Security Review 和 evidence。

不得修改 Wire、Flutter Bridge、Host、Android 或业务 Feature；若需要新增公共 Failure，必须先建立独立
Capability/Wire 演进任务，本任务保持阻塞，不得单端发明协议。

## 验收

- 确定性测试覆盖 late confirm 与 close、expiry、restart 和 transient teardown 的交错。
- 永久终态不继续 retry，资源与 slot 恰好释放一次；暂时状态恢复后仍完成真实 release。
- 完整 iOS Core/UI Simulator XCTest、generic build、lint、harness-check、普通 Review 与 Security Review
  均通过。真机文件保护与系统中断留给 iOS Quality Gate。
