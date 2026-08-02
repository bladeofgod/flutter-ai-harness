---
task: flutter-media-preview-components
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_media/lib/app_media.dart
  - app/packages/app_media/lib/src/preview/active_media_player_coordinator.dart
  - app/packages/app_media/lib/src/preview/media_playback_driver.dart
  - app/packages/app_media/lib/src/preview/media_playback_probe.dart
  - app/packages/app_media/lib/src/preview/media_poster_generator.dart
  - app/packages/app_media/lib/src/preview/media_poster_service.dart
  - app/packages/app_media/lib/src/preview/media_preview_image_policy.dart
  - app/packages/app_media/lib/src/preview/media_preview_models.dart
  - app/packages/app_media/lib/src/preview/media_preview_page.dart
  - app/packages/app_media/lib/src/preview/media_resource_thumbnail.dart
  - app/packages/app_media/lib/src/preview/video_player_media_playback_driver.dart
  - app/packages/app_media/lib/src/preview/video_thumbnail_poster_generator.dart
  - app/packages/app_media/pubspec.yaml
  - app/pubspec.lock
  - app/tool/redact_evidence.dart
  - scripts/quality/evidence-lint.sh
  - scripts/quality/test-evidence.sh
implementationDigest: bd668b9edace1ab75c0f9127e76d3088c6aaa73d8d9b1c5129ee42f2ad2e7751
---

# Security Review：Flutter 媒体预览组件

## 最终结论

独立只读 Security Review 通过，当前 P0 0、P1 0、P2 0。审查覆盖本地媒体输入、临时 poster、
symlink/路径边界、内存与文件句柄、原生日志、Git/CocoaPods 供应链、依赖锁定和测试证据脱敏；
首轮没有读取普通 Reviewer 结论。

## 已接受与后置风险

### 已接受：Android API 23-26 仍会先解码完整视频帧

Demo 最低支持 API 23。Hosted `1.0.6` 的 Android 实现只在 API 27 以上使用 bounded
`getScaledFrameAtTime`；API 23-26 会先执行 `getFrameAtTime`，再创建缩放副本。50 MiB 文件上限
不能限制 4K/8K 单帧的解码内存，两个并发 poster job 可造成稳定的内存耗尽路径。

用户已明确接受第三方插件内部实现风险，本任务不 fork 或修改第三方源码。该风险保留记录，
不作为当前 Android/Flutter 阶段的未解决 P1。

### 已接受：第三方原生实现记录原始异常和媒体信息

Hosted `1.0.6` 的 Android 实现多处调用 `printStackTrace()`、返回原始异常 message，并记录原始视频
尺寸；iOS 取帧失败时通过 `NSLog` 记录完整 `NSError`。文件异常可能携带 source/destination 路径，
这些日志发生在 Dart 错误映射之前，Dart 侧无法脱敏。

用户已明确接受第三方插件内部实现风险。应用公共边界仍只交付稳定错误类型；后续升级 provider 时
优先选择移除原始异常和媒体 metadata 日志的版本。

### 后置：iOS 最终原生依赖图尚未锁定

`flutter_video_thumbnail_plus 1.0.6` 已在 [pubspec](../../app/packages/app_media/pubspec.yaml)
和 [lockfile](../../app/pubspec.lock) 固定 Hosted 版本与 archive SHA-256；但其 podspec 对
`libwebp` 没有版本约束，Demo 的 `Podfile.lock` 尚未包含插件、`libwebp`
版本或 spec checksum。

用户已明确把 iOS 工作放到 Android/Flutter 验证之后。iOS Bridge podspec 完成后，由 iOS/跨 Runtime
任务执行 App Pod resolution、锁定 `Podfile.lock` 并验证 Host build。

## 已确认边界

- `flutter_video_thumbnail_plus 1.0.6` 使用 Pub Hosted 来源，lockfile 固定 archive SHA-256
  `096b9095ddf58861f143c7c1ac1695653bf38620870f9e76f75f5b089d914d1c`。
- 新 iOS 实现在取帧前设置 `AVAssetImageGenerator.maximumSize`，旧 provider 的 iOS 全尺寸解码 P1
  已关闭。
- 新 provider 的 Android source/output stream 使用 try-with-resources，旧 provider 的文件句柄 P2
  已关闭。
- 受控随机 job root、canonical containment、返回路径比对、bounded read、symlink no-follow、late
  cleanup 和最多两个 native job 的 Dart 边界保持闭合。
- Android Demo Debug APK 和独立 iOS Pod target 已编译；完整 App iOS Host build 尚未通过。

## 后续验证

本任务当前证据已覆盖 Flutter 测试、`app_media` analyze、Android Debug Host build 和仓库 lint。
iOS Host build、Pod lock 和设备级解码由后续 iOS/跨 Runtime 任务验证。

## Evidence 脱敏修复复核

已为 Xcode destination 行增加限定范围的设备 ID/名称脱敏，为 `/var/folders/...` result-bundle
增加临时路径脱敏，并让 `evidence-lint` 独立拒绝两类原始形态。Fixture 同时覆盖采集器正向替换与
lint 失败关闭，当前任务 evidence 已使用修复后的工具重新生成，未再出现真实设备名称、设备 ID 或
本机 result-bundle 路径。该 P1 已关闭。

## Provider 替换复核

用户明确接受第三方插件自身实现风险，只要求确认 Android/iOS 可用。本轮将 provider 替换为 Hosted
`flutter_video_thumbnail_plus 1.0.6`，重新生成完整 evidence：Android Demo Debug APK 与隔离 iOS Pod
target 均编译成功。第三方 Android 低版本全帧解码、原生异常日志及 iOS Pod lock 后置事实继续在
本报告保留，但分别属于用户已接受风险和后续阶段验证项；没有修改第三方源码。

## Android/Flutter 阶段复审

独立 Security Reviewer 基于当前实现、更新后的任务范围和脱敏证据复审，未发现新的未接受 P0/P1。
受控随机 job root、canonical containment、symlink no-follow、provider 返回路径比对、bounded read、
最多两个 native job、超时与 late cleanup 均保持闭合；当前 evidence 未包含设备 ID、设备名称或本机
临时路径。结论为 `P0=0`、`P1=0`、`P2=0`。

## 跨 Runtime 集成影响

lockfile 变化只把已存在的 `xml` 提升为 Harness 直接 dev dependency；Thumbnail/Viewer、播放器和资源
生命周期实现未修改。独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。
