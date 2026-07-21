---
executor: task-executor
blockedBy: []
uiSpec: not-required
---

# Codex 原生资产适配

## 背景

Codex 会自动加载 `AGENTS.md`，原生发现 `.agents/skills/*/SKILL.md` 和 `.codex/agents/*.toml`，但不会原生扫描 `.claude/commands/`、`.claude/agents/` 或 `.claude/skills/`。当前仓库通过文字映射允许 Codex 手动读取这些资产，但无法获得 Skill description 隐式触发和项目 Agent 原生发现能力。

本任务建立生成式薄适配。Claude 资产继续作为唯一事实来源；Codex 目录只保存可重建、可静态校验的入口，不复制工作流或角色正文。

## 输入与事实来源

- `CLAUDE.md`
- `AGENTS.md`
- `.claude/commands/*.md`
- `.claude/agents/*.md`
- `.claude/skills/*/SKILL.md`
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`
- Codex Skill 与项目 Agent 当前发现约定

## 目标

- 将 `AGENTS.md` 收敛为只负责加载 `CLAUDE.md` 和相关 `.claude` 资产的薄入口。
- 将 Claude Skill 与 Command 生成成 Codex 原生 Skill 适配。
- 将 Claude Agent 生成成 Codex 项目 Agent TOML 适配。
- 提供确定性生成、只读检查和失败 Fixture，阻止缺失、过期、篡改及名称冲突。

## 非目标

- 不改变现有 Command、Agent 或 Skill 的业务语义。
- 不把 `.claude/memories/` 注册为 Codex Skill。
- 不依赖符号链接、自定义 Codex Slash Command 或用户级 `~/.codex` 配置。
- 不引入新的 Dart Package、Flutter 依赖、MCP Server 或运行时应用代码。
- 不 commit、不 push。

## 具体要求

1. `AGENTS.md` 只能保留 Codex 启动适配：要求开始任务前完整读取 `CLAUDE.md`，按任务加载 `.claude/commands/`、`.claude/agents/`、`.claude/skills/` 和 `.claude/memories/`，并声明冲突时以 `CLAUDE.md` 为准。
2. 新增 Dart 适配模块和命令入口，使用 `package:yaml` 解析 Claude Markdown 的 YAML frontmatter，不使用正则或字符串切片解析结构化字段。
3. 生成命令默认同步适配，`--check` 只读比较期望内容；支持 `--root <path>` 供 Fixture 使用。输入、输出顺序和文件内容必须确定。
4. `.claude/skills/<name>/SKILL.md` 生成 `.agents/skills/<name>/SKILL.md`：
   - 使用相同 `name` 和 `description`，使 Codex 支持隐式及显式 Skill 触发。
   - 正文只要求完整读取并遵守对应 Claude Skill，不复制规范正文。
5. `.claude/commands/<name>.md` 同样生成 `.agents/skills/<name>/SKILL.md`：
   - 使用 Command 文件名作为 Skill name，复用其 description。
   - 将当前用户输入视为 Command 的 `$ARGUMENTS`。
   - Command 与 Skill 名称冲突时必须失败，不静默覆盖。
6. `.claude/agents/<name>.md` 生成 `.codex/agents/<name>.toml`，至少包含 Codex 所需的 `name`、`description` 和 `developer_instructions`；详细行为通过指令读取对应 Claude Agent 文件，不复制正文。
7. 每个生成文件包含稳定来源和“不要手工编辑”标记。同步时只更新或删除带该标记的适配；同名非生成文件必须报错并保留。
8. 生成器同时维护 `AGENTS.md`。`--check` 必须拒绝入口内容漂移、缺少适配、内容不一致和仍存在的过期生成适配。
9. `harness_check.dart` 复用同一适配计算逻辑执行只读校验，禁止另写一套期望内容算法。
10. 增加 `make codex-adapters` 和 `make codex-adapters-check`；完整 `make check` 必须覆盖只读适配检查。
11. 更新 `CLAUDE.md` 和 README 中的资产说明，明确事实来源、生成目录、生成命令和 Codex 调用方式；不得把生成目录描述为第二事实源。
12. 不修改现有 `.claude` 资产正文来迎合适配器；只有发现无效或缺失的必需 frontmatter 时才允许同任务修正。
13. 所有受管输出路径必须拒绝符号链接和仓库外逃逸；同步必须先完成全量预检，并在写入失败时恢复同步前状态。
14. 只读检查兼容 Git 的 CRLF 工作区换行；Command 适配必须保留 `argument-hint`，并明确显式调用与语义触发时 `$ARGUMENTS` 的提取规则。

## 同时编写的测试

- 扩展 Harness 失败 Fixture，先为有效 Fixture 生成 Codex 适配，再验证有效状态通过。
- 至少覆盖：篡改生成 Skill、缺失生成 Agent、过期生成适配、同名非生成文件冲突，以及 `AGENTS.md` 漂移。
- 验证同步命令可以恢复可修复的生成内容，但不会覆盖同名非生成文件。
- 验证符号链接无法把检查或同步引向仓库外路径，CRLF checkout 不产生虚假漂移。
- 验证同步失败不会留下部分写入或提前删除过期适配。
- 验证生成的 Command Skill 包含原始 `argument-hint` 和 `$ARGUMENTS` 提取约定。

## 验收标准

- 所有现有 Claude Skill 和 Command 都有名称一致的 Codex 原生 Skill 适配。
- 所有现有 Claude Agent 都有名称一致的 Codex 项目 Agent 适配。
- 适配文件只包含元数据、来源和加载指令，没有复制正文。
- 修改 Claude description 后，`--check` 与 `make harness-check` 都会失败，重新同步后恢复通过。
- 删除或重命名 Claude 资产后，不会遗留通过门禁的过期生成适配。
- `AGENTS.md` 不再重复 `CLAUDE.md` 的安全、架构、工作流和交付规则。
- `pre-push` 以轻量只读检查阻止未同步的 Codex 适配进入远端。
- `make check` 通过。

## 验证命令

```bash
make codex-adapters
make codex-adapters-check
make harness-check
make harness-test
make check
git diff --check
```

## 平台或环境限制

纯 Harness 与 Dart Tooling 任务，不需要 Android/iOS 设备、Figma MCP 或 Marionette。适配不得依赖 POSIX 符号链接行为，必须能由仓库锁定的 Dart SDK 在 macOS、Linux 和 Windows 文件系统上重建。

## 风险与待决问题

- Codex 通过 `$skill-name` 或语义匹配调用工作流，不保证支持 Claude 的 `/command` UI 语法；README 必须准确说明差异。
- Codex Agent TOML 属于工具入口配置，具体是否自动委派仍受用户请求、运行模式和并发策略约束。
- 新增手写 `.agents/skills` 或 `.codex/agents` 资产时必须避免与 Claude 源名称冲突。

## 完成记录

- 2026-07-21：提交后独立审查发现路径逃逸、CRLF 漂移、同步事务性、Command 参数映射和 pre-push 覆盖缺口，任务重新移入进行中目录。
- 2026-07-21：全部问题修复并由独立 agent 复审，P0/P1/P2 均为 0，任务重新归档。
- Review：[`execute-codex-native-adapters.md`](../../reviews/execute-codex-native-adapters.md)
- 测试证据：[`codex-native-adapters.log`](../../reviews/test-evidence/codex-native-adapters.log)
