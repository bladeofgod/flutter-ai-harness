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

- 缺少 `executor`：停止并报告无效任务卡，不猜测执行角色。
- 值为 `task-executor`：使用 `task-executor`。
- 值为 `bridge-engineer`：使用 `bridge-engineer`，要求有契约文档并覆盖所有声明平台。
- 其他值：停止并报告无效任务卡。

如果标记为 `task-executor` 的任务涉及 MethodChannel/EventChannel wire 契约或多个原生平台同步修改，停止并要求改为 `bridge-engineer`。

## 单卡闭环

1. 严格按卡片范围实现代码和测试。
2. 格式化触碰的 Dart 文件。
3. 通过 `scripts/quality/capture-evidence.sh` 直接执行受影响静态分析、聚焦测试和 `make lint`，把命令、退出码和脱敏后的完整输出写入 `docs/reviews/test-evidence/<task-slug>.log`；首条命令使用覆盖模式，后续命令使用 `--append`。不得先裸跑再为留证重复执行，也不得直接重定向原始 stdout/stderr 到入库证据。
4. 修改共享 Entity、公共包 API、协议生成、DI 装配、路由或平台契约时升级验证范围。
5. 运行 `reviewer`，写入 `docs/reviews/execute-<task-slug>.md`；报告 frontmatter 必须包含与任务文件 basename 一致的 `task` slug、`status` 和当前未解决的 `p0`、`p1` 数量。
6. 判断是否需要 Security Review。任务声明 `securityReview: required` 时必须执行；未声明但实际 diff 引入或改变下列任一边界时，先把该字段补入活动任务卡再执行：
   - 认证、会话、授权、用户数据隔离、凭据、隐私数据或安全存储。
   - 网络、文件、Deep Link、WebView、不可信输入反序列化或其他攻击者可控输入。
   - MethodChannel/EventChannel、原生权限、Manifest、Entitlements 或平台安全配置。
   - 第三方依赖、GitHub Action、构建/安装/生成脚本或依赖来源。
   - `.claude/settings.json`、MCP、CI 权限，或 Command/Agent/Skill、适配生成器与脚本中会改变读写、命令、网络、凭据、提交或发布能力的执行语义；纯描述修正和未改变能力的生成适配同步不触发。
7. 需要时由调用工作流运行必要的只读验证，再调用没有 Bash/写入能力的 `security-reviewer`；写入 `docs/reviews/security-<task-slug>.md` 时列出实际审查的 implementationFiles，并用 `implementation_digest.dart` 生成 implementationDigest。其首轮必须与普通 Review 保持独立，不读取普通 Reviewer 结论；不需要时不生成跳过报告。
8. 使用 `fix-review-findings` 修复全部适用报告中的 P0/P1，重新验证，并由各报告对应的 Reviewer 复审；任一修复改变了另一审查维度的代码时，两类 Reviewer 都必须复审。`execute-tasks` 已包含实现授权；自动修复最多三轮，超过后停止并请求用户决策。
9. 将完成任务卡移入 `docs/tasks/done/`，并更新 Review 和其他仓库内任务引用。UI Spec、Audit、App Operator 报告不属于任务归档产物，不得随任务移动。
10. 归档完成后重新运行 `make harness-check`；归档任务缺少已完成依赖、通过的普通 Review、要求的 Security Review、匹配当前实现的安全摘要或测试证据时门禁必须失败。

归档前必须清零 P0/P1。P2 只有在记录负责人或 Follow-up 任务后才可延后。

## 硬约束

- 不 commit、不 push。
- 不绕过 hooks。
- 不手工编辑生成文件。
- 没有命令证据时不得宣称验证通过。
- Security Review 只按任务标记或实际安全边界变化触发；不得把普通 UI、文案、格式化或不改变行为的重构升级为安全门禁。
- 不删除无关文件，不覆盖已有工作。
- 不自动生成 UI Spec/Audit，不调用 App Operator；这些能力只由人通过独立 UI 自动化流程安排。

## 交付

汇报完成卡片、变更路径、Review 报告、命令结果、延后问题、未验证平台和最终 `git status --short`。
