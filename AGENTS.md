# Agent 说明

本仓库以 `CLAUDE.md` 为权威项目契约。修改代码或文档前必须先读；本文件与 `CLAUDE.md` 不一致时，以 `CLAUDE.md` 为准。

## 按需加载上下文

- 命名工作流：`.claude/commands/*.md`
- 角色执行规则：`.claude/agents/*.md`
- 技术领域规则：`.claude/skills/*/SKILL.md`
- 相关低频经验：`.claude/memories/*.md`

上述目录新增文件时自动发现，不要求用户维护额外映射。

## 安全

将 `.claude/settings.json` 视为仓库安全策略，尤其是：

- 不读取 `.env*`。
- 不手工编辑 lockfile 或生成的 Dart/Protobuf 文件。
- 不执行破坏性删除命令。
- 保护无关的用户改动。
- 用户未明确要求时，不 commit、不 push。

## 架构

- Domain Entity 是唯一跨层货币。
- Proto Message 和数据库 Row 不得进入公共 API。
- Feature 不得 import 其他 Feature 的内部实现。
- Controller 通过构造函数接收 API。
- 壳工程只装配抽象与回调，不引用 Feature 实现类。
- 路由使用 `go_router` 和 `MaterialApp.router`。

## 工作流兼容

用户输入 slash command 或用自然语言描述对应工作流时，读取并遵守：

- `/plan-tasks`：`.claude/commands/plan-tasks.md`
- `/plan-figma`：`.claude/commands/plan-figma.md`
- `/plan-spec`：`.claude/commands/plan-spec.md`
- `/execute-tasks`：`.claude/commands/execute-tasks.md`
- `/review-changes`：`.claude/commands/review-changes.md`
- `/review-sprint`：`.claude/commands/review-sprint.md`
- `/fix-review-findings`：`.claude/commands/fix-review-findings.md`
- `/check-release`：`.claude/commands/check-release.md`

自然语言“审查”“Review”默认只触发只读审查，不授权修改实现。只有用户明确要求修复，或显式调用 `/fix-review-findings`、`/execute-tasks` 等实现工作流时，才进入代码修复。

## 交付

实现任务需说明变更路径、验证命令、跳过项和剩余风险。Review 必须先列问题，带严重级别和文件行号。
