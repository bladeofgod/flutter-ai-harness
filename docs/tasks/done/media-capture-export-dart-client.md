---
executor: task-executor
platforms: [flutter]
workKinds: [dart-client]
blockedBy:
  - media-capture-dart-client
  - media-capture-export-wire-evolution
securityReview: required
---

# 实现 Media Capture Transfer Dart Client

## 输入与事实来源

- Wire V3 `materialize_media_resource`、`release_materialized_media` 和 scoped locator 安全分类。
- 已归档的类型化 `app_media_capture_bridge` Dart Client 与现有 request/codec/lifecycle 测试。
- `app_media` import API 只消费临时 file URI，不允许 locator 进入消息。

## 目标

- 为 Dart Client 增加类型化 transfer materialize/release API 和严格 Wire V3 codec。
- 对 Native 返回的 URI/metadata 按不可信输入校验，并为上层提供明确 ownership/release 模型。
- 保持现有 V2 capture、presentation、thumbnail 和 release API 行为兼容。

## 非目标

- 不复制文件、不依赖 `app_media`、不创建消息、Controller 或 Viewer。
- 不实现 Android/iOS Adapter，不修改 Contract、Host、Native Module 或 Workspace 依赖。
- 不暴露裸 Map、PlatformException、任意路径 API、raw bytes 或长期持久 locator。

## 实现要求

1. 增加不可变 `MediaCaptureMaterializedMedia`、opaque export handle、typed call result/failure；file URI
   属性明确为短生命周期 infrastructure-only，`toString` 始终 redacted。
2. Codec 严格验证 Wire V3 envelope、required/unknown keys、版本、类型、signed-64、MIME、长度、TTL、
   export handle 和 URI。URI 只接受 canonical `file:///absolute/path`，允许空 host，拒绝非空 host、
   userinfo、port、query、fragment、dot segment、非法 percent encoding和超长值；直接消费 Contract
   提供的三端 golden vectors。
3. `materializeMedia` 只接受 confirmed media handle；`releaseMaterializedMedia` 只接受 export handle。
   Client 不自动调用 `releaseMedia`，不隐藏“Store commit 后才释放 source”的上层所有权要求。
4. request exactly-once、pending capacity、dispose、late result、Engine unavailable 和错误 redaction 复用现有
   coordinator；materialize late success 必须尽力调用 release export 或交给 Adapter boundary cleanup，
   不能把 locator 交付给已 dispose 调用方。
5. Capability Failure 与 transfer-store/Wire Failure 使用 Contract 已区分的类型化 code，不能归并为
   `export_failed`。URI、export handle、media handle、payload 和底层异常不得进入 FlutterError、日志、测试 evidence 或
   error details。公开 failure 只保留稳定 code/recoverable 信息。
6. 保留 Wire V2 codec compatibility tests；Client 发送 Wire V3 后不以未知字段 fallback 到 V2 export。

## 测试与验收

- Mock Channel 覆盖 materialize/release success、所有稳定 failure、重复、容量、dispose、late success 和
  cleanup exactly once。
- 表驱动恶意 payload 覆盖非 file URI、网络 URI、authority/query/fragment、dot segment、坏转义、超长、
  MIME/长度/TTL 不一致、未知字段和 redaction。
- 公共 API 检查证明上层业务模型不会接触 Map/raw bytes，`app_media_capture_bridge` 仍不依赖 Workspace 包。

```bash
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh test
make format
make analyze
make test
make harness-check
git diff --check
```

## 环境限制

Mock Channel 不证明真实 file URI 可读或平台 cleanup。双端 Adapter 与最终集成任务补充真实文件证据。

## 执行记录

- Review：[`../../reviews/execute-media-capture-export-dart-client.md`](../../reviews/execute-media-capture-export-dart-client.md)
- Security Review：[`../../reviews/security-media-capture-export-dart-client.md`](../../reviews/security-media-capture-export-dart-client.md)
- 测试证据：[`../../reviews/test-evidence/media-capture-export-dart-client.log`](../../reviews/test-evidence/media-capture-export-dart-client.log)
