---
executor: task-executor
platforms: []
workKinds: [documentation, planning]
blockedBy: []
---

# 设计 Flutter 媒体资源与预览基础件架构

## 输入与事实来源

- 用户批准：建立 Flutter 媒体资源基础件，统一预览图片和视频；媒体资源生命周期跟随消息，消息不保存
  原始绝对路径。
- 当前 Customer Support 的 `SupportMediaContent` 只有可选缩略图，没有可解析资源引用；媒体气泡没有
  点击预览行为，视频播放图标只是静态装饰。
- 当前 `NativeSupportMediaPicker` 在读取缩略图后立即释放 Native confirmed media lease，导致消息发送后
  不再具备读取原图或视频的来源。
- `docs/architecture.md`、`docs/infrastructure-modules.md`、`docs/native-architecture.md`、现有 Media
  Capture Capability V3 / Wire V2。
- `app_ui` 只负责设计 Token 和无业务 UI 原语，不负责文件、播放器、缓存或资源生命周期。

## 目标

- 固定 `app_media` 的包层级、公共模型、资源存储、解析、引用计数和图片/视频预览职责。
- 固定消息、资源仓库、平台选择器、Media Capture lease 与预览组件之间的所有权转移顺序。
- 为后续 Capability、Wire、双端 Adapter、Flutter 基础件和 Customer Support 接入任务提供唯一设计事实。

## 非目标

- 不创建 Package，不引入依赖，不修改 Dart/Kotlin/Swift 生产代码。
- 不实现上传、云端 URL、相册保存、编辑、转码、跨 App 重启的消息持久化或后台下载。
- 不把 Support 业务模型、Media Capture handle 或平台路径下沉到 `app_ui`。
- 不把 App Operator、UI Spec 或真机运行列为本设计任务的门禁。

## 设计结论

### 包和依赖

1. 新增聚焦的 Flutter Package `app_media`，初始包含 `resource/` 与 `preview/` 两个内部区域，不为了形式
   完整提前拆成多个 Package。
2. `app_media` 位于 `app_ui`/`app_core` 之上、`app_features` 之下：

   ```text
   app_media -> app_core, app_ui
   app_features -> app_media
   apps/demo -> app_media
   ```

   `app_data` 继续只依赖 `app_core`，不得依赖包含 Flutter UI、播放器和文件实现的 `app_media`。
3. 传输中立且需要同时出现在 `app_data` Domain Entity 与 `app_media` API 的 `MediaResourceId` 放入
   `app_core`。这是一个显式、唯一的聚焦基础设施例外：只有已经存在于两个包边界、传输中立且不含
   行为的 opaque ID 才满足准入条件。它只负责格式校验，不包含路径、URI、媒体 handle、文件语义或
   业务规则；Store、Resolver、媒体 metadata/API 不得继续下沉到 `app_core`，也不能借此建立中央契约包。
4. `app_media` 可以使用 `app_ui` Token 构建无业务全屏预览和缩略图；它不得依赖 `app_data`、
   `app_features`、`app_media_capture_bridge` 或 `apps/demo`。

### 资源模型和生命周期

1. `MediaResourceId` 至少使用 128-bit CSPRNG 生成，字符串闭合校验、进程内不复用；不得从文件名、
   路径、消息 ID 或 Native handle 派生。
2. `MediaResourceStore` 负责把受信范围外的临时文件复制到 App 私有 cache，使用随机目标名、staging
   文件、原子 commit 和失败清理。V1 的 canonical image 为 `image/jpeg` 或 `image/png`：Gallery 输入
   只要能被 Flutter 平台 codec 解码，就重新编码为上述闭合集合并移除源 metadata；无法解码的 HEIC、
   WebP 或其它格式明确返回 `unsupported_media`，不得按扩展名放行。视频不在 V1 转码，只接受通过
   ISO BMFF 容器检查且 content type 为 `video/mp4` 或 `video/quicktime` 的 MP4/MOV，并在进入消息前
   由 Preview 层做真实平台 decoder probe。canonical 图片最大 20 MiB、视频最大 50 MiB。
3. import 成功返回包含 `MediaResourceId`、类型、content type、实际长度、可选时长和可选净化 poster 的
   `OwnedMediaResource`。调用方持有一个逻辑引用；`retain/release` 采用明确引用计数，最后一个引用释放后
   删除文件并使后续 resolve 稳定失败。重复 release、dispose、晚到 import 和删除失败必须有确定语义。
4. `resolve(MediaResourceId)` 只在基础设施/预览层返回短生命周期的 `ResolvedMediaResource` 和 App 私有
   file URI。绝对路径或 URI 不得进入消息 Entity、Fixture、Route 参数、日志、错误 details、Semantics、
   analytics 或服务端 payload。
5. V1 Store 为 App 进程级、非持久资源；启动时清理上次进程遗留的 staging/未登记 cache，Registry
   dispose 清理全部资源。未来若消息跨重启保留，必须另建持久化或上传任务，不允许让当前本地 ID
   假装成永久媒体地址。

