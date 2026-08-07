---
task: generate-media-capture-dart-wire-codec
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：迁移 Media Capture Dart Wire 生成代码

## 结论

- `media_capture_wire.g.dart` 由统一 manifest 生成，固定 source digest
  `76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27`，包含 version、channel、17 methods、
  5 events、result/error identifiers、闭合 enum、payload descriptor、字段类型/范围与基础 primitive。
- 手写 constants、client 与 codec 已改为消费生成符号；跨字段校验、request registry、错误脱敏、Channel
  生命周期、dispose 和 transfer cleanup 继续由手写实现负责。
- enum 转换显式 total，未使用 `enum.name`/`toString()` 形成 wire 值；未知入站、未知字段、类型/range、
  signed-64、URI/handle、thumbnail bytes 与 cleanup 拒绝语义保持 fail-closed。
- 公共 barrel 没有导出生成内部 descriptor 或裸 collection。

## 验证

- `dart run tool/generate_media_capture_wire.dart --runtime dart --check`：通过。
- Bridge Package `analyze --fatal-infos`：通过。
- Bridge Package：129 tests passed，包含 drift、descriptor coverage、共享 golden coverage、public API leak、
  恶意 payload、Channel、late callback、dispose 与 transfer cleanup。

完整命令摘要见[测试证据](test-evidence/generate-media-capture-dart-wire-codec.log)。Mock Channel 结果只证明 Dart
Runtime，不替代 Android/iOS 平台线程与生命周期验证。复审未发现 P0/P1/P2。
