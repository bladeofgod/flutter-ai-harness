# 原生媒体拍摄基础能力

> 决策状态：已批准。实现状态：Capability V4/Wire V3、双端 Core/UI/Adapter、Flutter Client、Host 与平台 Gate 已实现；Android 设备流程与 iOS 真机系统能力待人工验收。

[返回基础模块索引](../infrastructure-modules.md)

Media Capture 是项目批准的基础能力，首个真实消费者是 Shoppe 订单评价。它同时服务纯原生业务与
Flutter 业务，但能力本身归 Android/iOS Native Module 所有。仓库已经完成双端 Core、concrete surface、
V4 有界导出、Native UI、Wire V3、Dart Client、Bridge Adapter 和 Host 接线；Customer Support 通过
`app_media` Store 保存资源 ID，并复用图片/视频 Thumbnail 与 Viewer。

结构化事实源：

- [Capability JSON Schema](../native/contracts/capability.schema.json)
- [Media Capture Capability Contract](./contracts/media-capture.capability.json)
- [原生架构](../native-architecture.md)

## 分层实现状态

| 层级 | 当前状态 | 边界 |
| --- | --- | --- |
| Capability V4 Contract / Schema / Harness | 已实现并通过静态门禁 | 定义受控流式导出、历史投影和跨 Runtime golden；静态门禁不替代真机 |
| Android Core | 已实现并通过专项 Gate | CameraX、concrete surface、缩略图、V4 export 与资源清理均有本地/构建证据 |
| iOS Core | 已实现并通过专项 Gate | AVFoundation、Rendering product、严格并发 compile 与 Simulator XCTest 已通过 |
| Android/iOS concrete surface | 已实现 | Module 提供 `MediaCaptureRenderView` 与 module-internal mount endpoint |
| Android/iOS Native UI | 已实现 | 只组合 concrete surface 和 Core API，不持有 source、renderer 或 backing target |
| Wire | Wire V3 已实现 | V3 surface 与 V4 sink 保持 Native-only；Channel 只提供短期一次性 transfer copy |
| Dart Client / Bridge Adapter / Host | 已实现 | 双端标准 Plugin 注册；Host 不拥有 Core 状态、媒体文件或 render binding |

Android 专项静态 Gate、JVM/Robolectric、Debug APK、iOS 专项 Gate、Simulator XCTest 与真实 Demo
no-codesign Runner build 已通过。Android instrumented/真机拍摄流程未运行；iOS 真机 Camera/Microphone、
系统权限弹窗、硬件中断或性能也未验收。这些项目保留给人工设备验收。

## 依赖边界

```text
Android Native Consumer -> Android Media Capture Native Module
iOS Native Consumer -> iOS Media Capture Native Module

Flutter Consumer -> Dart Client -> Android/iOS Bridge Adapter
                              -> 对应 Media Capture Native Module
```

原生业务直接调用所属平台的类型化 Native API，不经过 Flutter。Dart Client 与两端 Bridge
Adapter 是另一条消费者链路，只负责把后续 Wire 语义映射到本契约，不能拥有或修改拍摄
状态机、权限和文件策略。两端可以采用符合 Kotlin/Swift 语言惯例的不同 API 形态，但必须
映射到同一稳定 operation、state、result、cancel 和 failure 语义，也不得公开平台采集框架
内部对象。

现有平台 Core 路径分别为 `app/native/android/media_capture/` 与
`app/native/ios/MediaCapture/`。共享文档只维护跨平台语义与平台详情链接；实际依赖、实现
状态、生命周期证据和构建命令由各自平台详情文档维护，避免并行任务争写共享状态。

## Capability 版本

- Version 1 建立 Session/Media 状态机、权限、确认媒体租约、Native callback-scoped 原始媒体读取、
  opaque handle 与清理语义。
- Version 2 是 additive 演进：完整保留 Version 1 operation/state/failure 语义，新增 Native-only
  Render attachment 和已确认媒体的受限缩略图 copy。
- Version 3 是 additive 演进：保留 Version 1/2 全部 operation、state、failure、lease、thumbnail、handle
  与 generation 语义，新增模块定义的 concrete platform render surface、实际挂载、所有权和撤销模型。
  Capability Version 与 Wire Version 继续独立。