### 消息所有权

1. `SupportMediaContent` 增加 `MediaResourceId`，并继续携带媒体类型、展示名、可选时长和 bounded poster
   等轻量消息元数据；它不得携带路径、URI、Media Capture handle 或播放器 Controller。
2. 选择或拍摄成功后先导入 `MediaResourceStore`，再创建消息。调用方先持有 import 的初始引用；
   Support API/会话协调器在写入消息前为候选会话 retain 一个独立引用，消息写入成功是所有权线性化点。
   成功后即使 Controller 随后 late/dispose，会话引用也继续有效，调用方只释放自己的初始引用；写入
   失败则协调器释放候选引用，调用方再清理初始引用。
3. Route/Page dispose 只关闭正在预览的 Controller，不删除已发送消息资源。Demo V1 由 app-scoped
   `FeaturesRegistry`/会话资源协调器持有；`startConversation` 成功替换旧会话视为 reset，先发布不再引用
   旧媒体的新状态并卸载 Thumbnail/Viewer，再释放旧会话引用。消息删除和 Registry dispose 同理。
4. 媒体气泡通过 `MediaResourceId` 请求 `app_media` 的缩略图/预览。poster 缺失时，图片从真实资源解码，
   视频初始化真实数据源并停在可解码帧；加载失败显示明确错误状态，不以永久黑框冒充预览。

### Media Capture 所有权转移

1. confirmed media 仍先由 Native Media Capture Module 保存并以 `mediaHandle` 提供 consumer lease。
2. Flutter Consumer 通过后续 Capability/Wire 的受控导出能力取得一次性、App 私有、短 TTL transfer
   copy；大文件只在本机文件系统流式复制，不通过 MethodChannel 传输原始 bytes。
3. Wire 可以把平台生成的临时 `file:` URI 交给 Dart 基础设施，但该 URI 只用于立即导入
   `app_media`，不得成为业务 API/消息字段。Adapter 不接受 Flutter 提供的任意目标路径。
4. 通用 Capability 仍允许最长 60 秒录像，但 Customer Support Demo V1 的 consumer config 固定为 15 秒；
   export/Store 仍以实际 50 MiB为硬上限并向用户返回明确 `too_large`，不把过大文件截断或静默降质。
5. 固定清理顺序：

   ```text
   confirmed native lease
     -> optional sanitized poster
     -> materialize transfer copy
     -> import app_media resource
     -> release transfer copy
     -> release original native lease
     -> attach MediaResourceId to message
   ```

   任一步失败都先清理已经创建的后继资源，再释放原始 lease；只有 `app_media` commit 成功后才能释放
   Native lease，不能再沿用“读取缩略图后立即释放”的行为。

### 预览能力

1. `app_media` 提供按 `MediaResourceId` 工作的资源缩略图和全屏预览 Widget，不接收 Support Message。
2. 图片预览支持真实文件解码、适配屏幕、双指缩放/平移、loading/error 和关闭。
3. 视频预览使用经验证的 Flutter 播放库，支持初始化、真实首帧、播放/暂停、进度拖动、当前/总时长、
   App 前后台与 Route 生命周期暂停、错误和 dispose；缩略图中的视频不得常驻播放器或自动播放，而由
   bounded poster generator 生成净化小图。poster 不可用时展示明确的视频占位状态，点击后仍可进入
   Viewer 做真实 decoder probe/playback。
4. 全屏区域覆盖上下 Safe Area，关闭与播放控件有 Semantics/tooltip；组件不声明 Shoppe 文案、业务
   Route 或消息发送规则。

## 文档落位

- 在 `docs/infrastructure/media-resources.md` 写入上述详细契约、状态、公共 API、消费者和验证边界。
- 在 `docs/infrastructure-modules.md` 增加“Flutter 媒体资源与预览”索引。
- 更新 `CLAUDE.md`、`docs/architecture.md` 的仓库结构、包职责和依赖矩阵。
- 必要时更新中文/英文详细 HTML 中的架构说明；README 仍只做预览和概括，不展开内部协议。

## 验收与验证

- 文档明确区分消息引用、Store 物理文件、Native lease、Bridge transfer copy 和 Preview Controller。
- 所有权图完整覆盖成功、取消、失败、晚到、会话释放和 App dispose；没有路径跟随消息的表述。
- 依赖矩阵不允许 `app_data -> app_media`、`app_media -> app_features` 或 `app_media -> capture bridge`。
- 后续任务卡与本设计使用同一命名和依赖方向，没有未决架构分支。

```bash
make harness-check
git diff --check
```

## 环境限制

纯文档任务不需要 Flutter SDK、Android SDK、Xcode、设备或真实媒体。执行后停在实现前接受 Review。

## 执行结果

- [实现 Review](../../reviews/execute-flutter-media-resource-architecture.md)
- [测试证据](../../reviews/test-evidence/flutter-media-resource-architecture.log)
