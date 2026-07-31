---
task: media-capture-bridge-contract
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：Media Capture Bridge Contract

## 结论

最终 Review 通过，P0 0、P1 0、P2 0。Wire Schema/Profile、Capability 覆盖、错误模型、
生命周期、资源线性化和双平台行为已形成可由后续 Dart/Android/iOS Adapter 确定实现的契约。

## 首轮问题与修复

### 1. Base Schema 仍包含媒体专属结构

首轮 Base 强制 opaque handle 与媒体安全字段，无法复用于非媒体 Bridge。修复后 transport、
数据分类、安全策略和生命周期扩展均使用通用、可选结构；Media 专属 handle、路径、事件、
boundary 与策略只由 Profile 和专项 Harness 精确固定。

### 2. 异步 Failure 和普通事件交付不完整

`preview_timed_out -> session_timeout` 原本只有错误码，没有可执行 Wire 路径。修复后它使用独立
failure envelope 在 EventChannel UI 线程交付且保持 sink；direct method Failure、独立
`session_failed` 终止事件和 async failure 三种语义互不冒充，也不依赖无法证明的 request correlation。

### 3. detach、listener 和错误 details 不确定

Engine detach 与 UI owner destroy 现有不同的有序 boundary action；第二 listener 固定拒绝新 sink、
保留旧 sink，cancel 后才允许新 generation。错误 details 的类型、来源、枚举、长度和范围均为闭合
集合，未知字段只返回固定哨兵，不回显输入或底层异常。

## 后续复审问题与修复

### 1. Base lifecycle 与 late result 仍锁定或遗漏资源

Base lifecycle 最终只强制 MethodChannel 核心，Event/Failure/listener/correlation/boundary/adoption
均可选或为空。Media Profile 对 8 类暴露结果逐项声明 cleanup-before-drop：晚到 Session/Preview
使用已有 `system_interrupted` 清理，晚到 confirmed lease 使用 `release_media`。

### 2. 资源登记与 Flutter completion 存在竞态

最终实现用同一 `bridge_lifecycle_coordinator` 线性化 generation 复查、资源登记、一次完成、
boundary close/scan 与 late cleanup。`session_created` 和 `confirmed_media` 必须先登记资源再成功
完成 Flutter；boundary 先赢时先完成 `bridge_unavailable` 并清理资源，不会二次完成 Flutter。

## 已确认项

- 12 个 method、5 个普通 event、1 个 async failure 和 14 个 Capability Failure 均可追溯。
- `open_media_read` 明确保留给 Native Consumer，不传输 bytes、路径、URI 或虚构读取操作。
- Wire V1 独立声明兼容 Capability V1，不以版本数值相同推断绑定。
- Payload、signed-64、opaque handle、请求去重容量、完成槽预留和 Android/iOS 支持矩阵受确定性门禁。

## 验证

[测试证据](test-evidence/media-capture-bridge-contract.log) 保留三轮修复中的失败与最终成功记录。
最终 `make harness-test`、`make format` 和 `git diff --check` 通过；归档后的 `make harness-check`
在 Review 报告与共享安全摘要更新后重新执行。
