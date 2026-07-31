---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [integration]
blockedBy:
  - media-capture-android-export-bridge-adapter
  - media-capture-android-host-integration
  - media-capture-flutter-package-registration
  - media-capture-ios-export-bridge-adapter
  - media-capture-ios-native-ui
  - media-capture-ios-quality-gate
  - shoppe-support-media-resource-preview
securityReview: required
---

# 集成 Media Capture V4/V3、Flutter 媒体资源与双端 Host

## 输入与事实来源

- 已完成 Media Capture 基础 Dart Client、双端 Core/UI/Adapter、双平台 Gate 和 Host 前置接线。
- 已完成 Capability V4、Wire V3、transfer Dart Client、Android/iOS export Core/Adapter。
- 已完成 `app_media` Store/Viewer 和 Customer Support 媒体资源消息接入。
- `docs/native-architecture.md`、Bridge 总则、Workspace 依赖矩阵和 CI Host build jobs。

本任务显式升级原“Capability V3 + Wire V2 基础集成”计划，不再另行执行或维护一张固定 V3/V2 的最终
集成卡。V3/V2 仅作为兼容历史保留；本任务是共享文档、Harness、Host 和跨 Runtime vectors 的唯一最终
写入者，从而避免旧计划与新 V4/V3 任务并行改写同一聚合面。

## 目标

- 汇总 Flutter Package/Android Host，完成 iOS Host 依赖、权限和 plugin 注册。
- 验证同一 Dart Client 在 Android/iOS 完成 capture -> transfer -> `app_media` import -> Support message ->
  thumbnail/fullscreen/playback，并在 Store commit 后释放 transfer/source lease。
- 建立 Capability V4/Wire V3 三端 contract vectors，同时保留 V1-V3/V1-V2 历史投影。
- 汇总双平台证据，把专项 Gate 接入 Makefile/CI，并回填共享架构、基础能力和 Bridge 的真实状态。

## 非目标

- 不重新实现前置平台/Flutter 缺陷；发现问题退回对应任务 Executor 并复审。
- 不增加上传、云端 URL、持久消息、相册保存、后台播放、媒体编辑或新的业务入口。
- 不把状态机/Mapper、transfer path、Store 或消息生命周期堆进 MainActivity/AppDelegate/Runner。
- 不改变已经批准的 Capability/Wire；共享契约缺口必须回到契约任务，不能在 Integration 现场修改语义。

## 共享写入所有权

所有前置任务完成后，本任务是以下聚合面的唯一写入者：

- `app/apps/demo/ios/**` 的 Host/plugin/SwiftPM 接线，以及已有 Android Host 接线的只读验证
- `docs/native-architecture.md`、`docs/infrastructure-modules.md`、`docs/infrastructure/media-resources.md`、
  `docs/infrastructure/media-capture*.md`、`docs/bridge/README.md`、`docs/bridge/media-capture*.md`
- `CLAUDE.md`、`docs/architecture.md` 和中英文详细指南中的最终实现状态
- root Harness Validator/Fixture、依赖/边界 gate、`Makefile`、`.github/workflows/ci.yml`
- `app/packages/app_media_capture_bridge/test/contracts/**` 与跨 Runtime golden vectors

不得改写平台 Core/UI/Adapter、`app_media`、Support Feature 的生产实现来“修到能集成”。README 只增加
概括和详细指南入口，不展开内部协议。

## 集成要求

1. 验证依赖图：`app_media -> app_core, app_ui`，`app_features/apps/demo -> app_media`，`app_data` 不依赖
   `app_media`；Bridge Package仍不依赖其它 Workspace Package，Native Module仍不依赖 Flutter。
2. Android Host 保持仓库相对 Gradle dependency、Camera/Microphone 权限和标准 Plugin 注册；iOS 只采用
   `media-capture-ios-quality-gate` 已验证的唯一 Host 路线。两端均不增加 Photo Library/shared storage
   权限或 Entitlement。
