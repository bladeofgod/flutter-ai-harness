---
description: 按用户明确指定的任务、Review、证据和变更范围，从跨任务与集成视角只读审查已完成 Sprint
argument-hint: "<sprint-id> <task/review/evidence-path>... [diff=<git-range|working-tree>]"
---

所有单卡闭环完成后，再执行 Sprint 整体审查。用户必须明确给出本次纳入的记录以及 `diff` 范围；缺失时停止并请求补充，不维护或猜测 Sprint baseline。

1. 只读取参数中明确指定的 Sprint Overview、`docs/tasks/done/` 任务卡、Review 报告和测试证据，以及这些记录直接引用的产物。
2. 按用户指定的 Git Range、工作树或文件列表审查聚合改动，不从任务时间、当前 HEAD 或历史报告推断范围。
3. 检查跨卡回归：依赖方向、重复抽象、Entity 不一致、DI 顺序、Route 冲突、平台契约漂移、生成文件过期和端到端覆盖缺口。
4. 运行 `make check`，并根据聚合影响面运行集成测试或原生构建。
5. 写入 `docs/reviews/<sprint>-summary.md`，包含 P0/P1/P2、任务覆盖、验证证据、未验证平台和发布建议。
6. 不修改实现；需要修复时，等待用户明确调用 `/fix-review-findings <report-path>`。

除非问题在集成层重新出现，不重复已经解决的单卡问题。只有 P0/P1 清零且所有跳过验证都已说明，Sprint 才可通过。
