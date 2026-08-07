# Media Capture Flutter Bridge Contract

本文描述 Media Capture Capability 到 Flutter Channel 的 Version 3 映射。结构化事实源是
[`media-capture.wire.json`](./contracts/media-capture.wire.json)，通用结构见
[`wire.schema.json`](./contracts/wire.schema.json)。Native Module 的公共语义、状态机、权限与文件
所有权只由 [`media-capture.capability.json`](../infrastructure/contracts/media-capture.capability.json)
及其[详情文档](../infrastructure/media-capture.md)定义；本 Bridge 不修改这些事实。

跨 Runtime 的职责和依赖方向继续遵守[原生架构](../native-architecture.md)与
[Bridge 总则](./README.md)：Flutter Consumer 调用类型化 Dart Client，Android/iOS Adapter 在
Channel 边界把 Wire Model 映射为各自 Native Module Model，Native Module 不读取 Wire Contract，
Host 只装配和注册。

稳定 Wire 标识、payload/field descriptor 和基础 envelope/field primitive 的生成范围与命令见
[Bridge Wire 代码生成规则](./code-generation.md)。`codeGeneration` manifest 只引用本 Contract 已有 ID
和 JSON Pointer；它不提升 Wire 版本，也不生成 Capability mapping、dispatch、线程、生命周期、资源、
transfer store、presentation 或文件系统行为。

## 版本与 Channel

- Wire Contract：`media_capture_wire`，`wireVersion: 3`。
- 兼容 Capability：精确兼容 `media_capture` 的 `capabilityVersion: 4`。
- MethodChannel：`com.example.media_capture.commands`。
- EventChannel：`com.example.media_capture.events`。
- 发布真实应用前必须替换 `com.example` 命名空间；替换结果应在两端和 Dart Client 中保持一致。

`wireVersion` 与 `capabilityVersion` 独立演进。数值恰好相同没有耦合含义；Wire 只声明自己完整映射的
Capability 版本。Wire V3 在保留 V1/V2 history 的同时，新增基于 Capability V4 bounded streaming export
的 Flutter transfer locator。Adapter 必须从声明的兼容集合确定支持；不支持的组合继续返回
`incompatible_wire_version`，不能用未知字段、平台异常或运行时类型猜测 Capability 版本。Wire V2
不宣称兼容 Capability V1，也不保留 V1 到 V2 的暂存窗口。Wire 字段、
method、event、error code 或 enum 的不兼容变更提升 `wireVersion`；
Native Module 新增操作、状态、权限、Failure 或所有权语义时，必须先走 Capability 版本决策，不能
由 Bridge 反向补充。

Harness 不只检查 `[2, 3]` 声明。它从已锁定的 Capability V3 additive delta 构造 V2 transport
projection：精确移除两项 render surface policy、两项 surface resource、两项 owner scope，并从 Wire
coverage projection 移除已由 V3 验证为 Native-only 的 53 项 artifact metadata。V2 projection 与完整
V3 随后运行同一套 field、payload、method、result、event 和 failure 映射校验。过滤只发生在验证用
projection，仓库 Profile 仍保留完整 V3 coverage；这些额外 metadata 不进入受保护的 transport shape。

通用 `wire.schema.json` 只定义可复用的 Channel、Payload、可选 transport constraint、数据分类和策略
结构：不使用整数的契约可以把 signed-integer constraint 设为 `null`，没有 opaque handle 的契约可以
声明空集合，也不内置 Media/path 专属 policy。Event/failure envelope、listener、correlation 与
boundary/late-result 集合都是可选或可空结构；纯 MethodChannel、无 Session、无媒体资源的契约不需要
伪造这些字段。`linearizationPolicy`、`resourceAdoptionPolicies` 和 `resultCompletionPolicies` 也都是
可选或可空的通用结构，不预设 Session/Media；通用 boundary 只表达任意稳定
boundary/resource/action ID 和顺序。通用 method 通过 `kind` 区分 `direct_operation` 与
`presentation`：前者映射一个 Capability operation，后者由 Adapter/UI 编排既有 operation。Base
Schema 不写死 Media Capture、Activity、ViewController 或全屏常量。通用 coverage 的
`nativeArtifacts` 用 artifact kind、owner policy、可选平台和 disposition 描述任何 Capability 内部的
Native-only artifact，不写入具体 UI Framework 类型。本文的 Media Profile 与 Harness
才精确固定媒体元数据、Handle、禁止路径、日志、资源 adoption 和清理边界。

## Envelope 与 Payload

所有 method 请求都是 `{wireVersion, requestId, payload}`，成功结果是
`{wireVersion, requestId, resultType, payload}`，事件是
`{wireVersion, eventType, payload}`，Capability failure emission 是
`{wireVersion, failureType, payload}`。EventChannel listen 参数是仅含 `wireVersion` 的 Map。
五类 Map 都拒绝未知 key。直接映射 method 的 `resultType` 固定等于 Capability `resultId`；
presentation method 的两个正常终态使用独立的闭合 `resultType`。Adapter 不从 Payload ID 字符串
推导结果。`requestId` 是 1 至 128 字符的
ASCII token，固定匹配 `^[A-Za-z0-9_-]{1,128}$`，只用于一次 Engine attachment 内的去重和
完成关联，日志必须脱敏。

