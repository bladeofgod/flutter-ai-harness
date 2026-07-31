---
task: media-capture-export-dart-client
status: passed
p0: 0
p1: 0
---

# Review: Media Capture Transfer Dart Client

## 首轮结论

独立 Review 首轮为 P0 0、P1 2、P2 0。Wire V3 的闭合错误、URI、TTL、MIME、长度和 locator
脱敏校验已经生效，但有两项资源所有权与结果关联问题阻断归档。

## P1 发现

1. `materialize_media_resource` 已经在 Native 登记 export 后，如果 Dart 只因 URI、TTL、MIME、metadata
   或未知字段拒绝成功 payload，Client 不会释放已采纳的 export。连续异常结果会占用 transfer 文件和
   active capacity，直到平台 TTL 或 detach 回收。修复需要在完整 payload 解码失败时，只从已经严格验证
   Wire 版本、当前 requestId、resultType 和 exportHandle 的响应中提取内部 cleanup token，并复用有界
   release/retained cleanup；token 不得进入公开 failure。
2. materialize 返回的 `mediaType`、`byteLength` 和 `durationMillis` 没有与发起请求的 confirmed media
   对齐。Capability 是原始 source copy，不允许结构合法但属于另一媒体的 metadata 被接受。修复需要把
   expected metadata 传入 Codec，任何不一致都返回 `invalid_wire_payload` 并触发同一 export cleanup。

## 首轮验证

现有证据 `docs/reviews/test-evidence/media-capture-export-dart-client.log` 中的 113 项包测试、全仓
analyze/test/lint、Harness 和 `git diff --check` 均通过，但尚未覆盖上述失败 cleanup 和 metadata
串线场景。Mock Channel 仍不能证明平台 URI 可读或平台 cleanup。

## 最终复审

首轮两个 P1 已关闭，最终 P0 0、P1 0、P2 0：

- materialize 完整解码失败时，只在 Wire 版本、当前 requestId、resultType 和合法 export handle 均通过
  后提取内部 cleanup token；URI、MIME、TTL、未知字段和 metadata mismatch 都会释放未交付 export。
- release 首次失败会保留 cleanup ownership，并由 `dispose()` 有界重试；正常、失败和 late dispose
  分支均保持 exactly-once，不会把 handle 交给调用方或重复释放。
- 返回的 `mediaType`、`byteLength`、`durationMillis` 已与 confirmed source 精确绑定；不一致按
  `invalid_wire_payload` 拒绝并清理 export，不释放 source media。

最终 evidence 包含 122 项包测试、包/全仓 analyze、全仓 test、lint、Harness 和
`git diff --check`，全部通过。真实文件可读性与平台 cleanup 仍留给双端 Adapter 和最终集成任务。
