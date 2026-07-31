---
task: media-capture-ios-core
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: iOS Media Capture Native Core

## 首轮结论

首轮独立 Review 未通过，P0 2、P1 7、P2 1。当前实现已经建立 Swift Package、类型化 Core、
AVFoundation/File Wrapper 和 20 个 XCTest，但仍存在 Capability 结果/Failure 不一致、Preview 未实际
绑定渲染源、actor 重入覆盖终态、AVFoundation 与文件资源清理不足等问题。mandatory generic iOS
Simulator `xcodebuild` 也因本机缺少对应 iOS platform component 而未通过，任务不能归档。

## P0

### 1. MediaThumbnail 缺少 media_handle

Capability V2 要求缩略图结果包含 `media_handle`，当前 `MediaThumbnail` 类型和构造结果均未携带。

修复要求：增加 `mediaHandle`，从已验证的 `MediaRecord.handle` 填充，并增加公共 API 测试。

### 2. 控制操作可能公开契约未声明的 Failure ID

`set_flash_mode`、`set_focus_point`、`set_zoom` 的 allowlist 不包含 `resource_in_use`，但 AVFoundation
Wrapper 可抛出该错误，通用 mapper 会原样公开；`publicSnapshot` 也可能向 start/switch 暴露未声明的
`encoding_failed`。

修复要求：按 operation 做稳定 Failure 映射，只产生对应 allowlist 中的 ID；终止型错误同时提交
failed 状态并发出 `session_failed`。

## P1

### 1. Render attachment 没有实际渲染能力

公共 Adapter 只收到生命周期 context，live 平台 attach/detach 是空操作，未确认媒体也只发
`didAttach`。模块尚未真正把 live session 或私有媒体 renderer 绑定到目标。

修复要求：引入模块定义且 transport-neutral 的 render source/binding token；模块内部完成绑定，并在
每次 render callback 验证 scope/generation。Binding teardown 独立于弱 target，target 释放后仍执行
平台 detach。

### 2. actor 重入可能复活已取消或终止状态

`confirm`、`retake`、控制操作和 `failSession` 在 `await` 前读取 record，恢复后可能用旧副本覆盖并发
cancel、timeout 或 interruption 已提交的 registry 状态。

修复要求：首次仲裁时原子推进 operation/lifecycle generation；所有 `await` 后按 generation 和当前状态
重新验证，禁止旧副本写回。background、rotation、restart 也先推进 lifecycle epoch 再清理。

### 3. Delegate、continuation 和录像临时文件收尾不完整

单一 photo/movie delegate slot 会被后续操作覆盖，旧回调可能完成当前 delegate；`stopSession` 不等待
delegate 完成，也未完整清理 observer/partial recording destination。

修复要求：使用 operation-scoped delegate identity，stop/cancel/close 等待 exactly-once completion；
FileStore 增加 partial recording discard，close 时显式移除 observer。

### 4. 缩略图取消、预算和失败清理不满足合同

Apple generator 未协作检查 Task cancellation；视频 generator 未在 decode 前限制尺寸；失败路径没有
可证明的 cancel-and-await decoder 和中间 buffer wipe。

修复要求：managed job 持有 decoder Task、source 和可擦除 buffer，接入 cancellation handler，视频
decode 前限制尺寸，并严格按合同顺序清理。

### 5. read grace 到期不能强制撤销进行中的原始读取

当前读取先检查布尔状态再同步 `Data(contentsOf:)`，`close()` 无法中断已开始读取。

修复要求：使用模块持有的可关闭 source handle 或协作取消任务；revoke、关闭与删除完成后再发事件，
增加跨 grace 的阻塞读取测试。

### 6. XCTest 覆盖范围不足

现有测试没有完整覆盖两类 background revoke、rotation、restart、live owner destroy、CSPRNG、delegate
cleanup、actor race、真实 render source、视频预算和文件删除；也缺少普通 `import MediaCapture` 的
Package consumer 测试。

修复要求：补齐任务卡声明的确定性 Framework Fake/公共 API 覆盖，保持 Fake 能力边界说明。

### 7. mandatory generic iOS Simulator xcodebuild 未通过

证据中 mandatory 命令退出码为 70，原因是当前 Xcode 对应 iOS platform component 未安装。
`swift build --build-tests` 只能作为补充，不能替代该门禁。

修复要求：实现问题关闭后仍须在具备对应 component 的环境重跑任务卡原命令并留成功证据；在此之前
任务保持 active，不归档。

## P2

### 1. 已完成 deadline Task 会留在字典

deadline Task 完成后没有按 identity 移除自身，tombstone 清除也不清对应 key，长期使用会积累。

修复要求：Task 完成时按 identity 移除，并在 terminal/tombstone cleanup 中清除相应 key。

## 证据隐私复核

首轮审查期间发现 `xcodebuild` 原始输出包含本机路径和 destination 信息；主线程已将路径、标识和名称
替换为通用占位符。仓库证据 lint 与额外路径/UUID 扫描均通过，该问题已关闭，不计入当前问题数。

## 第 1 轮复审

