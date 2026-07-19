---
description: 执行已有任务卡，完成实现、验证、Review、修复和归档闭环
argument-hint: "<task-card-path>..."
---

执行 `$ARGUMENTS` 中的任务卡。只有实现、验证、Review、修复和复审全部完成，任务卡才算完成。

## 前置检查

1. 确认所有路径真实存在。
2. 编辑前完整阅读所有卡片。
3. 按声明依赖排序，再按文件名排序。
4. 阻塞项未解决或外部依赖缺失时停止。
5. 保护无关工作树改动，并将 diff 限定在当前卡范围。

## Executor 分流

- 缺少 `executor` 或值为 `task-executor`：使用 `task-executor`。
- 值为 `bridge-engineer`：使用 `bridge-engineer`，要求有契约文档并覆盖所有声明平台。
- 其他值：停止并报告无效任务卡。

如果标记为 `task-executor` 的任务涉及 MethodChannel/EventChannel wire 契约或多个原生平台同步修改，停止并要求改为 `bridge-engineer`。

## 单卡闭环

1. 严格按卡片范围实现代码和测试。
2. 格式化触碰的 Dart 文件。
3. 运行受影响静态分析、聚焦测试和 `make lint`。
4. 修改共享 Entity、公共包 API、协议生成、DI 装配、路由或平台契约时升级验证范围。
5. 通过 `scripts/quality/capture-evidence.sh` 把命令、退出码和脱敏后的完整输出写入 `docs/reviews/test-evidence/<task-basename>.log`；首条命令使用覆盖模式，后续命令使用 `--append`。不得直接重定向原始 stdout/stderr 到入库证据。
6. 同目录存在 `.spec.yaml` 时运行 `spec-auditor`。
7. 运行 `reviewer`，写入 `docs/reviews/execute-<task-basename>.md`。
8. 使用 `fix-review-findings` 修复 P0/P1，重新验证并复审。`execute-tasks` 已包含实现授权；自动修复最多三轮，超过后停止并请求用户决策。
9. 将完成任务和同名 spec/audit 文件移入 `docs/tasks/done/`。

归档前必须清零 P0/P1。P2 只有在记录负责人或 Follow-up 任务后才可延后。

## 硬约束

- 不 commit、不 push。
- 不绕过 hooks。
- 不手工编辑生成文件。
- 没有命令证据时不得宣称验证通过。
- 不删除无关文件，不覆盖已有工作。

## 交付

汇报完成卡片、变更路径、Review 报告、命令结果、延后问题、未验证平台和最终 `git status --short`。