- Version 4 是 additive 演进：保留 Version 1-3 全部语义，新增从 active confirmed media 到调用方提供的
  Native-only typed sink 的有界流式复制。Wire V3 已显式派生 Capability V4，同时保留 Wire V1/V2 历史
  投影，并继续把 platform render surface 与 Native sink 关闭为 Native-only。

## Version 1 公共能力

V1 支持开始会话、拍照、开始/停止录像、切换镜头、闪光灯、对焦、缩放、拍后预览、重拍、
确认、取消，以及确认后对媒体句柄执行模块受控的打开只读访问和释放。滤镜、美颜、贴纸、
涂鸦、裁剪、相册导入/保存、远程上传和生产媒体服务不属于 V1。

`start_session` 不等待权限和相机准备完成：它先返回可立即取消的 `session_created` 与 opaque
session handle，再用 `session_ready` event 交付镜头、闪光、对焦和 zoom 能力快照；权限、资源
或系统中断导致的终止通过 `session_failed` event 交付稳定 terminal Failure。每个 operation
都在 Contract 中列出唯一成功 result、可能 event 和允许的 `failureIds`，实现不得返回未声明
Failure。Operation 还通过 `resultScope` 指定唯一结果交付状态机：跨 Session/Media 的
`retake` 与 `confirm` 只由 Session transition 返回 result，Media companion transition 只
推进所有权状态并声明 `emission: none`，不得重复交付。录像达到 `max_video_duration_millis` 时自动停止，并用 `media_preview_ready` event
交付与手动停止相同约束的预览元数据。

专用 Media Capture Figma 不是实现前置条件。后续 Native UI 按用户批准的微信式拍摄器交互
方向实现点击拍照、长按录像和上述控制，但不复制微信品牌资源或逐像素样式；Shoppe 订单
评价入口、附件状态和页面语言继续复用现有 Token。手势、布局与动画不是 Native Module
公共 API，本 Capability 只固定它们背后的 V1 行为边界。

## Version 2 Native Render attachment

Native UI 不直接持有或控制平台采集 Session。Android/iOS Core 分别实现平台内部的
`RenderTarget Adapter`，公共 Capability 只把它表达为 callback resource；它不能返回媒体 bytes、
路径、URI、文件描述符、采集 Session、具体 UI 对象或平台 SDK 类型，也不能通过跨 Runtime
传输公开。

`attach_live_preview` 只允许 ready/recording Session，`attach_unconfirmed_preview_render` 只允许
处于 `preview` 的未确认 Media。两者都必须携带正数 `owner_generation`，每个目标同时最多一个
attachment。Core 为每个 Session/Media scope 保留单调 generation high-watermark，直到 scope
terminal 或 registry invalidation；retired generation 永不重新接受。只有严格大于 high-watermark 的
generation 能在原子 compare-and-advance 后替换 binding，并且先更新 high-watermark，再撤销旧 binding。
当前 active binding 的 generation 与 target adapter instance identity 都相同时才幂等复用；detach 后
同 generation 已 retired，不能重新 attach。同 generation 换 target
稳定返回 `attachment_target_conflict` 且不改变 binding。低于 high-watermark 的乱序 attach 返回
`attachment_generation_retired`，不得 revoke、detach、触发 callback 或影响当前 owner。

Fresh generation replacement 的公共顺序固定为
`compare-and-advance high-watermark -> revoke old callbacks -> detach old target -> attach new target ->
commit result`；不得先 attach 新 target，也不得在 high-watermark 提交前改变 binding。

两个 detach request 都必须携带原 attach 使用的 Native-only `render_target_adapter`。显式 detach 可重复
调用，但只有 generation 与 adapter instance identity 同时匹配当前 binding 时才执行 revoke/detach；
stale generation 或 mismatched adapter detach 是保持当前 binding 的 no-op。因此 adapter B 使用同一
generation attach 被拒后，不能用 B detach adapter A。所有 render callback 必须回到
owner UI thread，并在每次渲染前同时核对 active scope 与 owner generation；旧 generation callback
只能丢弃，不能重新 attach 或渲染。

Rotation、后台、owner destroy、Core close、App restart 都按
`invalidate generation -> stop callbacks -> detach -> state/resource cleanup` 顺序撤销两类 attachment。
Live preview 在拍照、手动/自动停止录像或 Session terminal 前同样先撤销；未确认预览在 retake、
cancel、confirm、failure 或 preview timeout 前先撤销，再删除或转移媒体。前台恢复必须由新的 UI
owner generation 显式 attach，Core 不暗中保留已销毁 owner。