首轮两个 P0 已关闭：`MediaThumbnail` 已携带 handle，Failure 会按 operation allowlist 收敛。deadline
Task 也已按 identity 清除，证据隐私保持脱敏。复审仍有 8 个 P1，任务不能通过。

### 1. Render binding 仍不能被独立 UI Package 使用

live/file source 要求 target 遵守 internal endpoint protocol；后续独立 `MediaCaptureUI` Package 无法
conform，现有 `@testable` 测试绕过了真实公共边界。

修复要求：提供不暴露 AVFoundation session、文件路径或 UIKit 的 public adapter/factory，由模块内部
完成 endpoint 绑定；用普通 `import MediaCapture` 测试真实外部 Package 路径。

### 2. terminal cleanup 与下一 Session 存在资源竞态

confirm/cancel/fail 先清 active owner，之后才 stop platform；teardown 完成前新 Session 可被接受，并被
旧 cleanup 的 stop 操作影响。restart 清理期间也可创建随后被删除的新 handle。

修复要求：增加 module/capture-resource lifecycle gate；teardown/restart 完成前拒绝新 Session 与操作，
补 start-vs-confirm/cancel/fail/restart 并发测试。

### 3. unsupported camera 被错误映射成 system interruption

start-session 的 `unsupported_capability` 被全局重写为 `system_interrupted`，破坏 Capability 允许的稳定
区分。

修复要求：删除该特判，invalid platform snapshot 单独映射，增加 camera unavailable 测试。

### 4. AVFoundation 与导出操作不响应调用者取消

photo/movie delegate await 和视频 export continuation 缺少 cancellation handler；调用者 Task 取消后仍
可能成功返回。

修复要求：用 operation identity/cancellation handler 取消底层操作，等待 exactly-once 收尾后传播
`CancellationError`，增加 production wrapper cancellation 测试。

### 5. thumbnail 中间 JPEG buffer 未按合同擦除

降质重试的失败候选是普通 Data，取消窗口也发生在包装为可擦除 buffer 之前，partial generation output
无法保证 wipe。

修复要求：encoder 从第一份 output 起就使用可擦除 owner，每次重试、取消和失败均显式 wipe。

### 6. 生产 FileHandle read/close 无共同同步

`@unchecked Sendable` backend 的 read 与 grace close 可并发访问同一 descriptor；带锁 Fake 不能证明
生产路径安全。

修复要求：使用锁或专属串行执行域隔离 descriptor，采用可抛错读取 API，并补 production close/read
竞态测试。

### 7. 测试验收与最新证据仍不完整

当前测试尚未断言真实 delete，internal Render endpoint 测试掩盖公共边界，operation completion 单测也
不能替代 photo/movie cancellation；现有 evidence 仍是修复前产物。

修复要求：补真实公共/生产边界测试并对最新源码重新采证，保持 Fake/SDK/Simulator 能力边界准确。

### 8. mandatory generic iOS Simulator xcodebuild 仍未通过

当前环境缺少 Xcode 26.5 对应 iOS platform component，mandatory 命令仍退出 70。SwiftPM SDK build
不能替代；实现修复完成后仍须在组件可用环境执行 exact 命令并留成功证据。

## 第 2 轮复审

capture-resource lifecycle gate、unsupported camera 映射、photo/movie/export cancellation、JPEG 全候选
擦除、production FileHandle read/close 共锁和真实 delete/partial discard 均已关闭。当前仍有 3 个 P1。

### 1. Public Render binding 尚未产生实际画面

独立 Package 已能通过普通 import 实现 factory，类型边界也未暴露 AVFoundation、文件路径或 UIKit；
但生产 binding 只持有 Session/URL，revoke/detach 只改变状态，没有创建 renderer、挂载 surface，也没有
触发生产 callback gate。现有测试只证明对象非空或保留 source，未证明画面到达 target。

修复要求：在不暴露 `AVCaptureSession`、`AVCaptureVideoPreviewLayer`、sample buffer、文件路径或 UIKit
View 的前提下，提供模块定义的公共 RenderTarget Adapter/实现，把 live 与 file preview 实际挂载到目标；
生产 callback 必须经过 scope/generation/lifecycle gate。增加普通 import consumer 的行为断言。

### 2. 最新实现与新增测试尚未重新采证

现有 evidence 仍对应旧文件列表，没有第 1/2 轮新增测试，也没有执行 XCTest。修复完成后必须对最新
源码重新采集 iOS SDK compile 证据；SDK compile 只证明编译，不能冒充 XCTest 运行或 mandatory gate。

### 3. mandatory generic iOS Simulator xcodebuild 仍未通过

当前环境仍缺少 Xcode 26.5 对应 iOS platform component，exact 命令退出 70。该门禁在组件可用前无法
关闭，任务保持 active。

## 第 3 轮架构结论

最后一轮没有继续用 opaque token、`AnyObject` 或只持有 Session/URL 的空 binding 伪装实际渲染，也没有
修改实现。独立 Architect 复核确认，真实 Render 属于 Core 卡范围：后续 Native UI 被 Core 阻塞、禁止
回改 Core，并且只能消费 Core 提供的 Render 能力；若 Core 在没有生产 renderer 时归档，后续没有合法
任务能补齐基础能力。

