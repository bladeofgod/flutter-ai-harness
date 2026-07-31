---
executor: task-executor
platforms: [android, ios]
workKinds: [capability-contract]
blockedBy:
  - native-harness-bootstrap-gate
securityReview: required
---

# 演进 Media Capture Native Preview 与 Flutter 缩略图 Capability

## 输入与事实来源

- `CLAUDE.md`、`docs/native-architecture.md`。
- `docs/native/contracts/capability.schema.json`。
- `docs/infrastructure/contracts/media-capture.capability.json`。
- `docs/infrastructure/media-capture.md` 与现有 Capability Review/Security Review。
- 已确认缺口 A：Capability V1 没有定义 Native UI 可消费的 live preview attachment 或确认前 preview
  render scope；平台 UI 不能自行持有 CameraX/AVFoundation session 来补协议。
- 已确认缺口 B：Capability V1 的 `open_media_read` 只提供 Native callback-scoped 原始媒体读取，Wire V1
  不能向 Flutter 暴露该访问；Shoppe 因而无法显示真实拍摄缩略图。

## 目标

- 先在传输中立 Capability 中增加 Native UI 所需的 live preview attachment、确认前 preview render
  scope，以及“从已确认媒体租约生成受限、已净化缩略图”的稳定语义，再允许 Wire 派生。
- 为 Android/iOS Core 提供相同的输入边界、结果上限、隐私清理、租约和失败语义。
- 让平台 UI 只消费 Core 暴露的 `RenderTarget Adapter` 抽象，不直接控制平台 Camera session。
- 保留 Native Consumer 的 callback-scoped 原始媒体读取，不把缩略图能力等同于原图导出。

## 非目标

- 不定义 Channel method、Wire key、`Uint8List`、Native UI presentation 或 Shoppe 页面。
- 不定义 CameraX `PreviewView`/Surface、AVFoundation layer/session 或具体 View 类型；这些只由平台
  `RenderTarget Adapter` 实现留在 Core 的平台内部边界。
- 不允许 Flutter 读取原始照片/视频、路径、URI、文件描述符或任意分块流。
- 不实现 Android/iOS 编解码、缩略图缓存、上传、相册保存或持久化。
- 不改变确认媒体的 24 小时租约、60 秒 read grace、opaque handle 或清理所有权。

## 实现路径与所有权

本任务独占以下共享契约写入，后续实现任务在本卡归档前不得开始：