Payload key 统一使用 `lowerCamelCase`。Wire Contract 中的 `fieldMappings` 把每个 key 显式映射到
Capability field，并完整保留 required、nullable、enum 和数值/集合 validation。Adapter 必须先
拒绝未知字段、缺失字段、错误类型、非有限数值、越界值和非法 enum，再构造类型化 Model；原始 Map
不得进入 Native Module、Controller 或业务 API。`durationMillis` 始终存在：照片为 `null`，视频为
1 至 60000 的整数。

只允许 `bool`、`bytes`、`double`、`int`、`string` 和其同类型 List。两端 `int` 固定使用 signed 64-bit
范围 `-9223372036854775808` 至 `9223372036854775807`；入站越界返回
`invalid_wire_payload`，method 结果出站越界返回 `wire_encoding_failed`。事件出站越界时以
`wire_encoding_failed` 终止当前 sink，但不改变 Capability 状态。

`bytes` 只用于 `read_media_thumbnail` 返回的 `thumbnailCopy`，Dart 固定映射为 `Uint8List`，两端
Adapter 映射为 Channel typed byte array。除此之外不传输 Proto、原始媒体 bytes、
CameraX/AVFoundation 类型、任意 Map、调用方提供的路径或 URI。Wire V3 唯一允许的 locator 是
`materialize_media_resource` 成功结果中的 Adapter-created、短生命周期 `fileUri`，并且只供 Dart 基础设施
立即导入 Store。Capability V3 concrete surface、factory input/output、
mount endpoint 或内部 source 也不能借用 bytes、String path、URI、descriptor、opaque token 或 untyped
Map 作为 fallback。`sessionHandle` 与 `mediaHandle` 只接收
Capability 创建的不透明句柄，必须非空且最长 128 字符；该长度直接派生自两项 Capability handle
policy，不增加字符集约束。入站超长返回 `invalid_wire_payload`，出站超长返回
`wire_encoding_failed`。Adapter 不解析、不拼接路径，也不把句柄放入日志或错误 details。

## Method 映射

| Wire method | Capability operation | 请求 / 结果 |
| --- | --- | --- |
| `start_session` | `start_session` | `start_session_request` / `session_created` |
| `take_photo` | `take_photo` | `session_action_request` / `media_preview` |
| `start_recording` | `start_recording` | `session_action_request` / `recording_started` |
| `stop_recording` | `stop_recording` | `session_action_request` / `media_preview` |
| `switch_camera` | `switch_camera` | `session_action_request` / `control_applied` |
| `set_flash_mode` | `set_flash_mode` | `flash_mode_request` / `control_applied` |
| `set_focus_point` | `set_focus_point` | `focus_point_request` / `control_applied` |
| `set_zoom` | `set_zoom` | `zoom_request` / `control_applied` |
| `retake` | `retake` | `media_handle_request` / `retake_ready` |
| `confirm` | `confirm` | `media_handle_request` / `confirmed_media` |
| `cancel` | `cancel` | `session_action_request` / `session_cancelled` |
| `release_media` | `release_media` | `media_handle_request` / `media_released` |
| `read_media_thumbnail` | `read_media_thumbnail` | `media_thumbnail_request` / `media_thumbnail` |
| `materialize_media_resource` | `copy_confirmed_media_to_sink` | `materialize_media_resource_request` / `materialized_media_resource` |
| `release_materialized_media` | Adapter transfer lifecycle | `release_materialized_media_request` / `materialized_media_released` |
| `present_capture_flow` | 无直接 operation；Adapter/UI 编排 | `start_session_request` / 三终态 |
| `dismiss_capture_flow` | Adapter presentation lifecycle | `dismiss_capture_flow_request` / `capture_flow_dismissed` |

分步拍摄、thumbnail 和 materialize method 的 `kind` 是 `direct_operation`。`materialize_media_resource`
的 method 名与 Capability operation 不同：请求只接受 `mediaHandle`，Adapter 自己创建随机 transfer target
和 typed sink，再以固定 52,428,800 byte 上限调用 `copy_confirmed_media_to_sink`。
`release_materialized_media` 的 `kind` 是 `adapter_operation`，只删除 Adapter transfer file 和登记
tombstone，不调用 `release_media`，也不等价于释放 source media lease。
`present_capture_flow` 的 `kind` 是 `presentation`，`capabilityOperationId` 必须为 `null`；它不能被
Native Core 当成新的 operation，也不能让 Core 读取 Wire Contract。
`dismiss_capture_flow` 是 Wire V3 的 Adapter-only 生命周期补丁。Flutter Client 只能提交自己当前
`present_capture_flow` 的 opaque `presentationRequestId`；Adapter 仅在该 ID 与活动 presentation 完全
匹配时 dismiss，并让原请求以正常 cancelled 终态完成。payload 不接受 Session/Media handle、路径、
URI 或自由文本。Android/iOS Adapter 均支持该操作，并遵守同一 request correlation 与幂等关闭语义。

### 全屏 Native UI Flow