但当前 Capability V2 又同时禁止 Core/UI 边界传递任意 backing UI surface、平台 SDK 类型、capture
session、preview layer、sample/pixel frame、路径和媒体 bytes。Core 私有 source 与 UI 私有 backing
surface 之间不存在合法 mount 通道，因此“保持现有禁止项并证明实际画面”在结构上不可执行。

推荐先演进 Capability，允许受限的 `module_defined_platform_render_surface`，继续禁止 raw/arbitrary UI
object、Session、PreviewLayer、sample buffer、路径、URI、文件描述符和媒体 bytes。随后在同一 Swift
Package 增加独立 `MediaCaptureAppleRendering` product，公开模块定义的 `MediaCaptureRenderView`；Core
product 继续保持 transport-neutral，内部 renderer/session/player/source 只通过 package-only 强类型端点
交给 Rendering target。Native UI 只持有该 render view，不持有内部 layer、Session 或路径。

该调整会修改已批准 Capability 的 representation 规则与版本策略，必须由用户选择：提升 Capability V3
并让 Wire V2 显式兼容 V2/V3，或把未发布 V2 作为 erratum 原版本修正。选择前 iOS Core 保持 active，
不归档；mandatory Xcode platform component 仍是独立的第二个阻塞。

## Capability V3 concrete renderer 独立审查

Capability V3 与 Wire V2/V3 兼容任务完成后，独立 Reviewer 对 concrete renderer 只读审查，结论为
P0 0、P1 2、P2 0：

1. callback gate 直到 endpoint mount 返回后才随 committed binding 进入 registry；rotation、background、
   owner destroy 或 close 无法及时失效尚未提交的 gate，旧 generation 可能短暂修改 surface。
2. detach/revoke 在实际 renderer cleanup 前清空 binding registry，新 generation 可在旧 session/player/layer
   清理完成前开始 mount；concrete renderer 的 photo content 清理顺序也早于 layer removal。

## Capability V3 修复待复审

- Core 在读取 source 和调用 endpoint 前登记带 identity、generation、lifecycle epoch 与 callback gate 的
  pending reservation；所有 lifecycle/owner/terminal 路径同时失效 pending 和 committed gate。
- slot 在旧 renderer cleanup 期间保持 reservation，拒绝新的 mount；断开 source、移除 layer、清空 content、
  detach callback 完成后才按 identity 清理 registry。
- 新增 Core 级受控竞态测试，覆盖 pending live rotation、pending unconfirmed owner destroy，以及旧 revoke
  阻塞时 replacement 不能 mount；Rendering 测试固定 photo layer removal 后再清 content。
- iOS Simulator SDK `swift build --build-tests` 已编译全部 Core、Rendering、Consumer 与 test target；mandatory
  generic Simulator `xcodebuild` 仍受本机缺少 iOS 26.5 platform component 阻塞。

在该修复快照中尚未完成独立复审，因此当时报告继续保持 failed。

## Capability V3 最终独立复审

独立 Reviewer 对最终 Swift Package、测试和脱敏 evidence 复审通过，P0 0、P1 0、P2 0：

- pending reservation 在 endpoint mount 前已进入 Core slot；rotation、background、owner destroy、restart
  与 close 都会先失效 pending/committed gate，旧 generation 的后到 mutation 被本地 gate 丢弃。
- replacement 在旧 binding cleanup 期间保留 reservation 与 `cleanupInProgress`，竞争 attach 无法开始 mount；
  旧 binding 按 identity 完整清理后才开放新 mount。
- concrete cleanup 顺序为 invalidate gate、断开 session/player、移除 layer、清空 photo content、完成 detach
  callback，最后清理 registry；Core 级 latch 测试覆盖 pending live rotation、pending unconfirmed owner destroy
  和阻塞 revoke 时的 replacement。

iOS Simulator SDK `swift build --build-tests` 已编译全部 product 与 test target，`make lint`、
`make harness-check` 和 `git diff --check` 通过。两条 mandatory generic Simulator `xcodebuild` 仍因本机未安装
iOS 26.5 platform component 退出 70；这不是剩余代码 finding，但在组件可用并重跑通过前，任务必须保持
active，不归档。Simulator/Fake 也不证明真机权限 UI、中断、编码性能和内存峰值。

## Read lease 安全修复后的普通复审

Security Review 在 `withMediaRead` 的 slow `openSource` actor reentrancy window 发现 release/expiry 后可能
登记 late read 的问题。最终实现会在 source 返回后先处理 deadline，再重新确认同一 storage reference、
leased state 与 `leaseDeadline > now`；失败立即关闭 source，且不登记 `readScopes`。新增测试分别覆盖
release-during-open 和 lease-expiry-during-open。

独立普通 Reviewer 对最终实现与证据复审通过，P0 0、P1 0、P2 0，确认 release、expiry、restart 和 close
不会留下 late read capability，也未引入正确性或生命周期回归。mandatory Xcode platform 环境阻塞保持不变。
