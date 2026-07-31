---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy:
  - media-capture-thumbnail-capability-evolution
securityReview: required
---

# 演进 Media Capture 全屏 Native UI Flow Wire

## 输入与事实来源

- 最新 `media-capture-thumbnail-capability-evolution` 归档产物。
- `docs/bridge/contracts/wire.schema.json`、`docs/bridge/contracts/media-capture.wire.json`。
- `docs/bridge/media-capture.md`、`docs/infrastructure/media-capture.md`。
- 用户批准的 V1 交互：点击拍照、长按录像、滑动缩放、切换镜头、闪光、点按对焦、预览、
  重拍、确认、取消；全屏原生呈现，不复制微信品牌/像素样式。
- 已确认缺口：Wire V1 只有 Capability operation 的逐项调用，没有由 Adapter 呈现全屏 Native UI、
  编排操作并向 Flutter 返回单一终态的协议。
- 最新 Capability 同时包含只供 Native UI 消费的 live preview attachment 与 unconfirmed preview
  render scope；它们不可编码或跨 Channel。

## 目标

- 定义 transport-specific 的 Native UI flow presentation/orchestration Wire，不把 UI、手势或页面
  生命周期塞进 Native Core Capability。
- 从最新 Capability 派生安全缩略图 Wire 映射，并为 Flutter 提供可显示的有界净化 bytes。
- 固定 Android/iOS 的全屏 present、confirmed/cancelled/failure、UI owner 生命周期和 exactly-once
  行为，供 Dart Client 与两端 Adapter 独立实现。

## 非目标

- 不新增 Camera Core operation、状态或文件所有权，不把 `present` 定义成 Capability operation。
- 不把 RenderTarget Adapter、owner generation、live/unconfirmed preview attach/detach/revoke 暴露给
  Flutter；Adapter 只 present 已经在 Native 侧消费这些能力的 UI。
- 不实现 Dart Client、Adapter、Native UI、Host 注册、权限配置或 Shoppe 页面。
- 不通过 Channel 传输原始媒体、路径、URI、文件描述符、Proto 或平台 SDK 对象。
- 不规定微信品牌资源、逐像素布局、动画常量或 Compose/SwiftUI 选型。

## 实现路径与所有权

本任务独占以下共享 Wire 写入：

- `docs/bridge/contracts/wire.schema.json`
- `docs/bridge/contracts/media-capture.wire.json`
- `docs/bridge/media-capture.md`
- `docs/bridge/README.md`（仅索引/版本说明）
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`

不得修改 Capability Contract、`app/native/**`、`app/packages/app_media_capture_bridge/**`、Host、
Shoppe Feature、CI 或 Makefile。发现 Capability 缺口必须停止并回到独立 Capability evolution，
不得在 Wire 中伪造。

## 契约要求

1. 提升 `wireVersion` 并声明与最新 `capabilityVersion` 的兼容关系；保留 V1 兼容/变更记录。
2. 扩展通用 Wire Schema，以结构化方式区分“直接映射一个 Capability operation 的 method”和
   “由平台 Adapter/Native UI 编排一组既有 Capability operations 的 presentation method”。Base
   结构不得写死 Media Capture、Activity/ViewController 或全屏常量。
3. 新增稳定的 `present_capture_flow` 语义：Flutter 只提交闭合的拍摄配置，Adapter 从当前 attached
   UI owner 全屏 present Native UI。一个 UI owner 同时只允许一个 flow；缺少/销毁 owner、Engine
   detach、重复 present 和并发 session 都有稳定、脱敏、恰好一次的完成行为。
4. Flow 只能编排最新 Capability 已声明的 start/capture/control/preview/retake/confirm/cancel/failure，
   不拥有资源。终态必须闭合且互斥：confirmed 返回 confirmed media metadata/lease；用户取消返回
   正常 cancelled 结果；Capability/system/presentation failure 以稳定 error/failure 完成。任何路径
   只能完成 Flutter 一次，late result 必须先清理 Session/lease 再丢弃。
5. 定义 full-screen presentation 与 dismiss 顺序、Android Activity / iOS presenting ViewController
   owner generation、配置变化/旋转、后台/前台、Engine detach 和 UI owner destroy；不得把系统销毁
   伪装成用户取消，也不得在旧 owner 上重新 attach flow。
6. Wire coverage 必须逐项列出 Capability 的 live preview attach/detach/revoke、unconfirmed preview
   render attach/detach/revoke 及其 result/event/resource，全部标为 `native_consumer_only` 或等价闭合
   disposition，`wireId: null` 且有不可编码 RenderTarget scope 的稳定原因。Harness 必须拒绝将它们
   加入 method/event/payload/field mapping，或通过 bytes/path/URI/SDK 对象间接跨 Channel。
7. 映射最新 `read_media_thumbnail` Capability operation。缩略图 bytes 只允许 `Uint8List`/等价
   Channel byte 类型，保留 Capability 的尺寸、字节、content type、EXIF 净化和 active lease 上限；
   Wire 固定映射 upright `image/jpeg`、`orientationDegrees: 0`、照片 null/video 实际
   `posterFrameMillis` 与 byte-length equality，不得扩大上限、回传原图或增加路径 fallback。
8. 更新 Payload、error details、coverage、resource adoption、late result、data classification、日志
   redaction 和双平台 support matrix。Flow confirmed lease 必须在 Flutter completion 前登记；取消/
   failure 不得遗留 Session、preview 或未交付 lease。
9. Harness 负例必须覆盖：把 present 当 Core operation、把 Native Preview scope 暴露到 Channel、遗漏
   native-only coverage、缺少三终态、双重完成、owner 销毁后成功、未清理晚到 lease、缩略图超限/
   poster/orientation/content type/EXIF 错误或路径 fallback、双平台语义缺失和版本兼容错误。

## 测试与验收

- 最新 Wire Schema/Profile 和 Capability coverage 确定性通过。
- Contract 能让 Dart Client、Android Adapter、iOS Adapter 分别确定实现，无需另行决定 terminal、
  owner、缩略图或错误语义。
- Core 实现不需要读取本 Wire；Native UI 调用 Core 类型化 API，Adapter 只负责 presentation 与映射。
- 文档明确全屏 Native UI 是 Adapter/UI 编排，不是基础能力状态机的一部分。

## 验证命令

```bash
make harness-check
make harness-test
make format
git diff --check
```

## 环境限制

本任务只设计 Wire/Harness，不需要 SDK、Xcode、设备、Figma 或运行 Flutter。静态 Contract 不证明
Activity/ViewController 实际可 present；运行证据由两端 Adapter/UI 和最终集成任务产生。
