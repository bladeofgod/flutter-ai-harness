---
task: harness-static-check
status: passed
p0: 0
p1: 0
---

# Review：Harness 静态自检与完整门禁

## 结论

P0/P1/P2 均为 0，任务通过。

## 审查结果

- JSON 校验覆盖 Claude settings、MCP 配置和 FVM 版本文件。
- Agent、Command、Skill frontmatter 校验名称、必填字段和 Skill `paths`/描述标记。
- 命名工作流引用同时识别 Agent、Command、Skill 与 MCP Server，不把 `figma` 误判为 Agent。
- 任务卡 `executor` 会校验对应 Agent 是否存在。
- Markdown 本地链接支持普通目标、尖括号目标、Anchor 和可选 Title。
- Shell 脚本与 Git hooks 通过 `bash -n`。
- Android/iOS 必需宿主文件会校验存在，iOS Development Team 会被拒绝。
- 私有路径扫描限定文本文件，Skill/docs 后续加入二进制资源不会触发解码崩溃。
- `make check` 与 Melos check 都包含 Harness、架构、证据、Proto、测试及各自 Fixture。
- `yaml` 作为校验器真实消费者的直接 Dev Dependency 加入，lockfile 由 `dart pub get` 更新。

## 验证

完整输出见 `docs/reviews/test-evidence/harness-static-check.log`：

- `make harness-test`：无效 frontmatter、断链、失效 Agent 引用和缺失平台宿主 Fixture 均被拒绝。
- `make check`：通过；12 个 Dart 文件格式正确，Analyze 无问题，全部 Harness/架构/证据 Fixture 通过，2 个 Widget 测试通过。
- `proto-check`：当前无 Proto，按占位约定明确跳过；未来出现 Proto 且生成链路未完成时会阻断完整门禁。
- evidence lint：全部任务证据通过。

## 剩余风险

- Harness Check 是静态校验，不连接需要用户批准的 Figma/Marionette MCP。
- Markdown 校验确认目标文件存在，不验证 Anchor 标题是否存在。
- ShellCheck/shfmt 仍不是仓库前置依赖；当前使用 `bash -n` 和行为 Fixture。

## 聚合复审

首次执行 `dart run melos run check` 时发现脚本内部调用裸 `melos`，在未全局安装 Melos 的环境返回 `command not found`。已将 Melos `check` 改为 `make -C .. check`，由根 Makefile 作为唯一完整门禁事实源；重新执行 `dart run melos run check` 退出码为 0。该修复未放宽任何门禁。
