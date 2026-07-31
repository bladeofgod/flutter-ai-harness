# Flutter 媒体资源与预览基础件

> 决策状态：已批准。实现状态：资源 Store 与 Flutter 通用预览已实现，业务接入待后续任务完成。

[返回基础模块索引](../infrastructure-modules.md)

本文是 Flutter 侧媒体资源所有权和通用预览能力的唯一详细设计事实。它解决图片或视频被
业务消息接纳后仍可展示、打开和播放的问题，但不改变 Native Media Capture Module 对拍摄源
文件的所有权。原生拍摄能力、跨 Runtime Capability 和 Wire 分别以
[`media-capture.md`](./media-capture.md) 和
[`bridge/media-capture.md`](../bridge/media-capture.md) 为准。

## 目标与非目标

`app_media` 为 Flutter 消费者提供两组聚焦能力：

1. 把相册选择器或 Bridge transfer copy 的临时文件导入 App 私有 cache，并用稳定的
   `MediaResourceId` 管理资源、引用和清理。
2. 按 `MediaResourceId` 构建无业务含义的图片/视频缩略图、解码探测和全屏预览。

V1 不提供上传、远程 URL、后台下载、相册保存、编辑、转码、跨 App 重启的消息持久化或后台
音视频播放。它也不把 Native `mediaHandle`、Bridge `exportHandle`、文件路径、URI 或播放器
Controller 写入消息。

## 包层级与依赖

`app_media` 是一个聚焦的 Flutter 基础设施 Package，初始在单包内使用 `resource/` 和
`preview/` 两个内部区域。只有出现独立发布、不同平台支持或真实依赖冲突时才重新评估拆包。

```text
app_media -> app_core, app_ui
app_features -> app_media
apps/demo -> app_media
```

- `app_core` 只增加传输中立的 `MediaResourceId` Value Object。
- `app_ui` 继续只拥有 Token 和无业务视觉原语，不拥有文件、播放器或资源生命周期。
- `app_data` 可以在 Domain Entity 中使用 `app_core` 的 `MediaResourceId`，但不得依赖
  `app_media`。
- `app_media` 不得依赖 `app_data`、`app_features`、`app_media_capture_bridge` 或 `apps/demo`。
- `app_features` 负责把业务消息、选择器、Bridge Client 和 `app_media` 编排在一起；
  `app_media` 不认识 Support、Order、Search 或 Route 规则。

`MediaResourceId` 是 `app_core` 唯一批准的聚焦基础设施 ID 例外。它只校验 `mr_` 加 32 个
小写十六进制字符的闭合格式，总熵至少 128 bit；生产 ID 由 `app_media` 使用 CSPRNG 创建，碰撞时
重新生成，且在进程内永不复用。ID 不从路径、文件名、消息 ID、Native handle 或时间戳派生，
不携带路径和文件语义。Store、Resolver、metadata、引用 API 与预览 API 均不得继续下沉
`app_core`。

## 公共模型

资源基础件当前由 `app/packages/app_media/lib/app_media.dart` 导出，生产环境通过
`createMediaResourceStore()` 创建进程级 Store。`MediaResourceId` 由
`app/packages/app_core/lib/value/media_resource_id.dart` 提供；文件系统、随机源、时钟和图片
canonicalizer 是包内实现依赖，不进入业务模型。

公共 API 使用有类型模型，不返回裸 Map、`dynamic`、平台 SDK 对象或底层异常：

| 模型 | 语义 | 不允许包含 |
| --- | --- | --- |
| `MediaResourceId` | 消息可保存的 opaque 逻辑标识 | 路径、URI、handle、业务 ID、文件语义 |
| `MediaImportRequest` | 调用范围内的 `file:` 源、媒体种类、声明 content type/长度和可选时长 | 调用方目标路径、远程 URL、任意 bytes |
| `OwnedMediaResource` | import 成功后的 ID、种类、canonical content type、实际长度、可选时长和初始 lease | 可长期保存的 locator、播放器对象 |
| `MediaResourceLease` | Store 发放给一个具体 owner 的逻辑引用，重复关闭幂等 | 消息序列化、日志、Route、Fixture |
| `ResolvedMediaResource` | 一个 active lease 范围内借用的 App 私有 file URI 和已验证 metadata | 业务 Entity、日志、错误 details、长期缓存 |
| `MediaResourceFailure` | 闭合、脱敏的导入、解析、解码和生命周期失败 | 原始异常、源文件名、路径、URI、Resource ID |