- `docs/native/contracts/capability.schema.json`
- `docs/infrastructure/contracts/media-capture.capability.json`
- `docs/infrastructure/media-capture.md`
- `docs/infrastructure-modules.md`（仅在版本/状态索引确需同步时）
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`

不得创建或修改 `app/native/**`、`app/packages/app_media_capture_bridge/**`、Host、Wire Contract、
Shoppe Feature、CI 或 Makefile。

## 契约要求

1. 提升 `capabilityVersion`，保留 V1 变更历史和兼容说明；Schema 的新增结构必须保持通用，不把
   Media Capture 专属尺寸、EXIF 或租约常量写死在 Base Schema。
2. 以机器可校验的 operation、result/event、state/resource/cleanup 条目定义 Native-only live preview：
   - `attach_live_preview` 把一个平台 `RenderTarget Adapter` 绑定到已 ready/recording Session 与明确的
     `owner_generation`；每个 Session 同时只允许一个 attachment，同 generation 重复 attach 幂等，
     不同 generation 必须先撤销旧 attachment。
   - `detach_live_preview` 可重复调用；rotation、后台、owner destroy、Session terminal、Core close 和
     App restart 都必须触发 revoke/detach，旧 generation callback 不得重新 attach 或渲染。
   - 前台恢复使用新 owner generation 显式重新 attach，不由 Core 暗中持有已销毁 UI owner。
3. 以独立机器条目定义 unconfirmed preview render scope：`attach_unconfirmed_preview_render` 只允许
   Media `preview` 状态，把同一 `RenderTarget Adapter` 抽象绑定到 media handle/owner generation；
   每个 preview 同时只允许一个 attachment。`detach_unconfirmed_preview_render` 幂等，retake、cancel、
   confirm、failure、preview timeout、后台、owner destroy、restart 都先 revoke scope 再清理/转移媒体。
4. 两类 Render attachment 都是 Native Consumer callback/resource scope，不返回媒体 bytes、path、URI、
   文件描述符或 CameraX/AVFoundation/session/View 对象。Contract 必须固定 attach/detach/revoke 顺序、
   owner generation、single attach、callback/thread 约束和 cleanup-before-terminal；平台可用不同 Target
   类型实现 Adapter，但公共语义一致。
5. 新增稳定的 `read_media_thumbnail` operation。它只在对应 Media handle 处于已确认且 lease
   active 的 `leased` 状态可调用；release/expiry grace、preview、discarded、released、expired
   都拒绝新请求，且读取不得刷新 lease、TTL、grace 或 tombstone。
6. 请求只接受 opaque `media_handle` 和结构化缩略图边界。V1 演进快照采用 `max_pixel_edge`
   `64..512`；非法类型、非有限值、越界或未知 handle 分别复用稳定的 `invalid_argument`、
   `media_invalid`、`invalid_state` 语义，不进入平台自定义 clamp 分支。
7. 结果是一次调用范围内的 caller-owned bounded copy，而不是原始媒体句柄。结果最多
   `524288` bytes，像素宽高均为正且不超过请求的 `max_pixel_edge` 和全局 512 上限，声明实际
   `byte_length`、`content_type`、方向归一后的宽高、`orientation_degrees: 0`、来源媒体类型和
   `poster_frame_millis`；`byte_length` 必须等于实际 copy 长度。
8. 缩略图输出 content type 闭合为 `image/jpeg`。照片按显示方向物理旋转为 upright pixels；视频 poster
   target 固定为 `min(1000, floor(duration_millis / 2))` 毫秒，选择 target 时刻或其后的最近可解码帧，
   若不存在则选择 target 前最近帧，距离相同选择更早帧，并返回实际 `poster_frame_millis`；照片该字段
   为 null。两端不得自行选择首帧/中间帧或保留非零 orientation。
9. 缩略图内容必须重新编码或等价净化，移除 EXIF、位置、设备、原始文件名和其它非展示元数据；
   不得返回原始文件 bytes、路径、URI、任意 Map 或平台 SDK 类型，也不得在日志、错误 details 或
   缓存 key 中记录媒体内容/handle。
10. 缩略图生成失败复用或新增明确的稳定 Failure，但不得泄漏底层解码异常；取消、release、TTL、
   App restart 与正在生成缩略图的竞态必须定义唯一结果和清理顺序。
11. 新 operation/result/event/field/state transition/resource/privacy 条目全部进入确定性 Validator；
   Harness 必须拒绝缺少 owner generation/single attach/revoke/thread/cleanup、把 RenderTarget 变成 SDK
   对象或 bytes/path/URI、遗漏 thumbnail 上限/poster policy/orientation/content type、允许 preview
   thumbnail、租约延长、EXIF 未清理或双平台语义不一致。

## 测试与验收

- JSON Schema/Profile 正例通过；缺少 Native Preview attachment/render scope、owner generation、
  single attach、detach/revoke、线程/cleanup、thumbnail 字段边界、结果上限、poster policy、方向归一、
  content type、隐私策略或租约状态限制时失败。
- 负例证明两类 preview 都是 `native_consumer_only` RenderTarget Adapter scope，以及 512px、512KiB、
  confirmed lease、固定 video poster、upright JPEG、EXIF 清理、无路径/URI/原图和不延长 lease。
- Android/iOS Core 可只读最新 Capability 设计类型化 API；任何 Wire 任务无需猜测缩略图语义。
- Android/iOS Native UI 可只通过 Core RenderTarget Adapter API 实现 live/确认前预览，不持有平台
  Camera session；文档明确 Flutter 原始媒体读取仍被禁止，只新增受限净化的缩略图 copy。

## 验证命令

```bash
make harness-check
make harness-test
make format
git diff --check
```

## 环境限制

本任务只演进契约与 Harness，不需要 Android SDK、Xcode、设备、Figma 或真实媒体。静态 Fixture
不能证明平台缩略图编码正确；两端实现和真实媒体验证由后续 Core/Gate 任务负责。
