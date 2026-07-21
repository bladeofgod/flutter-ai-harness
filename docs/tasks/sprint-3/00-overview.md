# Sprint 3 Codex 原生适配

## 范围

本 Sprint 将 Claude 优先的 Harness 资产以生成式薄适配暴露给 Codex 原生发现机制，同时保持 `CLAUDE.md`、`.claude/commands/`、`.claude/agents/` 和 `.claude/skills/` 为唯一事实来源。

## 输入与事实来源

- `CLAUDE.md` 与 `AGENTS.md`：当前项目契约和 Codex 入口。
- `.claude/commands/`、`.claude/agents/`、`.claude/skills/`：现有 Claude 原生资产。
- Codex 当前约定：仓库 Skill 从 `.agents/skills/*/SKILL.md` 发现，项目 Agent 从 `.codex/agents/*.toml` 发现。
- 用户批准决策：使用薄适配解决原生发现，不人工维护重复正文。

## 依赖顺序

```text
S3-001 Codex 原生资产适配
```

## 里程碑

1. 将 `AGENTS.md` 收敛为指向 `CLAUDE.md` 的生成式入口。
2. 让 Claude Skill 和 Command 作为 Codex 原生 Skill 被发现。
3. 让 Claude Agent 通过 Codex 项目 Agent 配置被发现。
4. 建立可重复生成和静态漂移门禁。

## 风险

- 直接复制正文会形成双份维护，必须由生成器保证适配内容确定且可校验。
- 符号链接在部分 Git/Windows 环境中不可移植，本 Sprint 不采用符号链接。
- `.claude/memories/` 是低频上下文，不应全部注册为 Skill 并占用初始发现预算。

## 待决事项

无。新增 Codex 专属 Skill 或 Agent 时，可使用非生成文件扩展，但不得覆盖生成器管理的同名路径。
