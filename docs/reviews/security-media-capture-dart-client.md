---
task: media-capture-dart-client
status: passed
p0: 0
p1: 0
implementationFiles:
  - app/packages/app_media_capture_bridge/analysis_options.yaml
  - app/packages/app_media_capture_bridge/pubspec.yaml
  - app/packages/app_media_capture_bridge/lib/app_media_capture_bridge.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_client.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_constants.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_models.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_wire_codec.dart
implementationDigest: b522fb9c3c76d8a73aad939fcbfb3c4ca5e20e61043ed691e327d8251a76333c
---

# Security Review: Media Capture Dart Client

## 最终结论

独立 Security Review 的首轮问题已经关闭，最终 P0 0、P1 0、P2 0。审查覆盖不可信 Channel 输入、
opaque handle、requestId 资源预算、事件 listener、dispose 竞态、confirmed lease、bounded thumbnail、
错误脱敏和 plugin 依赖边界。

## 已关闭问题

- dispose 不再在晚到 Session、preview 或 confirmed lease 尚未 settle 时成功关闭；cleanup acknowledgement
  必须通过类型、requestId、resultType 与资源 identity 校验，失败会保留 ownership、重试并向 dispose 调用方
  暴露稳定错误。
- EventChannel handler 在 disposal 开始时同步移除；共享 slot 阻止第二个 Client 覆盖合法 listener。
- JPEG 只接受结构有效且尺寸一致的展示数据，拒绝 EXIF、JFXX、ICC、COM、任意 APP suffix、SOS/SOF
  乱序与畸形组件结构。thumbnail bytes 有 envelope、字节和像素上限，并使用防御性 copy。
- PlatformException message、raw details、payload、handle、requestId、bytes、path/URI 和底层异常文本不会进入
  公共 failure 字符串；capacity 与 error code 使用闭合集合关联。
- requestId 使用平台安全随机源，pending 上限 32、completed tombstone 上限 4096/300 秒；重复和容量耗尽
  在 Native 调用前稳定拒绝。

## 验证缺口

证据中的 93 个测试、analyze 和格式门禁均通过。Mock BinaryMessenger 不证明恶意或缺陷 Native Adapter
之外的真实平台行为；Adapter detach、Engine teardown、权限和真实媒体净化仍由平台与集成任务验证。

## Workspace 登记复审

后续 `media-capture-flutter-package-registration` 只为 Package 增加 `resolution: workspace`，没有改变
Channel 输入处理、资源预算、错误脱敏、媒体校验、Plugin metadata 或依赖来源。独立 Security Reviewer
确认该变化不新增供应链或运行时边界，本报告据此使用全部七个 implementation file 重新计算摘要。
本次没有重跑上述 93 个 Dart Client 测试；当前任务的 Workspace、分析、lint 和 discovery 结果记录在其
独立 evidence 中，不把历史测试结果表述为本轮新证据。

## Wire V3 Transfer Client 对齐

后续 `media-capture-export-dart-client` 在相同 Client/Codec 文件增加 Wire V3 transfer API，并从公开
`MediaCaptureFailure` 删除可被调用方记录的 `StackTrace`。旧 V1/V2 方法的 code、diagnostics、
request lifecycle 和 typed result 行为未改变；当前全包回归由新任务 evidence 记录，本报告据此重新计算
七个 implementation file 的摘要。

## Presentation Dismiss 复审

独立 Security Review 发现的并发 presentation target 覆盖 P1 已关闭：Client 以单一原子 slot 在 Native
调用前拒绝第二笔请求，settled 只清理匹配 request ID；dispose 优先拒绝新请求并先 dismiss。新增并发与
dispose 测试及全包回归通过，公开 API 仍不暴露 request ID、payload 或异常 details。
