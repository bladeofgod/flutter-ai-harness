---
task: media-capture-export-wire-evolution
status: passed
p0: 0
p1: 0
---

# Review: Media Capture Transfer Wire V3

## 结论

多轮独立 Review 与修复复核完成，当前 `P0=0`、`P1=0`、`P2=0`。Wire V3 在保留 V1/V2 历史投影的
前提下，增加一次性 `materialize_media_resource` / `release_materialized_media`，并把 Capability V4
export、Adapter 私有 transfer store、Flutter 临时导入边界和 source lease 顺序闭合为机器契约。

## 修复复核

- file URI 固定为 uppercase percent-encoded ASCII serialization，按 ASCII code unit 计算 4096 上限；
  raw Unicode、合法 percent-encoded Unicode、authority、路径、转义和 4096/4097 向量均由三端共享。
- fixed Native sink、50 MiB request/result、JPEG/MP4、duration 与 optional SHA-256 分支都有独立 mutation
  Fixture；Capability Failure 与 Wire 自有错误保持一一来源映射。
- export handle 使用 attachment-scoped 128-bit CSPRNG、严格 registry lookup、禁止复用和跨 attachment；
  locator、handle、路径和底层错误不能进入日志、错误 details、事件、消息、Fixture 或持久化。
- materialize、in-flight cleanup、active export cleanup、显式 release 和 restart sweep 的顺序均被锁定。
  同 handle 并发 release 原子认领 cleanup/tombstone reservation，后到请求只加入同一终态；删除失败
  保留 registry、active 容量和同一 reservation。
- Engine detach 同时清理 in-flight 与 active transfer；TTL/restart、late result、tombstone 上限、容量归还
  和 source lease 不自动释放均有结构化规则与失败 Fixture。

## 验证

当前证据中的 `make format`、`make harness-check`、`make harness-test` 和 `git diff --check` 全部通过。
真实 cache root、原子 rename、文件删除和跨端 URI parser 仍由后续 Dart/Android/iOS 实现任务验证。
