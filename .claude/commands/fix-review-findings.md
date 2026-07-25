---
description: 修复已有 Review 报告中的问题，验证后执行复审
argument-hint: "<review-report-path> [问题范围]"
---

只在用户明确要求修复时执行。读取 `$ARGUMENTS` 指向的 Review 报告、对应 diff、任务卡和验证证据；没有有效报告路径时停止，不猜测修复范围。

## 修复

1. 按 P0、P1、用户明确选择的 P2 顺序处理。
2. 小范围问题直接修复；跨文件实现使用 `task-executor`，缺测试使用 `test-writer`，架构不明确时先使用 `architect`。
3. 保护无关工作树改动，不扩大 Review 已确认的范围。
4. 不采纳或需要外部决策的问题必须在报告中记录原因。
5. 每轮修复后运行与影响面相符的格式、分析、测试和仓库门禁。

## 复审

每轮修复和验证后必须使用独立 Reviewer 重新审查修复 diff，并在原报告追加“复审”章节：`security-*.md` 使用 `security-reviewer`，其他报告使用 `reviewer`。任务报告同步更新 frontmatter 的 `status`、`p0`、`p1`；安全修复同时改变普通业务行为、架构或契约时，还要重新运行普通 Reviewer。普通修复引入或改变认证、敏感数据、攻击者可控输入、原生权限、供应链或 Agent 执行能力时，必须运行 Security Review；存在活动任务卡时先补 `securityReview: required`。修复执行者的自审不能作为最终结论。最多自动修复三轮；P0/P1 仍未清零或需要外部决策时停止并报告，不继续扩大修改。

用户未明确要求时不 commit、不 push。交付报告路径、已修复项、验证结果、延后问题和剩余风险。