Flutter 调用 `present_capture_flow` 时只提交闭合的 `start_session_request` 配置。Adapter 必须从当前
attached UI owner 获取一个单调递增的 owner generation，重新确认 owner 仍存活，再全屏 present
Native UI。Android owner 是当前可 present 的 Activity，iOS owner 是当前可 present 的 ViewController；
它们只是平台映射，不进入 Base Schema。一个 stable attached UI owner identity 同时最多有一个 flow；
owner generation 只用于拒绝 stale callback，不作为 slot key。并发或重复
present 返回 `presentation_conflict`，缺少 owner、owner 已销毁、Engine detach 或 Adapter dispose
返回 `bridge_unavailable`，都不得启动新的 Capability Session。不同 `requestId` 不能绕过此限制：
`bridge_lifecycle_coordinator` 必须原子执行 owner-generation open recheck、按 attached owner identity
占用 active presentation slot。占用成功后、创建原生拍摄 UI 前，Adapter 必须按本次配置执行权限预检：
始终检查或申请 Camera；当 `video` 已启用且 `audioEnabled: true` 时再检查或申请 Microphone。全部授权
后才能创建 Capability Session 和全屏 present；拒绝、受限、永久拒绝或硬件不支持直接返回对应的闭合
Capability failure，不得展示拍摄 UI。Core 仍在 Session 初始化和录音开始前二次检查权限，避免预检后
权限被系统撤销。分步 direct method 保持 Capability 原有的按需请求时机。

Flow 只编排 `start_session`、拍照/录像、镜头/闪光/对焦/缩放控制、`retake`、`confirm` 与 `cancel`。
live preview 和 unconfirmed preview 的 attach/detach/revoke 由 Native UI 通过 Capability 的
RenderTarget Adapter API 在进程内消费；`render_target_adapter`、`owner_generation`、attachment
result/event、媒体 path/URI/descriptor 和平台 SDK 对象均没有 Wire field、payload、method 或 event。
在 Capability V3 下，Android/iOS Adapter 仍只 present Native UI；具体 surface 由对应 Native Module
factory 在进程内创建，Native UI 只持有 outer surface 生命周期，target/source/renderer/player/layer/
binding/mount endpoint 仍由 Module 私有持有。Flutter 不能创建、选择、描述或持有 surface。
Presentation-owned Session 的 Capability event/failure 也由 presentation 内部消费并驱动 UI/终态，
不得转发到 EventChannel；Flutter 对一次 flow 只能观察到下述一个终态。分步 direct method 创建的
Session 仍按 Event 映射表交付事件。

三个终态互斥并共用一次性完成门：

- `confirmed` 正常返回 `resultType: capture_flow_confirmed` 与 `confirmed_media_result_payload`；Adapter
  必须先完成 presentation cleanup，登记 confirmed lease，再 settle 已交付 lease，最后释放 slot 并完成
  Flutter。
- `cancelled` 正常返回 `resultType: capture_flow_cancelled` 与空 payload；用户取消不是异常。
- `failure` 使用闭合的 Capability/Wire error 完成；系统销毁、Engine detach 和 owner replacement
  不得伪装成用户取消。

present 顺序固定为校验请求、预留完成槽、捕获 owner generation，然后在同一 coordinator 内重新确认
owner open 并占用 slot，完成配置相关权限预检，再创建 Session 和全屏 present。权限回调返回后必须
重新确认 request、owner generation 和 slot 仍有效；失效时返回生命周期错误而不是继续展示 UI。所有
callback 与终态都引用同一个
`presentation_callback_terminal_machine`：revoke/dismiss 并等待 Session 和未确认 Preview cleanup
完成，confirmed 时按需登记资源，settle 已交付或未交付 lease，释放稳定 attached owner identity 的
slot，最后恰好一次完成 Flutter。failure 和 presentation failed 也必须通过这条 machine order 释放
未交付 lease。Engine detach 与 owner destroy 使用对应 boundary order，但保持相同 cleanup、lease、slot、
completion 先后关系。任何路径都不能先释放 slot 再异步清理旧 Session，否则新的 request 可能在旧资源
仍存活时进入 Core。

后台和显示旋转都会先 revoke/detach 当前 RenderTarget，旧 generation 因而永久退休。owner 仍存活时，
后台恢复或旋转完成必须分配一个严格大于退休 high-watermark 的 fresh generation，再显式 reattach；
不得复用 current/old generation。fresh generation 继续持有同一个 attached owner identity slot，第二个
request 仍返回 `presentation_conflict`。只有旋转实际销毁 owner 时才进入 owner-destroy 路径：revoke、dismiss、
终止 Session、清理 Preview、释放 slot，以 failure 完成且禁止自动 reattach；Flutter 如需恢复必须使用新
`requestId` 重新 present。

### Native 资源 coverage

Wire coverage 除 operation/result/event/failure 外，还完整对照 Capability `resourcePolicy.resources`
和 `ownershipPhases`。`live_preview_attachment`、`unconfirmed_preview_render_attachment`、两项
platform render surface、对应 preview/render owner scope 都固定为
`native_consumer_only`、`wireId: null` 并声明不可编码原因。其它资源也逐项说明是 payload 映射还是
明确不暴露；因此不能通过漏掉 resource/scope coverage 来间接把 RenderTarget、owner generation、
bytes、path、URI 或 SDK 对象带过 Channel。

