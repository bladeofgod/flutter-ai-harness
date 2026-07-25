---
description: 对明确范围执行独立只读安全审查，检查信任边界、敏感数据、外部输入、供应链和 Agent 能力变化
argument-hint: "<task-card-path|scope> [diff=<git-range|working-tree>]"
---

对 `$ARGUMENTS` 指定的任务、diff 或直接提供的代码执行只读安全审查。调用工作流可以运行非破坏性验证和写报告；`security-reviewer` 本身只读文件与原始证据，不执行命令，也不得修改实现、测试、配置或依赖。

## 输入模式

### 任务门禁

1. 任务卡路径存在时，读取完整任务、相关项目契约和测试证据，并将任务 slug 作为报告标识。
2. 使用调用方给出的 Git Range、工作树或文件列表；缺少可确定的范围时停止，不猜测历史 baseline。
3. 调用方识别本次实际审查的一个或多个仓库实现文件，并在审查完成后运行 `bash scripts/dart-tool.sh run tool/implementation_digest.dart <repository-relative-path>...`。
4. 写入 `docs/reviews/security-<task-slug>.md`；报告 frontmatter 包含 task、status、p0、p1、implementationFiles 和 implementationDigest。摘要必须与当前文件内容一致，否则不得通过归档。

### 独立审查

用户直接提供代码片段、设计、威胁模型或其他没有仓库文件的输入时也可以审查。此模式不强制绑定文件，默认在对话中返回结果；只有用户明确要求留档时才写入 `docs/reviews/security-<scope>.md`。这类报告必须声明输入范围，只覆盖当次输入，不使用任务 frontmatter，也不能作为任务归档门禁。

## 执行

1. 首轮使用 `security-reviewer` 独立审查，不向其提供普通 Review 结论。
2. 调用工作流只运行与安全假设直接相关的非破坏性验证，并把原始结果交给 Reviewer；不得让 Reviewer 自行执行 Bash。
3. 静态分析、测试或构建已经失败时准确记录，不用安全审查掩盖基础门禁失败。

## 报告

- 每条发现必须包含严重级别、资产、攻击者可控入口、危险操作或敏感数据路径、文件行号证据、影响和明确修法。
- 任务报告的 P0/P1 未清零时不得标记 `passed`；Security Review 后任一 implementationFiles 内容变化时必须重新审查并更新摘要。

需要修复时等待用户明确调用 `/fix-review-findings <security-review-path>`；由 `/execute-tasks` 调用时，沿用其已有实现授权和最多三轮修复限制。
