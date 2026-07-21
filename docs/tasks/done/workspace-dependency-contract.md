---
executor: task-executor
blockedBy: []
---

# 修正 Workspace 依赖方向契约

## 背景

权威契约、README 中的依赖箭头与 `pubspec.yaml` 的真实 Import 方向相反。

## 输入与事实来源

- `docs/reviews/harness-baseline.md` P1-1
- `CLAUDE.md`
- `docs/architecture.md`
- Workspace 各 Package 的 `pubspec.yaml`

## 目标

统一“箭头表示谁可以 import 谁”的语义，并提供明确允许依赖矩阵。

## 非目标

- 不改变现有 Package 职责或技术栈。
- 不为了图形整齐引入新依赖。

## 具体要求

- `CLAUDE.md`、英文 README、中文 README 使用真实 Import 方向。
- `docs/architecture.md` 增加直接依赖允许矩阵。
- 明确 `apps/demo` 是装配层，可以依赖所有下层公开入口；下层不得反向依赖上层。
- 明确 `app_ui` 与 `app_core` 的基础层边界。

## 同时编写的测试

本任务为文档契约修正；结构化依赖图自动验证由 `repository-architecture-gates` 完成。

## 验收标准

- 三处依赖图和实际 Package 依赖一致。
- 文档不再使用含义不明的单向箭头。

## 验证命令

```bash
make harness-check
```

在 `harness-static-check` 完成前，使用本地 Markdown 链接和差异检查替代该占位命令。

## 风险与待决问题

无。