Store 公共操作采用以下语义：

```text
importFile(request) -> OwnedMediaResource(initialLease)
retain(resourceId) -> MediaResourceLease
resolve(resourceId, activeLease) -> ResolvedMediaResource
release(lease) -> idempotent completion
dispose() -> idempotent completion
```

`retain` 返回独立 lease，而不是只增加一个无法识别 owner 的裸计数。每个 owner 只释放自己持有的
lease，因此同一 owner 重复释放不会误减其它 owner 的引用。`resolve` 不隐式创建新引用；调用者必须
先持有与 ID 匹配的 active lease。`ResolvedMediaResource` 只在该 lease 和 Store 都 active 时有效，
调用者只读且不得重命名、覆盖或删除文件。

所有公共模型的 `toString` 必须脱敏。Resource ID 即使不含路径，也不得进入日志、FlutterError、
Snackbar、Semantics、analytics 或服务端 payload；业务 Fixture 只在确需 Domain round-trip 时保存
通过 Value Object 校验的 ID 字符串。

## Store 导入边界

### 输入与 canonical 输出

Store 只接受当前 App 可读取的本地 `file:` URI。相册 `XFile.path` 和 Bridge transfer `fileUri`
都只是本次 import 的临时输入，不能成为资源标识。Store 使用官方平台 API 获取 App cache 根，在其下
维护固定私有目录；它拒绝非 `file:` scheme、非空 host、query/fragment、相对路径、`.`/`..`、
符号链接、canonical root 越界和导入期间被增长、截断或替换的源。

V1 媒体闭合集合：

| 种类 | 可接受输入 | canonical 输出 | 上限 |
| --- | --- | --- | --- |
| 图片 | 能由 Flutter 平台 codec 真实解码的本地图片 | `image/jpeg`；需要透明通道时为 `image/png` | 20 MiB |
| 视频 | ISO BMFF 容器检查通过的 MP4/MOV，content type 为 `video/mp4` 或 `video/quicktime` | 不转码，保持已验证容器 | 50 MiB |

图片必须重新编码，并移除 EXIF、位置、设备、原始文件名和其它非展示 metadata；扩展名或 picker
声明不能替代真实解码。平台 codec 无法解码的 HEIC、WebP 或其它输入返回
`unsupported_media`。视频 Foundation 只验证声明/实际长度、content type 与容器签名，不把容器通过
等同于可播放；业务接纳前由 Preview 层执行真实平台 decoder probe。

目标文件名只由新建的 CSPRNG Resource ID 与闭合扩展生成。Store 先写同目录 staging 文件，完整复制
或重编码后执行长度与内容复核，再 flush/close 并原子 rename commit。只有 commit 线性化点成功后才
创建 Registry entry 和初始 lease。失败、取消、Store dispose 或晚到 completion 必须关闭句柄、删除
staging/canonical partial file，并且不交付 ID。

### 资源状态

```text
absent
  -> staging
  -> active(reference leases >= 1)
  -> deleting(last lease released or Store disposed)
  -> released(tombstone)

staging
  -> failed/cancelled -> absent
```

- `active` 是唯一允许 retain/resolve 的状态。
- 最后一个 lease 释放后，Registry 先原子拒绝新 retain/resolve，再删除物理文件并写入短期
  tombstone；删除重试不能让资源重新变为 active。
- 每个 lease 的 release exactly once；重复 release 同一 lease 幂等。未知、失效或与 ID 不匹配的
  lease 稳定失败，不能影响其它引用。
- import、retain、resolve、release 与 dispose 在一个 Store coordinator 上线性化。晚到操作只能完成
  自身清理，不能复活已释放资源或第二次交付结果。
- Store 为 App 进程级、非持久 Registry。初始化时清理自身目录中上次进程遗留的 staging 和未登记
  文件；不得扫描或删除该根目录外的文件。
- `dispose` 先拒绝新操作，再取消或等待在途 import，失效全部 lease，删除 active/staging 文件，最后
  关闭 Registry；重复 dispose 返回同一完成语义。

删除失败属于基础设施清理失败：资源保持不可解析并进入 bounded retry，不向消息重新暴露 locator。
V1 不承诺进程被系统强杀时同步删除，但下一次 Store 初始化必须收敛清理。

## 消息所有权

消息只保存逻辑引用和轻量 metadata：

```text
SupportMediaContent
  - MediaResourceId resourceId
  - mediaType
  - displayLabel
  - optional duration
  - optional bounded sanitized poster
```

