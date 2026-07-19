---
executor: task-executor
blockedBy: [S1-001, S1-003, S1-004]
---

# S1-005 增加 Harness 自检并接入完整门禁

## 背景

`make check` 当前主要验证 Dart 代码，没有验证 AI Harness 的 JSON、frontmatter、引用、文档链接和 Shell 语法，也未运行 `proto-check`。

## 输入与事实来源

- `docs/reviews/harness-baseline.md` P1-5
- `CLAUDE.md` AI 工程资产与验证规则
- `.claude/`、`.mcp.json`、`Makefile`、`scripts/`

## 目标

建立可重复的 `harness-check`，并让 `make check` 覆盖 Harness、Proto、证据、架构和应用测试。

## 非目标

- 不连接需要用户批准的 MCP Server。
- 不在快速门禁中启动模拟器或执行移动端集成测试。
- 不把占位 Proto 生成器伪装成已实现。

## 具体要求

- 校验 `.claude/settings.json`、`.mcp.json`、`.fvmrc` JSON。
- 校验 Skill/Agent/Command frontmatter 必填字段、命名和 Skill `paths`。
- 校验命名工作流中的 Agent/Skill/Command 引用存在。
- 校验仓库内 Markdown 相对链接。
- 对 Shell 脚本和 Git hooks 运行 `bash -n`。
- 校验声明的 Android/iOS 宿主文件存在。
- 把 `harness-check`、`evidence-lint` 和 `proto-check` 纳入 `make check`/Melos check。
- 为失败场景提供 Fixture 或聚焦测试。

## 同时编写的测试

- 无效 frontmatter 拒绝。
- 断链 Markdown 拒绝。
- 缺少平台宿主拒绝。
- 当前仓库通过。

## 验收标准

- `make check` 一条命令覆盖上述门禁。
- Proto 不存在时明确跳过；一旦出现 Proto 且生成链路未建立，完整门禁失败。
- Harness 校验器自身有稳定回归测试。

## 验证命令

```bash
make harness-test
make check
```

## 风险与待决问题

MCP 连接状态属于用户本地运行态，只检查静态配置，不作为仓库门禁。