## Version 3 模块定义 Platform Render Surface

V2 attachment 的 operation、field 与 generation 状态机原样保留。V3 不新增跨 Runtime 参数，而是把
`render_target_adapter` 可接受的生产实现闭合为模块定义的 concrete platform surface：Native UI owner
持有外层 `MediaCaptureRenderView` 的创建、挂载位置和销毁生命周期；Native Module 独占 live/file
source、renderer/player/layer、backing target binding 与 cleanup。Owner 不能取得这些内部对象，也不能把
任意 `View`、`UIView`、`CALayer`、空 factory、identity marker 或 opaque token 伪装成 surface。

每类 surface 的 factory contract 都有两个必需输入：已登记的 surface lifecycle ownership phase 与
正数 owner generation；唯一输出是对应 `module_defined_platform_surface` resource。输出必须 non-null、
每次 factory invocation 都是 fresh concrete instance，并满足所属平台声明的 closed target conformance。
Closed conformance 只接受明确列出的 backing target kind，拒绝 arbitrary target；factory output type、
conformance ID 与 module-internal mount endpoint type 必须逐项一致。

Mount binding 不是 UI 可实现的 callback。它把 factory output resource、V2 attachment policy、owner
generation field、surface lifecycle ownership phase 和 closed conformance 绑定到一个 module-internal
强类型 endpoint。Endpoint、backing target、source、renderer 和 binding 的 owner 都必须是 Native Module；
Native consumer 仍只拥有外层 surface lifecycle。结构中任一关系缺失、开放或改为 consumer-owned，都不
满足 actual mount。

Android Module 提供 concrete `MediaCaptureRenderView`，内部拥有 CameraX `PreviewView`/
`SurfaceProvider`、photo content renderer 与 video player surface。iOS Core product 继续保持传输中立，
独立 `MediaCaptureAppleRendering` product 提供 concrete `MediaCaptureRenderView`，内部拥有
`AVCaptureVideoPreviewLayer`、photo content 与 `AVPlayerLayer`。这些 Framework 对象只存在于所属 Module
内部，不进入 Core capability field、Native UI 公共 owner API 或 Channel。

两类 V3 surface 固定为 live Session surface 与 unconfirmed photo/video surface。每类都必须在 Android、
iOS 实现实际挂载：Module 同时能访问私有 source 与 surface backing target，并把真实 renderer 安装到
外层 surface；仅保存 source、仅发送状态通知、空 factory 或 identity-only binding 都不算挂载。
安装顺序固定为：

```text
validate active scope
-> validate target identity
-> validate owner generation
-> validate lifecycle gate
-> connect private source to module renderer
-> mount renderer into surface
-> commit binding
```

install 前以及每次 target mutation、observer/player callback 前，都必须重新校验 active scope、target
identity、owner generation 与 lifecycle gate。被动 Framework pipeline 不伪造逐硬件帧 callback；旧
generation 的 callback 或 mutation 直接丢弃，不得触碰当前 surface。

revoke、detach 和 replacement 共用以下完整顺序：

```text
invalidate callback gate
-> disconnect source/session/player
-> remove module renderer/content
-> clear module renderer/content
-> detach surface
-> cleanup binding registry/state
```

cleanup 对每个 active binding exactly once。Rotation、后台、owner destroy、terminal、Core close 与 restart
继续沿用 V2 high-watermark、target identity 和 fresh generation 规则；恢复或替换必须使用严格更新的 owner
generation 与 fresh binding。Fresh replacement 先 compare-and-advance high-watermark，再按上述 revoke 顺序
完整清理旧 binding，保持 generation high-watermark 后按 install 顺序挂载新 renderer；retired generation
永远不能重新修改 surface。

Surface 只允许 Native consumer 使用。禁止对它做任意跨 Runtime 编码，也禁止把 platform SDK source、
capture session、preview/player layer、SurfaceProvider、sample/pixel frame、媒体 bytes、路径、URI、文件
描述符、`AnyObject`、untyped Map 或 opaque token 投影到 Wire。Version 3 因而只补齐平台内部渲染通路，
不扩大 Flutter 媒体读取面、Native UI 的 source 权限或文件所有权。数据分类上，surface 是 Native-only
生命周期资源，不是媒体数据、序列化 payload 或不透明数据令牌；backing target、source、renderer、binding
和 cleanup 状态均为 Module-private。

