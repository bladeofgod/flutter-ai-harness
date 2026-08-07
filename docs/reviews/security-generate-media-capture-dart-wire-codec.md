---
task: generate-media-capture-dart-wire-codec
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/generate-media-capture-dart-wire-codec.md
  - app/packages/app_media_capture_bridge/lib/src/media_capture_client.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_constants.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_wire_codec.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_wire.g.dart
  - app/packages/app_media_capture_bridge/test/media_capture_generated_wire_test.dart
  - app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart
  - app/packages/app_media_capture_bridge/test/contracts/media-capture-v4-v3.golden.json
implementationDigest: 9aca534ad4f4eb71743bd1e96339783cb08c276f02d7907773f578f1bc5c0005
---

# Security Review：迁移 Media Capture Dart Wire 生成代码

## 已检查边界

- MethodChannel/EventChannel 数据继续视为不可信；生成 descriptor 只提供闭合协议事实，不跳过手写的
  required/unknown/type/range、signed-64、URI/handle、thumbnail 和跨字段校验。
- 未知入站值仍映射 `invalid_wire_payload`，出站不可编码仍映射 `wire_encoding_failed`；错误 details 和日志
  不回显原始 payload、路径、URI、handle 或 bytes。
- 生成器不拥有 pending/completed registry、late callback、dispose、transfer cleanup 或媒体资源生命周期；
  这些手写边界的恶意与竞态测试继续通过。
- 生成内部未从 Package 公共 barrel 导出，没有引入 `dynamic`/裸 Map 公共 API、依赖来源、网络、凭据、
  文件权限、Agent/MCP、CI 或发布能力。

## 结论

生成迁移减少了手工协议漂移，但没有扩大 Channel 输入信任或资源所有权。P0/P1/P2 为 0/0/0。Dart Mock
Channel 不替代平台线程、权限和生命周期证明，这些由 Android/iOS 独立任务覆盖。