`nativeArtifacts` 进一步逐项对照 V3 的 surface policy、factory input/output、target identity、owner
generation、双平台 concrete surface、closed conformance、mount target、source、renderer、binding 与
diagnostic policy，全部固定为 `native_consumer_only`、`wireId: null`。`mountBinding` 本身没有独立稳定
ID，coverage 因而使用 Capability 已声明的 `targetConformanceId` 作为 `capabilityId`，并由
`ownerPolicyId + platform + artifactKind + capabilityId` 组成唯一键；这不表示 conformance ID 是 mount
endpoint ID。Validator 从 Capability V3 的 factory、implementation 和 binding 结构动态展开同一集合，
同时要求每个 surface 都有 Android/iOS disposition，不能靠手写总数或描述通过。

### 有界缩略图

`read_media_thumbnail` 只接受 opaque `mediaHandle` 与 `maxPixelEdge`（64 至 512），并且只允许读取仍处于
active lease 的 confirmed media。结果 `thumbnailCopy` 是一次调用拥有的净化 JPEG copy，类型固定为
Channel bytes / Dart `Uint8List`，最长 524288 bytes；`thumbnailByteLength` 必须等于实际数组长度，
宽高都不超过请求值和全局 512 上限。输出固定 `thumbnailContentType: image/jpeg`、
`thumbnailOrientationDegrees: 0`，没有 path/URI/source-bytes fallback。

照片 `posterFrameMillis` 为 `null`。视频沿用 Capability 固定的 target、最近可解码后帧、否则前帧、
等距取早帧规则，并返回实际 frame timestamp。两端必须重新编码或等价净化，移除 EXIF、位置、设备、
源文件名与其它非展示 metadata。读取不刷新 lease、TTL、grace 或 tombstone；release/expiry/restart/
调用取消/解码失败竞态只允许一个终态，晚到 bytes 在 drop 前清零或释放。

每个新 `requestId` 最多完成一次。相同 `requestId` 在 pending 阶段或完成后 300 秒识别窗口内再次到达，
Adapter 返回 `duplicate_request`，不再次调用 Native Module，也不重放结果。该 Wire 去重窗口不延长
Capability 的 Session/Media tombstone、预览 TTL 或媒体 lease。调用者确实需要执行 Capability 允许的
重复 `stop_recording`、`cancel` 或 `release_media` 时，必须使用新的 `requestId`；幂等结果仍由 Native
Module 的既有状态机决定。

### Scoped Transfer Locator

`materialize_media_resource` 为 Flutter Consumer 提供一次性 materialize 入口。请求 payload 只包含
`mediaHandle`；Adapter 不接受 Dart 提供的 path、URI、file name、target directory、remote URL、
shared-storage locator、file descriptor、chunk sink 或任何 raw bytes。Adapter 在 plugin-owned App private
cache transfer root 下创建随机临时目标，以 typed native sink 调用 Capability V4
`copy_confirmed_media_to_sink`，并在成功复制后原子 commit 文件、登记 opaque `exportHandle`，再完成
Flutter。若 transfer store 已达到 4 个 active export 或 104,857,600 active bytes，直接返回
`transfer_store_overloaded`，不得调用 Capability；单个文件最大 52,428,800 bytes。

成功 payload 闭合为 `exportHandle`、`fileUri`、`mediaType`、`contentType`、`byteLength`、
`durationMillis`、signed-64 `expiresAt` 和可选 `integritySha256`。照片只允许 `image/jpeg`，视频只允许
`video/mp4`，长度不超过 52,428,800 bytes；完整性值存在时必须是 lowercase 64-character SHA-256 hex。
`fileUri` 是 `sensitive_local_locator`，只允许 Dart 基础设施立即导入 `app_media` Store；
禁止进入日志、error details、event、业务消息、Fixture、Route、analytics 或持久化。合法 canonical
形式使用 `file:///absolute/path`，允许 URI authority component 存在但 host 必须为空字符串；必须拒绝
非空 host、userinfo、port、query、fragment、相对路径、`.`/`..` segment，以及非法或超长 percent
encoding。完整 URI 总长度不得超过 4096 字符，4096 合法、4097 拒绝。Dart、Kotlin 和 Swift 必须共享
canonical URI 必须是 ASCII serialization：非 ASCII path scalar 先按 UTF-8 进行 uppercase percent
encoding，禁止未转义 Unicode；长度按序列化后的 ASCII code unit 计数，因此也等于 ASCII byte length。
Dart、Kotlin 和 Swift 必须共享 JSON contract 中的合法、恶意及长度边界 golden vectors，不能分别解释
“无 authority”、Unicode 序列化或长度上限。