Render Surface 诊断采用结构化白名单。记录只能包含稳定的 record kind、operation ID、lifecycle state、
stable Failure ID 和脱敏 status enum，并且必须在创建记录前完成脱敏。日志禁止包含 surface/target 实例或
描述、owner generation、source/renderer/binding/mount endpoint、平台 SDK 对象或描述、路径、媒体 bytes、
opaque token 和 raw exception。平台异常只能映射为稳定 Failure ID 与 `redacted_failure`，不能把底层异常
文本、对象 `description` 或实例 identity 作为调试便利写入日志。

白名单同时逐字段声明值来源，不能只限制字段名。`operation_id`、`lifecycle_state` 和
`stable_failure_id` 分别绑定当前 Capability Contract 的 operation、全部状态机 state 和 failure ID
完整集合；`record_kind` 与 `redacted_status` 分别回指本诊断策略声明的 record-kind/status enum。来源类型、
结构化引用或允许集合任一不一致都必须拒绝，因此未声明的 operation/state/failure 字符串不能进入日志。

## Version 2 受限缩略图

`read_media_thumbnail` 只接受 opaque `media_handle` 与 `max_pixel_edge`。边界必须是有限整数
`64..512`；非法类型或越界返回 `invalid_argument`，未知 handle 返回 `media_invalid`，已识别但不在
`leased` 状态返回 `invalid_state`。只有已确认且 24 小时 lease 仍 active 的 Media 可开始读取；
`preview`、两种 grace、discarded、released 和 expired 均拒绝新请求。读取不会刷新或延长 lease、
TTL、grace 或 tombstone。

开始 source access 前，Core 必须先登记一个 module-owned managed generation job。Job 独占 source
access、decoder 和 module-owned generation buffer；partial encoded output 与 decoded pixels 在 atomic
result commit 前都不属于 caller。成功 commit 在同一 linearization point 把独立 bounded copy 的物理
所有权原子转给 caller；此后 source release、TTL、restart 或 Core cleanup 都不能撤销或修改已提交 copy。

成功结果不是原始媒体读取能力。输出固定为重新编码或等价
净化的 `image/jpeg`，最多 524288 bytes；宽高必须为正，且都不超过请求 `max_pixel_edge` 和全局
512 上限。`thumbnail_byte_length` 必须等于实际 copy 长度，像素物理旋转为 upright 并固定
`thumbnail_orientation_degrees: 0`。结果同时声明来源 `media_type`。照片
`poster_frame_millis` 为 null；视频 target 固定为
`min(1000, floor(duration_millis / 2))`，优先 target 或其后最近可解码帧，没有时选 target 前最近帧，
等距选更早帧，并返回实际帧时间。

缩略图移除 EXIF、位置、设备、原始文件名和所有非展示元数据。它不得返回 source bytes、路径、
URI、文件描述符、任意 Map 或平台 SDK 类型；日志、错误 details 和 cache key 均不得记录媒体内容、
handle 或路径。底层解码失败映射为不含 backend details 的 `thumbnail_generation_failed`。

Result commit、caller cancel、release、TTL、restart 和 decoder failure 共用
`atomic_terminal_outcome_commit` linearization point；第一个 terminal trigger 获胜，outcome exactly once，
失败 winner 的 cleanup exactly once。Result commit 先赢时，后续 source 状态变化只处理 source/job，
不能撤回 caller copy。其它 winner 按固定顺序执行：`revoke source access -> cancel and await decoder ->
close source handles -> wipe decoded pixels -> wipe module generation buffer -> discard partial copy -> unregister
managed job`，全部完成后才交付唯一 Failure。`unregister managed job` 必须最后执行，作为 registry、并发计数
和预算占用的最终释放点。Caller cancel 返回 `thumbnail_generation_cancelled`；release/TTL 返回
`invalid_state`；restart 返回 `media_invalid`；decoder failure 返回 `thumbnail_generation_failed`。

成功 ownership transfer 由 `thumbnail_result_committed` 触发 exactly-once finalization，并且在 result
delivery 前依次执行：`close source access -> finish and close decoder -> close source handles -> wipe decoded
pixels -> wipe module generation buffer -> unregister managed job`。`unregister managed job` 同样是 registry、
并发计数和预算占用的最终释放点。Caller copy 在原子 ownership transfer 后已经独立，不属于 cleanup 或
finalization sequence；finalization 不能读取、擦除、撤销或重新接管它。