消息不得保存 `MediaResourceLease`、file URI、绝对路径、Native `mediaHandle`、Bridge
`exportHandle` 或播放器 Controller。`MediaResourceId` 跟随消息，物理文件和 lease 则由
App-scoped Store 与会话资源协调器管理。

发送采用以下所有权顺序：

```text
picker/capture owner imports resource and receives initial lease
  -> Support API retains one candidate session lease
  -> API writes and accepts message                 [linearization point]
  -> success: session owns candidate lease
  -> failure: API releases candidate lease
  -> caller releases its initial lease in either outcome
```

消息写入成功后，即使 Controller 已 dispose、generation 已变化或结果晚到，API/会话协调器也必须保留
消息的 session lease；Controller 只能释放自己的初始 lease，不能回滚已接纳消息。消息写入失败时，
协调器先释放 candidate lease，调用方再释放 initial lease。一个消息对象被 Mapper 或 UI 复制不会重复
retain；会话协调器以当前已接纳消息集合拥有引用。

Page/Route dispose 只关闭 Thumbnail/Viewer 等临时 lease，不删除已发送消息资源。Demo V1 的
`FeaturesRegistry` 持有 Store 和会话协调器：

1. `startConversation` 成功替换旧会话时，先发布不再引用旧媒体的新状态。
2. 卸载旧 Thumbnail/Viewer 并等待它们释放临时 lease。
3. 释放旧会话的全部 session lease。

消息删除和 Registry dispose 使用同一顺序。Registry dispose 还必须先关闭 picker/Bridge client 与
active Viewer，再释放会话 lease，最后 dispose 自己创建的 Store；外部注入的 Store 只解除引用，
不得越权 dispose。

V1 消息与 Resource ID 不跨 App 重启保留。未来如果消息需要持久化或上传，必须建立持久媒体仓库、
迁移和远端 locator 解析任务；不得把当前 cache ID 当作永久地址。

## Native Media Capture 所有权转移

Native confirmed media 的物理文件始终先归 Media Capture Module。`mediaHandle` 代表 Consumer 对该
文件的临时 lease：active lease 期间可以执行 Capability 允许的读取；`release_media` 表示 Consumer
已经完成使用，Module 立即拒绝新读取，并在有界 grace 后撤销残留读取和删除文件。

因此不能在读取 thumbnail 后立即释放 Native lease。Flutter Consumer 使用后续 Capability/Wire 的
受控导出建立一次性 transfer copy，再导入 Store：

```text
confirmed native lease
  -> optional sanitized poster
  -> materialize bounded transfer copy
  -> import and commit app_media resource
  -> release transfer copy
  -> release original native lease
  -> attach MediaResourceId to candidate message
```

Capability 使用有界 sink 流式复制，不把完整视频载入内存；Bridge Adapter 自己选择 App 私有 transfer
根和随机目标，Flutter 不能提供目标路径。Wire 只在一次调用范围内交付短 TTL `file:` URI 和 opaque
export handle。该 locator 属于敏感本地信息，只能由 `app_media` 立即消费，不得进入消息、Fixture、
Route、事件、日志、错误 details 或持久化。

Store commit 是跨所有者转移的关键点：

- commit 前失败或取消：按相反顺序释放已经创建的 transfer，再释放原 Native lease；不创建消息。
- commit 成功：App resource 已独立拥有自己的物理文件，此后 transfer/source 清理失败不能删除或
  使消息资源失效；清理进入 bounded retry/retained cleanup。
- transfer materialize 成功但 import 失败：先 release transfer，再 release Native lease。
- caller/Engine/Route dispose 与 import 竞态：线性化前取消则不交付资源；若 commit 已先获胜，晚到
  completion 必须取得并立即释放 initial lease，清理 canonical 文件后再丢弃结果。
- Native lease 只有在 Store commit 后才能主动释放；Capability export 成功本身不自动延长或释放
  source lease。

通用 Media Capture 仍允许最长 60 秒录像；Customer Support V1 的 consumer config 固定为 15 秒。
Store 和 transfer 对视频都执行实际 50 MiB 硬上限，超过时返回 `too_large`，不截断或静默降质。

## 缩略图、探测与全屏预览

`app_media` 对 Feature 公开按 `MediaResourceId` 工作的业务无关能力：