Transfer TTL 固定 300 秒。`exportHandle` 由 Adapter 使用至少 128-bit CSPRNG 生成，采用无 padding
base64url、长度 22 至 64，只能在当前 Engine attachment 严格查表且不得复用。Engine detach 先关闭
transfer generation，取消 in-flight Capability export/sink、删除 partial file、释放容量，再完成 pending
Flutter 请求；随后删除已登记 active export。App restart、TTL、cancel、Flutter completion 失败和 late
Capability result 使用同一先清理后完成边界。TTL、Engine detach 或 Flutter completion 失败清理已登记
export 时，必须先标记 cleanup pending，再删除文件、移除 registry entry、释放容量；删除失败保留 entry
和容量继续 bounded retry。App restart 必须先关闭 transfer generation，删除私有 transfer root 下的全部
残留文件并重置 registry/容量，最后才重新开放 materialize；清扫失败时不得开放 generation。
`release_materialized_media` 只接受 opaque
`exportHandle`，删除 transfer file 并保留 300 秒 tombstone；每个 attachment 最多 4096 条，容量满时不
提前逐出旧 tombstone，而是返回 `transfer_store_overloaded`。tombstone 命中重复 release 仍返回
`materialized_media_released`；未知、过期或跨 attachment handle 返回 `materialized_media_invalid`。
首次 release 必须原子认领 handle cleanup 并预留 tombstone 容量，再删除文件、移除 active registry、
归还 active export/bytes 容量、写入 tombstone，最后完成 Flutter。不同 `requestId` 并发 release 同一
handle 时，后到请求只能加入已认领 cleanup，共享其终态，不得再次预留或执行删除/容量变更。删除失败时
保留 registry entry、active 容量和同一 tombstone reservation，用同一 claim 做 bounded retry，不得先
返回成功。tombstone 容量满使用 `capacity=release_tombstones`。release export
不释放 source media，materialize 也不自动释放 source lease。

Dart 侧调用顺序固定为：`materialize_media_resource` -> 导入 `app_media` Store ->
`release_materialized_media` -> `release_media`。任一清理失败只能做 bounded retry 或 retained cleanup；
source media 尚未成功导入前不得先 release source。

去重表在每个 Engine attachment 内最多保留 32 个 pending 请求和 4096 个未到期的 completed
tombstone。任一容量已满时，新 `requestId` 直接返回 `bridge_overloaded`，且不调用 Capability。
pending 绝不逐出，completed tombstone 在 300 秒 TTL 到期前也绝不逐出；因此容量保护不会让旧
`requestId` 越过 exactly-once 边界再次执行。Adapter 在调用 Capability 前先预留 completed
tombstone 槽；预留失败直接返回 `bridge_overloaded`，避免并发 pending 完成时突破 4096 上限。

`failureDelivery` 为每个 method 把 Capability operation Failure 无重叠地分成 direct 与 deferred。
`start_session` 的 direct 集只包含 `invalid_argument`、`session_conflict` 和
`unsupported_capability`；这些前置失败可以在创建 Session 前完成 method。权限三态、
`resource_in_use`、`storage_full` 与 `system_interrupted` 只允许在 `session_created` 已返回后通过
`session_failed` event 交付，不能再把同一原因返回为 method error。

其它 method 没有先行成功结果，其 operation Failure 直接且恰好一次完成 pending method，
`deferredFailureIds` 为空。Capability 发出的任何 `session_failed` 都是独立的 Session 终止通知，
Adapter 必须原样转发，即使其中的 Failure code 与刚完成 method 的 error code 相同；它既不用于第二次
完成 method，也不能因缺少 correlation ID 而被猜测、吞掉或去重。

### `open_media_read` 的边界

`open_media_read` 在机器可校验的 coverage 中明确标记为 `native_consumer_only`，其
`scoped_media_read` 结果标记为 `intentionally_not_exposed`。Capability 的 `read_access` 只在 Native
Module 控制的 callback scope 内有效，不能被诚实地编码成可跨 Channel 存活的 String。另一方面，
本任务禁止传输原始媒体 bytes、路径或 URI，也不能虚构 `read_chunk` 等新操作。因此 V2 Flutter Bridge
不提供对应 method；纯原生 Consumer 仍可直接使用 Capability API。

这不是平台缺失或静默 fallback。若 Flutter Consumer 后续需要读取/上传确认媒体，必须先为安全的
跨 Runtime 导出或流式读取语义建立新的 Capability 版本，再派生新的 Wire 版本。V2 的 bounded
thumbnail 只供展示，不能当成原图读取或上传 fallback。

## Event 映射

| Wire event | Capability event | 触发语义 |
| --- | --- | --- |
| `session_ready` | `session_ready` | 权限和资源准备完成，携带控制能力快照 |
| `session_failed` | `session_failed` | Session 以 `terminalFailureId` 指定的终止 Failure 结束 |
| `media_preview_ready` | `media_preview_ready` | 录像达到时长上限并自动生成预览 |
| `media_lease_expired` | `media_lease_expired` | lease 到期并拒绝新读 |
| `media_read_revoked` | `media_read_revoked` | 60 秒读 grace 结束，既有读被撤销且存储已删除 |

Capability 的 `render_attachment_revoked` 不在 EventChannel 表中。它与 attach/detach result 一样只供
Native UI 消费，coverage 固定为 `native_consumer_only`、`wireId: null`；Adapter 必须在对应 owner
generation 内处理 revoke、detach 与 cleanup，不能把它编码为 Flutter event。

