---
task: media-capture-ios-dismiss-wire-support
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/bridge/contracts/media-capture.wire.json
  - docs/bridge/media-capture.md
  - app/tool/harness_check.dart
  - app/lib/harness_validator.dart
  - app/lib/src/harness_validator.dart
  - app/lib/src/implementation_digest.dart
  - scripts/quality/test-harness.sh
implementationDigest: 92e3595dcecfa6df2043282989f18b33e7a6201af80061ab0eb1849c62af30ff
---

# Security Review: iOS Capture Flow Dismiss Wire 支持状态

## 结论

独立 Security Review 通过，P0 0、P1 0、P2 0。本次只把既有 `dismiss_capture_flow` 的 iOS support
提升为 `supported`，没有新增 Runtime 入口或权限，也没有放宽请求与资源边界。

## 已确认边界

- method 仍是 commands Channel 的 Adapter operation，只接受 originating `presentationRequestId`；payload
  拒绝未知字段，不接受 Session/Media handle、路径、URI 或自由文本。
- request ID 保持专用 opaque format；协议 error allowlist、exactly-once completion、匹配 flow 后幂等
  dismiss、lifecycle cleanup 和 ID 日志脱敏均未改变。
- Validator 精确要求 Android/iOS 均 supported；mutation 从合法 baseline 回退 iOS support 时必须失败，
  request ID format 和 Session-handle payload 漂移负例继续保留。
- Wire V1/V2 history projection 不包含 V3-only dismiss；Capability、transfer、thumbnail 和 Native Render
  安全边界未变化。

## 验证边界

静态 Contract 与 Harness 不证明 iOS Runtime 已实现或可发布。iOS Adapter、Flutter SwiftPM Plugin、Host
编译与 Quality Gate 是后续独立门禁；Camera/权限与硬件行为最终由用户真机验收。

本轮 Reviewer 未读取普通 Review 结论，未运行命令或修改文件；受共享文件影响的 10 份既有 Security
报告已由同一次独立影响复审覆盖并刷新摘要。

## 跨 Runtime 集成影响

最终集成只修正 Wire current method 计数并把 dismiss 纳入三端 current set，没有改变 iOS dismiss 的
request correlation、终态或清理语义。独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。

## Validator Library 路径迁移复审

2026-08-06 独立安全复审确认 Validator 仅拆分为不可变 Library 结果和薄 CLI，未放宽本报告的既有安全约束。绑定已覆盖公开入口、真实 Validator、摘要计算器、CLI 和 Shell Fixture。

## Wire 生成 Profile 影响复审

2026-08-06 复审确认新增内容仅为闭合 descriptor、无副作用 field/envelope primitive 和生成工具，Wire V3、Capability V4、Native 生命周期、线程与资源 ownership 均未改变。固定 Schema/输出白名单和注入负例未放宽本报告边界，P0/P1/P2 维持 0/0/0。
