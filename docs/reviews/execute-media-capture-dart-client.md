---
task: media-capture-dart-client
status: passed
p0: 0
p1: 0
---

# Review: Media Capture Dart Client

## 首轮结论

独立 Review 首轮为 P0 0、P1 3、P2 0，阻断项集中在 dispose 与晚到资源的所有权、跨 Client
EventChannel listener 互斥，以及 JPEG APP metadata 只校验前缀。Client 的闭合 Wire 解码、逐 method
错误白名单、requestId pending/tombstone 和公共类型边界在首轮已满足任务要求。

## 第 1 轮复审

listener 已按 BinaryMessenger/channel 建立共享 slot，dispose 会先同步关闭事件 generation；JPEG APP1-15
已拒绝，APP0 只接受固定 canonical JFIF。复审仍有 P1 1：迟到 Session/lease 的内部 cancel/release
如果超时、抛 PlatformException 或返回畸形 acknowledgement，会被静默吞掉并丢失 cleanup ownership。
P2 另指出 thumbnail 上的公开 mutator 和 SOF/SOS 顺序校验缺口。

## 最终复审

当前实现未发现剩余 P0/P1/P2：

- disposal cleanup 必须解码为对应的 `MediaCaptureCallSuccess`；错误 handle、畸形 envelope、平台错误和超时
  都不会被当作成功。
- cleanup 失败时保留内部 closure 与资源 ownership，执行有界退避；仍未完成时 `dispose()` 以稳定、脱敏的
  `MediaCaptureDisposalException` 结束，后续重复 `dispose()` 会继续重试，而不是让 Client 恢复业务调用。
- 无返回的业务请求和 cleanup 都有总等待边界；事件 handler 在等待 Native acknowledgement 前已经移除。
- thumbnail 清理入口不再随 package barrel 导出，模型对业务调用方保持不可变；入站副本在模型复制后清零。
- JPEG 校验要求 SOF 先于 SOS，并验证 frame/scan component count 与精确 segment length。

新增测试覆盖 cleanup PlatformException、畸形 acknowledgement、错误 handle、跨 dispose 重试、无返回请求、
跨 Client listener、APP metadata 与 scan-before-frame 恶意输入。任务声明的 `executor: task-executor`、
`platforms: [flutter]`、`workKinds: [dart-client]` 与实现范围一致，没有写入 plugin 平台目录或 Host。

## 验证

证据：`docs/reviews/test-evidence/media-capture-dart-client.log`。

- `flutter pub get`：通过。
- `flutter analyze --fatal-infos`：通过，0 issues。
- `flutter test`：通过，93 tests。
- `dart format --output=none --set-exit-if-changed lib test`：通过，0 changed。
- `make lint`、`make format`、`make harness-check`、`git diff --check`：通过。

Mock Channel 只证明 Dart Client/codec，不证明 Android/iOS Adapter 线程、平台 presentation、Camera 或 Host
注册；这些保留给各平台 Adapter、Quality Gate 和最终 Integration 任务。