每个 Engine attachment 最多有一个事件 sink。EventChannel listen 参数按结构化
`eventListenEnvelope` 检查；未知版本、缺少版本或任何额外 key 都拒绝订阅。事件没有 Bridge 级重放，
也不生成新的 Capability 状态。第二个 listen 返回 `listener_already_active`，保留现有 sink，不允许
replace。Cancel 移除当前 sink，之后允许 relisten；每次成功 listen 使用递增 generation，旧 generation
的 late event 一律丢弃。Listener cancel 只解绑 sink，不等价于用户 `cancel`、`release_media` 或
Native Module 生命周期结束。

### Capability failure emission

Capability 的 `preview_timed_out` transition 直接 emission `failure: session_timeout`，它不是
`session_failed` event。Wire 以独立 `failureEnvelope` 和 `session_timeout_failure_payload` 映射该
事实：`failureType` 固定为 `session_timeout`，payload 只含 `sessionHandle`。Adapter 在 UI 线程通过
EventChannel 发送该 failure envelope，发送后保留当前 sink；不得把它改名为 Capability event、
PlatformException method error 或 listener 终止。

## 错误与取消

Wire 为可跨 Channel 的 Capability Failure ID 建立稳定映射，`recoverable` 与 `terminal` 属性
不变；`attachment_generation_retired` 与 `attachment_target_conflict` 只涉及 Native target identity，
因此固定为 `native_consumer_only`。已映射的 Failure
并不全部通过 `PlatformException` 交付：`failureDelivery.directFailureIds` 才完成对应 pending method；
`session_failed` 作为普通 event 携带 `terminalFailureId`；`preview_timed_out` 的 `session_timeout` 使用
独立 async failure envelope。Bridge 自己只增加 11 个 Wire/传输错误，不把它们伪装成 Capability Failure：

| code | 含义 |
| --- | --- |
| `incompatible_wire_version` | 请求版本不是当前 Adapter 支持的 Wire 版本 |
| `invalid_wire_payload` | Envelope/Payload 存在未知、缺失、类型或 validation 错误 |
| `duplicate_request` | `requestId` 在当前去重窗口已存在 |
| `bridge_unavailable` | Engine、Activity/ViewController 或 Adapter 已分离，无法完成 Wire 调用 |
| `bridge_overloaded` | pending 或 completed 去重表已达固定容量，请求未进入 Capability |
| `wire_encoding_failed` | Native 结果或事件不能编码进声明的 Wire 类型/范围 |
| `listener_already_active` | 当前 Engine attachment 已有 event sink，新 listener 被拒绝 |
| `presentation_conflict` | 当前 UI owner 已有一个 flow，拒绝重复或并发 present |
| `transfer_store_overloaded` | Adapter transfer store active export/bytes 容量满，或 release tombstone reservation 容量满 |
| `transfer_store_unavailable` | Adapter 私有 transfer root 不可用或生命周期已关闭 |
| `materialized_media_invalid` | export handle 未知、过期或 tombstone 识别窗口结束 |

Capability V4 export Failure 一一映射为 `media_export_conflict`、`media_export_overloaded`、
`media_export_too_large`、`media_export_sink_rejected`、`media_export_read_failed`、
`media_export_write_failed`、`media_export_cancelled` 和 `media_export_timed_out`。这些 code 的
`source` 固定为 `capability_failure`，Adapter/Wire 自有的 transfer store 和 handle 错误固定为
`wire_protocol`；不得使用来源含混的 `export_failed` 或 `export_invalid`。所有错误 details 都不得回显
`fileUri`、`exportHandle`、media handle、底层 path、URI、OS error、异常或 stack。

`PlatformException.message` 使用静态脱敏文案。`errorDetailFields` 为每个 details key 固定 type、
source、enum、最大长度或 signed-64 范围：`operation` 只能是已声明 method 或
`unknown_operation`；`field` 只能是已声明 key 或 `unknown_field`，不得回显攻击者输入；`reason`、
`lifecycleReason`、`capacity` 都是闭合集合。details 不得包含 handle、`requestId`、payload、路径、
URI、bytes、媒体元数据、堆栈、底层异常或 SDK 对象。

用户 `cancel` 成功返回 `session_cancelled`，不是 `PlatformException`。权限拒绝、系统中断和编码失败
严格按 `failureDelivery`、`session_failed` 或 async failure envelope 的结构化映射交付；Bridge 不将
它们改写为取消。

## 线程与生命周期

Adapter 可以在平台适合的工作上下文中解码和调用 Native Module，但所有 MethodChannel result 与
EventChannel event 必须切回平台 UI 线程：Android 使用 main thread，iOS 使用 main actor/main
queue。Native Module 的采集、编码、资源和文件生命周期仍由 Capability 拥有，不因 Channel callback
要求而迁到 UI 线程。

