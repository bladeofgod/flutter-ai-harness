---
task: media-capture-export-wire-evolution
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/bridge/contracts/wire.schema.json
  - docs/bridge/contracts/media-capture.wire.json
  - docs/bridge/media-capture.md
  - docs/bridge/README.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: 27c2a069b085b0c2dea019bfd63ba54d3620d4572734a8274b470c624756bcad
---

# Security Review: Media Capture Transfer Wire V3

## iOS dismiss 支持状态影响复审

后续变更只提升 `dismiss_capture_flow` 的 iOS support；transfer locator、private root、CSPRNG handle、容量、
TTL、tombstone、canonical URI、source lease 和 cleanup 顺序均未变化。独立 Security Reviewer 确认 P0 0、
P1 0、P2 0，摘要已绑定当前共享文件。

## 结论

独立安全审查及逐轮修复完成，当前 `P0=0`、`P1=0`、`P2=0`。Flutter 不能提供目标路径、URI、文件名、
sink、descriptor 或 raw bytes；只有 Adapter 在 App 私有 cache 中生成的短生命周期 locator 可进入成功
payload，并且只能由基础设施立即导入 Store。

## 已验证边界

- URI 是最大 4096 ASCII code unit 的 canonical `file:///` serialization；非 ASCII path 必须按 UTF-8
  uppercase percent encoding，恶意 host/userinfo/port/query/fragment/dot/percent/control 向量均被拒绝。
- export handle 不可猜测、不可记录、不可跨 attachment 使用；transfer store 有 4 active、100 MiB、
  50 MiB/file、300 秒 TTL 和 4096 release tombstone 的固定上限。
- 同 handle 并发 release 只产生一个原子 claim 和 tombstone reservation；显式 release、TTL、detach、
  restart 与 late cleanup 不会双重删除、重复归还容量或在删除失败后丢失 cleanup ownership。
- source media lease 不因 materialize/release export 自动释放；Flutter 必须在 Store commit 后依次释放
  transfer export 与 source media，避免业务资源建立前丢失源文件。
- mutation suite 覆盖 handle 全部策略、result metadata、release/active/restart 顺序、双类 Engine transfer、
  iOS/Android 私有 root、错误来源、版本投影和 locator redaction。

## 验证缺口

静态契约不能证明平台真实文件始终位于 canonical private root，也不能证明进程终止、磁盘错误和并发 I/O
下的物理清理。Android/iOS Adapter 与最终跨 Runtime 集成任务必须补真实文件和 Host build 证据。

## 跨 Runtime 集成影响

最终集成用三端 golden、Host build 和 fail-closed consumer binding 验证既有 V4/V3 投影，没有改变 Wire
导出语义、locator 分类或清理顺序。独立安全复审为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。
