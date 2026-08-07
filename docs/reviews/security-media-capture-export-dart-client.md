---
task: media-capture-export-dart-client
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_media_capture_bridge/lib/app_media_capture_bridge.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_client.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_constants.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_models.dart
  - app/packages/app_media_capture_bridge/lib/src/media_capture_wire_codec.dart
implementationDigest: 872b1e22fece3fd8a8ea604a8361b729797a632251880a7b1fd2bb26981055f3
---

# Security Review: Media Capture Transfer Dart Client

## 首轮结论

独立 Security Review 首轮为 P0 0、P1 1、P2 1。URI canonicalization、长度与 TTL 上限、opaque
handle、错误闭合集、pending/tombstone 容量和字符串脱敏已经生效。

## P1 发现

被 Dart 拒绝的 materialize 成功结果不会释放 Native export。攻击者或缺陷 Adapter 可以返回已登记
export 的成功 envelope，并让 handle 合法而后续 URI、TTL、MIME、metadata 或未知字段异常；Dart
返回 `invalid_wire_payload` 后，敏感 transfer 副本与 active capacity 会保留至 TTL。修复必须在严格
验证响应身份后回收未交付 export，失败时保留 cleanup ownership 并重试，且不能泄漏 handle。

## P2 发现

公开 `MediaCaptureFailure.stackTrace` 可被业务调用方或通用错误采集器直接记录，暴露 Debug/JIT 符号与
本机构建路径。修复应从公开 Failure DTO 删除调用栈；内部异常转换只保留闭合 code/diagnostics，不能把
原始异常或调用栈挂到公开结果。

## 首轮验证缺口

Mock Channel 不证明 transfer root、symlink/TOCTOU、真实文件 metadata 或平台 TTL/restart cleanup；
这些由双端 Adapter 和最终 Store 集成验证。现有证据通过，但没有覆盖 P1 的失败结果释放路径。

## 最终复审

独立安全复审确认首轮 P1/P2 均已关闭，最终 P0 0、P1 0、P2 0：

- cleanup token 只由严格匹配的 Wire V3、当前 requestId、materialize success resultType 和合法
  base64url export handle 建立；身份字段异常不会触发可能误删其他资源的 release。
- rejected result 会立即尝试 release，失败后保留 cleanup ownership 并在 dispose 有界重试；公开 failure
  不包含 locator、handle、payload 或底层错误。
- `MediaCaptureFailure` 公开 DTO 只保留闭合 code 与 diagnostics，不再保存或暴露 StackTrace。
- source metadata 不一致只产生闭合 `invalid_wire_payload`，并通过相同的受约束 cleanup 路径释放新
  export；source media ownership 保持不变。

当时实现摘要为 `193348951adc9189356d3832d4e65ce31ea36ca065ed5405c76c515e50fcb8b2`；
当前摘要以前置 frontmatter 为准。
最终 evidence 中 122 项包测试及所有仓库门禁均通过。真实 transfer root、symlink/TOCTOU、文件内容
一致性和平台 TTL/restart cleanup 仍由 Android/iOS Adapter 与最终集成验证。

## Presentation Dismiss 共享 Client 复审

共享 Client 新增的单 presentation slot 与 dismiss 生命周期不改变 transfer cleanup token、export
identity 或 source ownership。独立 Security Review 的覆盖 P1 已按建议修复，全包回归通过；本报告摘要
重新绑定当前共享 Client/Codec 实现。