资源预算在访问 source 前执行：同一 Media 最多 1 个、同一 Module 最多 2 个 in-flight generation
job；单 job decoded-pixel 上限 1048576，working-memory 上限 8388608 bytes，Module working-memory
上限 16777216 bytes。Decoder 必须在完整分辨率分配前执行 decode-time subsampling。并发或预算不足
稳定返回可恢复、非终止的 `thumbnail_overloaded`，不得先打开 source 再等待资源。

Native callback-scoped `open_media_read` 仍只服务 Native Consumer。Version 2 没有允许 Flutter
读取原始媒体；后续 Wire 只能映射受限、净化且有上限的 thumbnail copy。

## Version 4 确认媒体流式导出

`copy_confirmed_media_to_sink` 只在 `media_handle` 仍处于 active `leased` 状态时开始。请求还必须携带
调用范围内的 typed `MediaCopySink` 与 `media_export_max_length`。Sink 是 Native consumer object，不能
序列化、写入 Module registry 或使用字符串路径、URI、文件描述符、平台 SDK 文件对象代替。照片 source
固定为 `image/jpeg`，视频固定为 `video/mp4`；其它类型返回 `invalid_state`，不会隐式转码或扩大能力面。
Capability Profile 通过 `sourceRepresentations` 机器化声明 `photo -> image_jpeg -> image/jpeg` 与
`video -> video_mp4 -> video/mp4`，平台实现和后续 Wire 不得自行推断或替换 MIME literal。

Sink 协议固定为 `begin -> sequential write* -> commit xor abort`。`begin` 接收媒体类型、content type 与
声明长度；每次 `write` 最多 262144 bytes；成功且长度一致时 `commit` 恰好一次。已经成功 begin 后的
失败、取消、release、expiry 或 Core close 必须 `abort` 恰好一次；commit 与 abort 互斥。容量预检、非法
参数、未知 handle 等尚未 begin 的拒绝不得调用 sink。Sink 的四个方法都必须响应结构化任务取消，并在
收到取消后 5 秒内收敛；不满足这一点的 consumer 不符合 Capability conformance。

Module 在打开 source 或 sink 前，原子预留一个 `media_export_job` 和一个 `media_export_buffer`。同一
Media 最多 1 个 active export job，同一 Module 最多 4 个；单 job buffer 上限 262144 bytes，Module
总 buffer 上限 1048576 bytes。容量不足返回 `media_export_conflict` 或 `media_export_overloaded`，不等待、
不调用 sink、不打开 source，也不逐出既有 job。复制只允许有界 chunk 流，禁止把完整照片或视频加载到
内存。

媒体最大复制长度为 52428800 bytes。Module 在复制前验证 source 声明长度不超过请求/全局上限，在每次
write 前累加并验证长度，在 commit 前验证实际长度与声明长度相等。超限、复制中增长或截断都返回
`media_export_too_large`，不得截断、补齐或静默降质。成功结果只包含原 source 对应的 `media_handle`、
`media_type`、`content_type` 和实际 `byte_length`；不返回 sink 的路径、URI、句柄、平台对象或 raw bytes。

每个 job 从 registry reservation 成功时开始 120 秒 deadline。Caller cancellation、deadline、
`release_media`、lease expiry 与 `core_closed` 共同竞争 `media_export_terminal_outcome_commit`；第一个赢家
关闭 callback gate，取消 copy task 与 sink，失败路径 abort begun sink，关闭 source，擦除并释放 buffer，
最后 unregister job。晚到 callback/result 只丢弃，不能 commit、abort 或第二次完成。成功路径在完整长度
校验后 commit sink，再关闭 gate/source、擦除并释放 buffer，最后 unregister job，之后才交付唯一 result。

V4 新增的 direct、recoverable、non-terminal Failure 为：

- `media_export_conflict`：同一 Media 已有 active job；sink 未调用。
- `media_export_overloaded`：Module job/buffer 容量已满；sink 未调用。
- `media_export_too_large`：声明、累计或最终长度越界/不一致。
- `media_export_sink_rejected`：sink begin/commit 拒绝，底层 details 脱敏。
- `media_export_read_failed`：source read 失败，底层错误脱敏。
- `media_export_write_failed`：sink write 失败，sink details 脱敏。
- `media_export_cancelled`：caller cancellation 赢得竞态。
- `media_export_timed_out`：120 秒 deadline 赢得竞态。