Adapter 为每个请求维护一次性完成门。成功、Capability Failure、Wire error 或生命周期关闭只能赢得
一次完成。Generation open check、resource adoption、非资源结果决策、exactly-once completion 和
boundary close/scan 全部在同一个 `bridge_lifecycle_coordinator` 上线性化，不能分散到独立锁、队列或
异步回调。初始 presentation 在该 coordinator 内原子 recheck owner generation、按稳定 owner identity
占用 slot，再创建
Session。Callback/terminal 赢得顺序固定为：重新确认 generation open、完成 presentation cleanup、
confirmed 时按需登记资源、按 ownership settle delivered/undelivered lease、释放稳定 owner slot、最后
恰好一次完成 Flutter。`linearizationPolicy.callbackWinOrder`、presentation terminal/slot policy 与两个
capture-flow `resultCompletionPolicies` 都引用同一 `presentation_callback_terminal_machine`，不得各自
维护不一致的子顺序。
`session_created` 必须先登记 active Session，`confirmed_media` 与 `capture_flow_confirmed` 必须先登记
attachment lease；其它结果也在同一 coordinator 内决定完成，只是不新增 adoption。登记和 Flutter
completion 之间不得释放 coordinator。`media_thumbnail` 只有调用范围内的 bytes copy，不进入长期
lease registry；边界获胜时仍必须先清零/释放 late copy 再 drop。

Boundary 赢时先关闭 generation，再以 `bridge_unavailable` 赢得尚未 settle 的完成门并扫描已登记资源；
之后到达的资源结果不得成功完成 Flutter，必须按 `lateResultPolicies` 清理后再 drop。Late cleanup 不得
触发第二次 Flutter completion。Engine detach 首先原子关闭 attachment generation 和 UI owner
generation、revoke/dismiss presentation；随后通过 Capability 已有
`capability_failure/system_interrupted` 终止所有 Flutter-originated active Session，等待未确认 Preview
清理，并调用 `release_media` settle pending flow lease 与该 attachment 持有的 confirmed lease。上述
cleanup 完成后才释放 active slot，最后以 `bridge_unavailable` 完成尚未 settle 的 pending request。
新 Engine
attachment 使用全新 generation，不继承 callback、request registry、Session 或 lease。

Activity/ViewController destroy 关闭对应 UI owner generation，先 revoke/dismiss 旧 presentation，
并用相同 Capability failure 语义终止 active Session、清理 Preview 和 pending lease；cleanup 完成后
释放 active slot，最后以 `bridge_unavailable` 完成仍绑定旧 UI owner 的 pending 请求。它不伪装成
用户 `cancel`。Engine attachment 仍存活，
因此已经交付的 confirmed lease 与 event sink 保留。新 UI owner 使用新 generation，不继承旧
Session；旧 generation callback 丢弃。上述顺序确保 callback 与销毁不能双重完成。

UI owner boundary 之前已经在 coordinator 中登记并成功交付的 confirmed lease 由 Engine 继续持有；
boundary 之后才返回、尚未交付的新 lease 必须释放。Engine detach 的 boundary scan 则释放此前已经登记
并成功交付的全部 attachment lease。两种 boundary 对晚到 `confirmed_media` 都执行 release。
Capability V3 surface/source/renderer/binding 从不成为 Bridge result，因此不新增 late-result shape；
它们在 Native revoke/detach/owner-destroy gate 内先停止 callback 和 mount mutation、完成 Module cleanup，
Bridge 再沿用既有 Session/Preview/lease/slot/completion 顺序。

`lateResultPolicies` 覆盖 9 个直接映射结果和两个 presentation 正常终态，并同时绑定
`engine_detach` 与 `ui_owner_destroy`。Pending
method 已由 `bridge_unavailable` 完成后，晚到 `session_created` 必须立即对返回 Session 执行
`capability_failure(system_interrupted)`；晚到 `media_preview` 及其它仍可能持有 Session 的结果使用
原请求 Session 执行同一终止语义并清理 Preview；晚到 `confirmed_media` 无论来自哪种 boundary 都
立即 `release_media`。已在 UI owner 销毁前成功交付的 confirmed lease 仍按前述规则保留，只有晚到的
新 lease 被释放。晚到 `capture_flow_confirmed` 必须释放 lease、终止 Session、清理 Preview 后再
drop；晚到 `capture_flow_cancelled` 必须确认取消清理已经完成；晚到 `media_thumbnail` 必须先清零或
释放 bytes copy。`session_cancelled`、`media_released` 先确认没有活资源再丢弃。所有策略都要求先完成
Native cleanup、再 drop callback，且绝不第二次完成 Flutter。

Event payload 在 UI 线程发送前也必须经过出站类型和 signed-64 检查。编码失败以
`wire_encoding_failed` 终止当前 event sink，后续 callback 对该 sink 丢弃；Adapter 不伪造 Capability
Failure，不取消 Session，也不改写文件 lease。

日志继续只允许稳定 operation/state/failure/status 值并在记录创建前脱敏。surface instance、factory
input/output、target/source/renderer/binding/mount endpoint、owner generation、平台对象说明、路径、媒体
bytes 与 raw exception 均不得进入 Channel、错误 details 或日志；V3 diagnostic policy 只在 Native
Module 内消费，不生成 Wire event。

这些边界只复用 Capability 已存在的 `system_interrupted`、`capability_failure`、`release_media` 与
清理语义，不新增 Native 状态，也不把系统销毁伪装为用户取消。

## 平台一致性