3. Host 只创建/装配模块并注册 Adapter，不处理 Wire Map、拍摄状态、file URI、transfer/store lease、
   `MediaResourceId` 或 Support 消息。
4. 建立同一组 JSON/golden vectors供 Dart/Kotlin/Swift 消费，覆盖 V3 methods/events/failures、Capability
   Failure 与 transfer-store/Wire error 来源、canonical `file:///absolute/path` 空 host、恶意 URI、MIME、
   signed-64、50 MiB、4 active/100 MiB、TTL、tombstone、lifecycle、late cleanup 和 redaction。
5. 历史 vectors 继续证明 Wire V1/V2 不暴露原始媒体，Capability V1-V3 的 Native-only surface/read scope
   不变；只有 Wire V3/Capability V4 增加 scoped transfer，不能让最新 shape 反向污染历史投影。
6. 双端专项 gate 验证 Core 4-job/1-MiB working budget、256 KiB chunk、120 秒 deadline、完整 Failure
   taxonomy，以及 Adapter canonical private root、原子 commit、4-active/100-MiB、5 分钟 TTL、restart/
   detach cleanup 和 no-path logging。
7. Flutter 集成测试验证 gallery image canonicalization、MP4/MOV decoder probe、15 秒 Support capture、
   Store import 后 transfer/source lease 释放而 message ID仍可 resolve；会话 reset/消息删除/Registry dispose
   先卸载 Thumbnail/Viewer，再删除最后引用。
8. `MediaResourceThumbnail` 使用 bounded poster而非每气泡播放器；Viewer 图片可缩放、视频有真实帧并可
   play/pause/seek。Poster 2-job/10 秒预算、Viewer 单 player、App/Route lifecycle 和 late cleanup 有证据。
9. 执行 Android Debug APK 与 iOS Debug no-codesign Host build，证明依赖图、plugin registration、
   SwiftPM/Gradle、Manifest/Info.plist 可解析。存在对应设备时再运行用户主动 capture/gallery 流程；缺设备
   时明确记录，不用 Fake 冒充。
10. 根双平台 Gate/CI 保留独立 `check`、Android build、iOS build；Harness 拒绝缺 Package/依赖边、
    contract vector漂移、平台 transfer cleanup缺失、路径进入 Domain/Fixture/log、旧“缩略图后立即释放”
    逻辑或 Support 消息没有 resource ID。
11. 更新共享文档为实际完成状态并链接平台 evidence；只声明真实通过的平台/层级，不记录真实媒体、URI、
    resource/handle、设备 ID、主机路径或公司 Figma 信息。
12. 最终普通 Review 与 Security Review绑定精确实现文件和 evidence，重点复核外部 picker 输入、file
    locator、symlink/traversal、会话所有权线性化、资源残留、供应链依赖和日志脱敏。

## 测试与验收

- Dart/Kotlin/Swift Capability V4/Wire V3 vectors与历史投影全部通过。
- `app_media`、Support、双端专项 Gate、Android APK、iOS no-codesign build和 root check通过。
- Android/iOS 各自有设备证据时，图片可查看、视频有真实帧且可播放；无设备平台明确保留运行缺口。
- transfer/native资源在 Store commit 后释放，Store资源在消息生命周期内有效并在最终 owner release后删除。
- Host 只含装配/权限/注册；Core 不 import Flutter，Adapter 不拥有 capture能力，业务不保存 locator。

## 验证命令

```bash
bash scripts/quality/media-capture-android.sh
bash scripts/quality/media-capture-ios.sh
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
make format
make analyze
make test
make lint
make harness-check
make harness-test
make check
git diff --check
```

## 环境限制

完整验收需要 Android SDK/JDK 与 macOS/Xcode。真实 Camera/Gallery/视频解码只有在用户提供对应平台设备
并主动操作时执行；缺失平台必须明确报告，不能用另一平台或 Fake 替代，也不得保存真实媒体作为证据。