未知 handle、非法状态、非法参数和 Core close 分别复用 `media_invalid`、`invalid_state`、
`invalid_argument`、`system_interrupted`。Failure message/details 只能为空或包含受限长度，不得包含 handle、
其它 source metadata、路径、sink details、操作系统错误、异常文本或内容摘要。所有 direct export Failure
均不改变 active source lease；export 成功也不自动 `release_media`，不刷新 TTL/grace/tombstone。调用方只有
在后继资源提交成功后才显式 release，从而保留“复制成功但业务提交失败”时的重试来源。

V4 不改变 `open_media_read` 的 callback scope。Native consumer 可以直接提供 typed sink；后续 Bridge
只能从本能力派生受限的一次性 transfer copy，不能把 sink、read scope 或整段媒体 bytes 公开到 Flutter。

## 状态、取消与 Failure

状态按所有权拆成两套独立状态机。Session machine 每次调用独立创建，单个模块同一时刻只
允许一个活动 Session；它从 `idle` 经 `requesting_permission`、`preparing` 进入 `ready`，
拍照或停止录像后进入 `previewing`，最终以 `completed`、`cancelled` 或 `failed` 结束。
`confirm` 结束当前 Session，因此已有媒体租约不会阻止下一次拍摄。

Media machine 每个 opaque handle 独立存在，允许同时持有多个已确认租约。未确认媒体从
`preview` 经 `confirm` 进入 `leased`，或者被重拍、取消和失败清理为 `discarded`；已确认
媒体在主动释放后进入 `release_grace`，在 TTL 到期后进入 `expiry_grace`，两种状态都立即
拒绝新读取；60 秒 grace 结束时强制撤销并关闭残留读取、删除物理文件，再分别进入
`released` 或 `expired`。Session 状态不承担确认后媒体的生命周期，Media 状态也不持有采集
资源。

未确认预览超过 600 秒时，`preview_timed_out` 只由 Session 交付一次 `session_timeout`
Failure；Media 状态伴随清理为 `discarded`，不重复发结果。App 重启会使活动 Session 结束、
未确认 Media 被丢弃、已确认租约过期，但旧进程无法可靠交付 event，因此对应转换的 emission
为 `none`；新进程首次使用旧 handle 时按注册表策略返回 `session_invalid` 或 `media_invalid`。
每一条清理策略都有对应状态转换，不能只删除文件而留下仍可调用的状态。

用户主动取消是正常的 `session_cancelled` 结果与 `cancelled` 状态，不进入 Failure。权限拒绝、
系统中断、资源占用、空间不足、编码失败、句柄失效、不支持能力、并发 Session 和非法状态
使用稳定 Failure ID。系统中断与用户取消不能互相映射；重复或竞态发生的 stop、cancel、
release 和清理必须保持幂等：重复 stop 返回既有预览，重复 cancel 保持同一取消结果，重复
release 在 grace 或 tombstone 内保持同一释放结果，不重新创建或延长任何资源。超出 300 秒
tombstone 识别期限后，Session 与 Media handle 分别稳定返回 `session_invalid` 和
`media_invalid`；`invalid_state` 只用于 handle 仍可识别但操作不适用于当前状态。

## 权限

- Camera 只在用户明确开始拍摄时请求。
- Microphone 与 Camera 分离，只在用户开始带声音录像时按需请求；纯拍照或静音录像不得请求。
- Photo Library 是 V1 非目标，不请求读取、受限选择或写入权限。
- 稳定权限状态为 `not_determined`、`granted`、`denied`、`restricted`、
  `permanently_denied` 和 `unsupported`。Android/iOS 对可重试与必须前往设置的判断差异在
  Capability 的 `platform.differences` 中显式声明，不能虚构平台不存在的区分能力。

## 媒体句柄与所有权

Native Module 在 App 私有临时或缓存沙箱创建物理文件，并在文件整个生命周期内保持唯一
物理所有者。公共结果只返回模块生成的 opaque media handle 和类型、尺寸、时长、方向、
字节数等受限元数据，不返回绝对路径、调用方指定路径或任意 URI。

照片结果的 `duration_millis` 必须显式为 null，视频结果必须提供正时长。两种媒体都必须
提供像素尺寸、方向和字节数；Session 启动结果先报告可用镜头、切换能力、闪光模式、点对焦
支持和 zoom 范围，Native UI 不得靠失败重试探测控制能力。