17 个 method、5 个 event 与 1 个 async failure 在 Android/iOS 的支持矩阵均为 `supported`，Payload、
错误码、取消、presentation owner、去重和完成语义一致。两端只在 UI callback 调度机制和实际 owner
类型、私有 cache/temporary transfer root API 上有实现差异。Capability V3 的 Android/iOS concrete surface artifact 各自有独立 coverage，但两端
都保持 Native-only，因而不形成 Wire 平台差异。权限可重试判断、私有临时目录等
差异属于 Capability Contract，Adapter 只映射其稳定语义，不向 Wire 暴露平台 SDK 细节。

## 端到端顺序

1. Dart Client 使用 Wire V3、一个新 `requestId` 和闭合拍摄配置调用 `present_capture_flow`。
2. Adapter 校验 Envelope/Payload、预留去重/完成槽，并捕获当前 open UI owner generation。
3. Adapter 全屏 present Native UI；Native UI 直接调用 Core 类型化 API并在本地 attach live preview。
4. 用户拍照/录像与控制由 UI 编排既有 operation；进入 Preview 时先 revoke live scope，再 attach
   unconfirmed preview scope。
5. 用户重拍回到 ready；用户确认后 Adapter 按共同 terminal machine 先 dismiss/清理、登记并 settle
   lease、释放 slot，再返回 `capture_flow_confirmed`；用户取消和 failure 同样先完成各自 lease cleanup
   与 slot release，再返回 `capture_flow_cancelled` 或稳定 error。
6. Flutter 用返回的 `mediaHandle` 调用 `read_media_thumbnail` 显示净化缩略图，或调用
   `materialize_media_resource` 获得短生命周期 transfer locator。导入 Store 后必须调用
   `release_materialized_media`，随后才调用 `release_media` 结束 source lease；Flutter 仍不能打开原始
   media read scope。
7. 需要底层分步控制的 Flutter Consumer 仍可调用分步 `direct_operation` method；两种入口委托同一
   Native Module，不能同时创建冲突 Session。

## 实现与验证位置

Contract 的实现固定落在原生架构约定的 `app/packages/app_media_capture_bridge/`：Dart Client 在
`lib/`，Android/iOS Adapter 分别在 `android/` 与 `ios/`。两端 Adapter 已用 Native Module Fake 覆盖
Payload 映射、版本、错误、去重、listener、detach、线程和 exactly-once，并由双端 Gate 与 Host build
验收真实依赖图。

Harness 当前验证固定 Schema/Profile 路径、Wire V3 对 Capability V4 的精确兼容、Wire V2 history
projection、全部 operation/result/event/failure/resource/ownership-scope 和 V3 Native artifact coverage、
direct/presentation 分型、三终态、owner generation、原子
slot reservation/release、共同 callback/terminal machine 与 lease settlement、background/rotation
fresh generation、支持矩阵、Channel 基础类型、
错误 details、`open_media_read` 与 Native render scope 明确不暴露、`preview_timed_out` failure
emission、opaque handle 长度、signed-64、缩略图 bytes/尺寸/长度/JPEG/orientation/poster/EXIF/无路径
fallback、CSPRNG export handle、native sink/fixed-length input coverage、transfer result MIME/长度/完整性、
精确 file URI golden vectors、严格有序 cleanup、TTL、容量、独立有界 tombstone、redaction、有限去重表、listener
generation、双生命周期清理、late lease/copy/transfer 清理、数据分类和安全策略以及本文档链接。最终
Integration 还要求 Dart/Kotlin/Swift 直接消费同一份 V4/V3 golden，并锁定真实 Host SwiftPM/Gradle 接线。

## 变更日志

- Wire V1 / Capability V1：建立 12 个 method、5 个 event、1 个 async failure、14 个 Capability
  error 与 7 个 Wire error；明确 callback-scoped `open_media_read` 只供 Native Consumer 使用，并
  固定句柄、整数、去重表、listener、生命周期、error details 与出站编码边界。
- Wire V2 / Capability V2/V3：新增 `read_media_thumbnail` 和 `present_capture_flow`，固定 presentation
  三终态、UI owner generation、full-screen present/dismiss、后台/旋转/detach、resource adoption 与
  lease settlement 的共同 callback/terminal machine、late cleanup；完整关闭 Native preview coverage，
  并只向 Flutter 增加有界净化的 `Uint8List` JPEG。Capability V3 的 concrete surface、factory、
  conformance、mount、source、renderer、binding 和 diagnostic 全部保留在 Native，Wire shape 不变。
- Wire V3 / Capability V4：新增 `materialize_media_resource` 与 `release_materialized_media`，以
  Adapter-owned App private cache transfer store、canonical short-lived `fileUri`、128-bit CSPRNG
  `exportHandle`、固定 native sink/50 MiB binding、可选 SHA-256、300 秒 TTL/tombstone、4 active export、
  104,857,600 active bytes、4096 release tombstone 和严格有序 exactly-once cleanup 映射 V4
  bounded export。Channel 只传有界 metadata 和 scoped locator，不传 raw bytes/chunk/source path；
  release export 不释放 source media，Dart 必须先导入 Store 再释放 export 和 source lease。