| 能力 | 职责 | 生命周期 |
| --- | --- | --- |
| `MediaResourceThumbnail` | 以稳定尺寸展示 canonical 图片或 sanitized video poster | mount 时 retain，unmount/late completion 时 release |
| `MediaPlaybackProbe` | 用真实平台 decoder 初始化视频并读取实际时长 | 单次 retain，完成/失败/取消后 release |
| `MediaPosterService` | 从可播放视频生成有界净化 poster | 每 job retain，最多 2 个并发、10 秒 deadline |
| `MediaPreviewPage` | 全屏图片缩放或视频播放 | route 可见期间 retain，关闭/dispose 后 release |

图片 Viewer 使用真实 canonical 文件解码、适配屏幕并支持双指缩放和平移。视频 Viewer 使用经过
验证的公开 Flutter 播放库，初始暂停，支持播放/暂停、进度拖动、当前/总时长和结束重播；Route
不可见或 App 进入 inactive/paused/detached 时立即暂停，resumed 不自动续播。全屏同时最多一个
active video player，打开新实例前先 dispose 旧实例。

视频缩略图不常驻播放器且不自动播放。Poster 输出仅允许 JPEG/PNG、最长 524,288 bytes、最大边
512 px；poster 缺失时显示明确的视频占位和播放含义，点击仍可进入 Viewer 做真实 probe。图片或
视频 loading、missing、invalid、decode/playback failure 必须保持稳定布局并展示明确错误状态，不能
用永久黑框冒充有效预览。

每个 Thumbnail、Probe、Poster job 和 Viewer 都独立 retain/release，不能消费消息的 session lease。
异步初始化、解码、seek、poster 或 resolve 在 Widget dispose 后晚到时，只执行资源与 Controller
清理，不更新 UI。预览组件不声明 Support 文案、业务 Route 或消息发送规则。

## 失败与取消语义

Flutter 层至少使用以下稳定失败类别；底层异常只能映射，不能透传：

| Failure | 含义 |
| --- | --- |
| `invalid_argument` | ID、类型、URI 或 metadata 不符合闭合输入 |
| `unsupported_media` | 图片无法 canonical decode，或视频类型/容器/decoder 不支持 |
| `too_large` | 声明或实际媒体超过 20/50 MiB 上限 |
| `import_failed` | 受控复制、重编码或 atomic commit 失败 |
| `missing` | ID 不在 active Registry 或物理资源已失效 |
| `invalid` | Registry metadata、root、长度或 content type 漂移 |
| `decode_failed` | canonical 图片或 poster 解码失败 |
| `playback_failed` | 视频播放器初始化或运行失败 |
| `overloaded` | 预览基础件达到固定并发或排队容量，调用方可稍后重试 |
| `cancelled` | caller、Widget、deadline 或 Store dispose 先赢得取消 |
| `store_closed` | Store 已开始或完成 dispose，拒绝新操作 |

失败对象只包含稳定 code、recoverable/terminal 属性和静态脱敏文案。资源 ID、locator、文件名、
媒体内容、底层播放器/文件系统错误、堆栈和平台对象均不得进入错误、日志或 UI 文案。

## 消费者与装配

当前真实消费者是 Customer Support 的图片/视频消息，订单评价附件预览是第二个已存在的复用场景。
Gallery 与 Camera 都必须先导入同一 Store，业务消息不区分资源原始来源。

`apps/demo` 在进程级装配一个 Store，并将同一实例通过 `FeaturesRegistry` 构造函数注入需要的 picker、
会话协调器、Thumbnail 和 Viewer。Feature 不使用服务定位器查找 Store，也不创建彼此独立且无法统一
清理的默认实例。

## 验证边界

基础件实现必须覆盖：

1. Store import、canonicalization、root/symlink/traversal 防护、原子 commit、文件漂移和启动清理。
2. lease retain/release、重复 close、最后引用删除、late result、会话 reset 和 App dispose。
3. 图片真实解码、视频 decoder probe、poster 预算、播放器生命周期、Safe Area 和错误状态。
4. Gallery 与 Native transfer 的成功、取消、失败、超限和 cleanup 顺序。
5. 依赖门禁持续拒绝 `app_data -> app_media`、`app_media -> app_features` 与
   `app_media -> app_media_capture_bridge`。

纯 Dart/Widget Fake 不能证明 Android/iOS 平台 codec、视频首帧、音视频同步或 Bridge 私有 cache
边界。真实平台结论必须由对应 Host build、平台测试和设备证据给出；证据不得记录真实媒体、设备 ID、
Resource ID 或文件 locator。
