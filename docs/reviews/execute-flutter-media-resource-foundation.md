---
task: flutter-media-resource-foundation
status: passed
p0: 0
p1: 0
---

# Review: Flutter 媒体资源存储基础件

## 结论

首轮独立 Review 未通过，P0 1、P1 1。Store 的导入、校验、引用和大部分清理边界完整，但删除连续失败
后没有保留进程内 cleanup ownership；同时任务要求的最终 `make harness-check` 尚未通过。

## P0

### 最终 Harness 门禁尚未通过

[测试证据](test-evidence/flutter-media-resource-foundation.log) 中的 `make harness-check` 运行时，正在并行
演进的 Capability V4 尚未完成 V4 -> V3 -> V2 历史投影，且受共享文件影响的旧 Security Review
摘要已经漂移。该问题不属于 Store 实现缺陷，但在 Capability 收敛、安全复审和最终 Harness 重跑前，
本任务不得归档。

## P1

### 删除失败后丢失可重试的 cleanup ownership

`DefaultMediaResourceStore.release` 在最后一个 lease 释放时先移除 Registry entry、写 tombstone，再尝试
删除文件。连续三次删除失败后只返回 `import_failed`；原 lease 已失效，重复 release 不会再次尝试删除，
物理文件只能等待 Store dispose 或下次进程初始化清理。

修复要求：资源保持不可解析，但 Store 必须记录 pending deletion；同一 lease 重复 release、后续清理
机会和 dispose 都能继续 bounded retry，成功后移除 cleanup ownership。增加删除失败、重试成功和
dispose 收敛测试。

## P2

### 生产 Factory 可以重复清空同一 Store 根

`createMediaResourceStore()` 每次调用都创建新 Store，而初始化会清空固定 cache 子目录。同进程误建第二个
Store 会删除第一个 Store 的 active 文件。生产 Factory 应返回进程级唯一实例，依赖注入使用的
`DefaultMediaResourceStore.create` 继续允许测试隔离。

## 不采纳项

Review 将证据中的 `dart format --output=none` 输出 `Changed tool/harness_check.dart` 解释为 Foundation
修改了共享 Harness。该命令为只读格式检查，只报告文件若写入会变化；实际文件由并行的
`media-capture-export-capability-evolution` 任务独占修改，Foundation 执行器未写这两个禁止文件，因此
不构成本任务范围越界。

## 已确认项

- `MediaResourceId` 格式闭合且 `toString` 脱敏。
- `app_media` 依赖方向没有反向依赖 Feature、Data 或 Capture Bridge。
- 源文件 URI、symlink、长度、digest 和 Store 内 canonical 文件在关键边界被复核。
- 图片会真实解码并重编码，视频只声明 ISO BMFF Foundation 校验，不冒充真实 decoder probe。
- 聚焦测试、全量测试、analyze、lint、format 和 `git diff --check` 已有通过证据。

## 修复后复审

独立 Reviewer 复审通过，当前 P0 0、P1 0、P2 0：

- Store 以 `_pendingDeletions` 保留物理清理所有权；重复 release、后续队列操作和 dispose 都会继续
  bounded retry，资源在此期间保持不可解析。
- 生产 Factory 缓存进程级 Store Future，不再因重复创建清空同一 cache root。
- 修复新增测试覆盖删除失败后重试、dispose 收敛、source final symlink 替换、图片 decoded-memory 预算
  和伪 BMFF；修复后 24 个聚焦用例及全量门禁通过。
- 共享 Harness 的旧失败不再作为 Store 代码问题；任务仍需等待历史 Security Review 摘要同步后重跑
  最终 `make harness-check` 才能归档。
