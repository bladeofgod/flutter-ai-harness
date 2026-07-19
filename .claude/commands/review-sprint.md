---
description: 从跨任务、共享契约和集成行为视角只读审查已完成 Sprint
argument-hint: "<sprint-directory-or-task-list>"
---

所有单卡闭环完成后，再执行 Sprint 整体审查。

1. 读取 Sprint Overview、任务卡、Review 报告和测试证据。
2. 审查相对 Sprint 基线的聚合 diff。
3. 检查跨卡回归：依赖方向、重复抽象、Entity 不一致、DI 顺序、Route 冲突、平台契约漂移、生成文件过期和端到端覆盖缺口。
4. 运行 `make check`，并根据聚合影响面运行集成测试或原生构建。
5. 写入 `docs/reviews/<sprint>-summary.md`，包含 P0/P1/P2、任务覆盖、验证证据、未验证平台和发布建议。
6. 不修改实现；需要修复时，等待用户明确调用 `/fix-review-findings <report-path>`。

除非问题在集成层重新出现，不重复已经解决的单卡问题。只有 P0/P1 清零且所有跳过验证都已说明，Sprint 才可通过。
