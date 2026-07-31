---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy:
  - flutter-media-preview-components
  - media-capture-flutter-presentation-dismiss-integration
  - media-capture-android-export-bridge-adapter
  - media-capture-export-dart-client
  - shoppe-support-chat
securityReview: required
---

# 接入 Customer Support 媒体资源消息与预览

## 输入与事实来源

- 已实现 `app_media` Resource Store、缩略图和全屏图片/视频预览。
- Media Capture Dart Client/Android Adapter 已提供 Wire V3 materialize/release；iOS 后续由独立任务接入。
- 当前 `SupportMediaContent` 只有 type/label/previewBytes/duration，媒体气泡无点击行为；
  `NativeSupportMediaPicker` 读取缩略图后立即 release Native lease。
- 用户要求：Customer Support 从 Camera/Gallery 发送图片或视频，消息可见真实预览并可点击查看/播放。

## 目标

- 让 `MediaResourceId` 跟随 Support 消息，并把 gallery/camera 临时文件安全导入 `app_media`。
- 修正 native lease 时序：Store commit 成功后才释放 transfer copy 和 source lease。
- 使用通用缩略图/全屏预览替换黑框和静态播放图标，保持现有发送、回复和评分流程。

## 非目标

- 不修改 Capability/Wire/Native/Adapter，不上传媒体、不跨重启持久化消息、不保存相册。
- 不在 `SupportMediaContent` 保存路径、URI、capture/export handle 或播放器 Controller。
- 不为 Support 复制一套私有图片/视频 Viewer，不改变 Search/Order Review 媒体规则。
- 本任务只完成 Flutter 行为和 Android 可用链路；iOS 运行结论由最终集成任务给出。

## 实现要求

1. `SupportMediaContent` 增加必填 `MediaResourceId`，保留类型、label、可选 duration 和 bounded sanitized
   poster。Fixture payload/mapper 只序列化 ID 字符串和轻量元数据；绝对路径/URI/handle 不得进入
   `app_data`、Support API 或 message `toString`。
2. `SupportMediaAttachment` 返回 Store 已 commit 的 owned resource，不返回 picker path。调用方持有 import
   初始引用；不得让 Controller 的 generation check 决定会话引用是否存在。
3. `LocalSupportChatApi`（或同层会话资源协调器）拥有原子接纳边界：调用 `sendMedia` 时先为候选会话
   `retain(resourceId)`，再写入 Fixture/DataSource；写入成功即由会话无条件持有该引用并返回带
   accepted message/resource ID 的 typed receipt，即使 Controller 随后 late/dispose 也不能回滚。写入失败
   则在返回 failure 前释放候选引用。Controller 在 API 成功或失败后都只释放自己的初始引用 exactly once。
4. Gallery：`image_picker` 只负责用户选择。验证 picker metadata 后立即调用 Store import；图片由 Store
   canonicalize 为 JPEG/PNG，视频只接受 MP4/MOV并在发送前执行真实 decoder probe。其它格式或超过
   20/50 MiB 返回 `unsupported_media`/`too_large`；无论结果如何都不保留 `XFile.path`。取消不创建资源，
   读/导入/probe失败清理 staging和初始引用。
5. Camera：Support V1 的 `maxVideoDurationMillis` 固定为 15,000，降低 50 MiB export 上限下的正常失败
   概率；超过上限仍返回明确 `too_large`，不改变通用 Capability 的 60 秒能力。confirmed 后可读取
   bounded poster，但 poster failure 不应丢弃有效源；随后调用
   materialize、Store import。固定清理顺序：

   ```text
   import success -> release export -> release native media -> return attachment
   import failure -> release export(if any) -> release native media -> typed failure
   ```

   不能在 Store commit 前调用 `releaseMedia`；cleanup failure 使用现有 retained retry，dispose 必须收敛。
6. `FeaturesRegistry` 创建/接收一个 app-scoped `MediaResourceStore`，通过构造函数把同一实例注入 Support
   picker、route/page和 preview。外部注入实例不由 Registry 越权 dispose；内部创建实例 exactly once
   dispose，并在所有 picker/client 清理后释放会话资源。
7. 会话接纳的 media ID 由 Support resource coordinator 持有，Page/Controller route dispose 不删除已发送
   消息资源。`startConversation` 成功替换当前会话即视为 reset：先发布新会话并卸载旧 Thumbnail/Viewer，
   再释放旧会话全部媒体；消息删除（若现有流程有）和 Registry dispose 使用同一顺序。
8. 媒体气泡使用 `MediaResourceThumbnail` 显示真实图片或 bounded video poster；保持 220x160 稳定约束、label/时长和
   play overlay。loading/error 有明确状态，不再用永久黑色 `ColoredBox` 作为有效消息预览。
9. 整个气泡是可点击语义按钮。通过 GoRouter 的静态命名 route + typed `extra`（或等价不把 ID 写进 URL
   的方式）打开 `app_media` 全屏 Viewer；缺失/失效 ID 显示稳定错误并能关闭返回 Support。
10. 返回 Support 后会话、滚动、输入文本和发送状态保持；视频预览关闭/后台后停止播放，重复打开不泄漏
   Controller 或 retain。
11. Fixture payload 可以携带通过 Value Object 校验的 opaque resource ID，以支持 Domain round-trip；
    但 file URI、capture/export handle 和原始 bytes 不得进入 Fixture。日志、FlutterError、Snackbar、
    Semantics 和 `toString` 连 resource ID 也不得输出。UI 文案沿用英文 Customer Support 语言，发送按钮
    保持 `Send`。

## 测试与验收

- Picker/API/Controller 单测覆盖 gallery JPEG/PNG/MP4/MOV canonicalization/probe、unsupported/too-large、
  camera 15 秒配置、poster success/failure、materialize/import/release 顺序、接纳前 retain、接纳成功后的
  Controller late/dispose、写入失败回滚、重复点击和每个引用 exactly-once cleanup。
- Data mapper/fixture 测试证明 resource ID round-trip，拒绝空/畸形 ID，payload 不含 locator/handle。
- Widget/route 测试覆盖真实测试图片、视频首帧、点击打开、play/pause/seek/返回、missing/error、
  320/375/横屏/大字号/Safe Area/Semantics 与原文字发送回归。
- Registry/Demo tests 固定内部/外部 Store ownership、`startConversation` reset先卸载 UI 再释放旧引用、
  路由重建和 App dispose 不双重释放。
- Android Debug APK 安装后，用户主动选择/拍摄的图片与视频均显示真实内容，点击可全屏查看/播放；测试
  完成后 transfer/native lease 已释放但 message resource 仍可访问。

```bash
TOOL_WORKDIR=app/packages/app_data bash scripts/flutter-tool.sh test
TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
make format
make analyze
make test
make lint
make harness-check
git diff --check
```

## 环境限制

Android 真实 Camera/Gallery 需要用户连接设备并主动授权/选择，不把媒体、设备 ID 或路径写入证据。iOS
尚未完成 V3 Adapter 时只验证 Flutter Fake/Host compile，不宣称 iOS 运行可用。
