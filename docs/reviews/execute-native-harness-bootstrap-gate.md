---
task: native-harness-bootstrap-gate
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：原生 Harness Bootstrap 第二阶段任务图

## 首轮结论

独立只读 Review 未通过，P0 0、P1 4、P2 0。13 张任务卡的结构化元数据、DAG、安全门禁、
微信式交互边界和大部分共享写入设计正确，但以下问题阻止 Gate 归档与第二阶段执行。

## Findings

### 1. Capability 缺少 Native UI 的受控预览输出

现有 `open_media_read` 只允许 confirmed `leased` 媒体，`media_preview` 又只有 handle/metadata；
Android/iOS UI 卡却要求 Core 提供 live preview 和确认前 render scope。Capability evolution 必须先
定义 native-consumer-only 的 live preview attachment 与 unconfirmed preview render scope，包含
owner generation、attach/detach、旋转、后台、撤销和清理，且不得暴露 bytes、路径、URI 或 SDK session。

### 2. iOS 验证没有证明 iOS SDK 编译

iOS Core/UI/Adapter/Gate 主要使用 host `swift test/build`，不能可靠证明 UIKit、iOS-only Flutter API
和 iOS 13 target。任务卡必须增加 mandatory generic iOS Simulator `xcodebuild` compile；可用
Simulator 上的测试可以按环境执行并留证，但 iOS SDK compile 不能因无 booted Simulator 跳过。

### 3. Shoppe 卡遗漏 Flutter 壳装配点

实际 Orders route 依赖由 `app/apps/demo/lib/router/demo_router.dart` 装配，Registry 生命周期又由
`DemoApp` 拥有。Shoppe 卡必须获得对应 Router、App dispose 与测试路径写权限，明确这是 Flutter 壳
装配，不是 Native Host/plugin registry；Integration 继续不预写业务接入。

### 4. 首轮 Review 时 Gate evidence 尚未出现 harness-test

Review 读取证据时只有 `harness-check` 和 `git diff --check`；随后后台 capture 已把成功的
`make harness-test` 追加到同一日志。修卡后仍需重新依次留证 `harness-test`、`harness-check` 与
`git diff --check`，避免时间竞态使复审读取不完整证据。

## 已确认项

- 当前 13 张卡的 Executor/platform/workKinds/securityReview 与正文一致，DAG 无环。
- Capability/Wire 共享写入串行，双平台 Core/UI/Adapter/Gate 路径互不重叠，Integration 独占聚合面。
- 微信式 V1 交互完整，明确不复制微信品牌/像素，Figma 非前置且使用 Shoppe Token。
- Fake、Host、Simulator 和真机层级没有互相冒充；Media Capture 仍未实现。

## 证据

[测试证据](test-evidence/native-harness-bootstrap-gate.log) 保留首轮验证与后续修复验证。

## 修复与复审

### 1. Native Preview 与缩略图契约

Capability evolution 卡已增加 native-consumer-only 的 live preview attachment 与 unconfirmed
preview render scope，固定 owner generation、single attach、detach/revoke、旋转、后台和终态清理。
Wire evolution 只把这些资源标为不可跨 Channel；缩略图另行固定 upright JPEG、方向归一、确定性
video poster、尺寸/字节上限和 EXIF 清理。

### 2. iOS SDK 编译证据

iOS Core/UI/Adapter 均要求在对应 Package 目录执行 mandatory generic iOS Simulator
`xcodebuild` compile；iOS Gate 还验证临时 Flutter Host。无 booted Simulator 只允许跳过运行测试，
不能跳过 iOS SDK 编译。候选 SwiftPM Host 路线失败时回到独立架构决策，不现场增加 fallback。

### 3. Shoppe Flutter 壳装配

Shoppe 卡已获得 `demo_router.dart`、必要的 `demo_app.dart` 和对应测试所有权，要求显式注入同一
Media API，并区分 DemoApp 内部创建与外部注入 Registry 的 dispose 责任；这些路径只属于 Flutter
壳 composition，不触碰 Android/iOS Native Host 或 plugin registry。

### 4. 最终证据

修订后的任务卡重新依次执行 `make harness-test`、`make harness-check` 和 `git diff --check`，最终
连续记录均为退出码 0，且复审时没有残留后台进程。

最终独立复审通过，P0 0、P1 0、P2 0。DAG 无环，13 张卡的 Executor、依赖、安全门禁、共享
写入所有权、微信式交互和证据分层均满足 Gate 验收要求。