所有公共字段通过 Contract 的顶层 `field` Profile 维护唯一结构化 validation：录像时长只
允许 1 至 60000 毫秒；焦点坐标必须是有限数且位于 `[0, 1]`；zoom 必须是有限数并落在当前
`session_ready` 快照的边界内，统一采用 reject 而不是 clamp；尺寸与 byte length 必须为正；
方向只允许 0/90/180/270；照片 duration 必须为 null、视频 duration 必须为正；content type
必须是合法 MIME。调用方 request 中的时长、focus、zoom、枚举或 handle 格式违规时返回可
恢复、非终止的 `invalid_argument`，且不改变状态；模块生成的 result/event 若无法满足正
尺寸、MIME、duration 或 orientation 等输出不变量，则属于 `encoding_failed` 或对应内部
terminal Failure，绝不能归因于调用方输入。

确认前，预览文件与句柄由模块逻辑拥有；10 分钟预览 TTL 到期或发生重拍、取消、失败时，
模块立即使其失效并删除。确认后，每个 handle 的 Media machine 独立进入 `leased`，Consumer 获得最长 24 小时
的逻辑租约，物理文件仍由模块持有；Consumer 只能
通过 `open_media_read` 获取回调作用域内的只读访问，并在消费完成后调用 `release_media`。
显式释放或 86400 秒 TTL 到期会立即禁止新读取；已有读取最多保留 60 秒，随后模块必须强制
撤销、关闭并删除文件，不能无限等待不合作的 Consumer。

Session 与 Media handle 都是 module-instance scope、至少 128-bit entropy、最长 128 字符且
永不复用的 opaque registry key。两类 handle 都必须由平台密码学安全随机源生成，不能使用
counter、时间戳或其他可预测输入凑足位数。模块只允许 strict registry lookup；handle 不从路径派生，
不得参与文件路径拼接，也不能用于猜测、遍历或选择沙箱文件。公共 `session_handle` 与
`media_handle` 字段分别由结构化 handle policy 显式绑定，不能靠字段命名推断安全规则。

V1 句柄不跨 App 重启持久化。重启后旧 Session/Media 句柄分别返回 `session_invalid` 与
`media_invalid`，模块在接受新 Session 前尽力清理自己的临时残留。日志不得记录 handle、路径、媒体内容或嵌入元数据；确认前必须
移除位置元数据和设备识别信息，只保留正确展示所需的最小媒体数据与显式结果元数据。

## 平台一致性与允许差异

Android 与 iOS 必须提供相同的操作、状态、结果、取消、Failure、权限和所有权语义。具体
异步类型、回调方式、UI 上下文切换、私有缓存目录选择和权限可重试判断遵循各平台惯例，
由平台 API 显式映射；不得为了表面对称复制另一平台的 SDK 结构。

## 消费者与验证

Customer Support 已接入拍摄/相册入口、图片/视频消息、缩略图和全屏预览；Shoppe 图片搜索复用同一
picker/Store 导入链路。Android/iOS Core 仍只从 Capability Contract 设计类型化 API，Bridge Contract
只能映射既有能力，不能改写状态机、取消、权限或文件所有权。

当前静态门禁验证固定 Schema/实例路径、Schema 完整摘要、版本历史、字段 validation、
result/event/failure emission、双平台语义、禁止的传输/SDK 类型、handle/lease/cleanup、Render
attachment、bounded thumbnail 与 streaming export 安全策略以及索引/详情链接。Base Schema 只提供可复用结构，
不内置 session/media、尺寸、EXIF、poster frame 或租约常量；这些均由 Media Capture Profile 精确
约束。平台文档已经记录纯单测、Framework Fake、Host 编译与 iOS Simulator 证据；Android instrumented/
真机流程和 iOS 真机验证均不宣称通过。Android/iOS Core/Gate 使用大尺寸照片/视频和并发 thumbnail 请求验证
decode-time subsampling、decoded-pixel/working-memory 预算、稳定 overload Failure、完整 cleanup
顺序与 commit 后 caller copy 独立性。双端 V4 Core 已用 50 MiB 边界、复制中增长/截断、并发 job、
never-returning sink、取消、deadline、release/expiry/Core close 竞态证明 bounded buffer、唯一终态和
清理顺序；静态契约仍不能替代真机系统能力证据。
