---
executor: task-executor
platforms: []
workKinds: [harness, documentation]
blockedBy:
  - migrate-harness-fixtures-to-dart-tests
  - remove-unused-workspace-dependencies
securityReview: required
---

# 建立有界测试证据与 CI 日志保留策略

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 5 项已确认方向。
- `scripts/quality/capture-evidence.sh` 当前把每条命令的完整脱敏 stdout/stderr 入库；
  `docs/reviews/test-evidence/` 现有 76 个日志约 8.1 MiB，单文件最高约 700 KiB。
- `scripts/quality/evidence-lint.sh`、`scripts/quality/test-evidence.sh`、Harness 归档证据检查和
  `.claude/commands/execute-tasks.md`。
- `.github/workflows/ci.yml` 当前运行 check/Android/iOS Job，但没有任务日志 Artifact 策略。

## 目标

- 入库证据只保留可审计的命令、工具版本、退出码、稳定测试摘要、必要失败片段和实现摘要，并设置可验证
  的大小上限。
- 将新的完整脱敏 CI 输出保存为固定 14 天的受限 Artifact，成功和失败 Job 都能取回；原始未脱敏输出
  始终只存在于临时目录。
- 保持任务归档、普通 Review、Security Review 和脱敏门禁使用同一证据事实来源。

## 非目标

- 不删除现有 `docs/reviews/test-evidence/` 文件，不重写 Git 历史。
- 不把 Artifact 当永久归档或任务完成的唯一证据；过期后入库摘要仍必须足以确认命令和结果。
- 不上传环境变量、凭据、签名、设备 ID、真实用户数据、原始媒体或未脱敏日志。

## 实现要求

1. 在 `CLAUDE.md` 文档生命周期和执行工作流中定义两层证据：入库 bounded summary 与 14 天完整脱敏 CI
   Artifact。明确本地执行没有 CI run 时只提交 summary，不伪造 Artifact URL/run ID。
2. 扩展采集器支持同一次命令生成完整脱敏临时日志和确定性 summary，且只执行命令一次。summary 至少
   包含 shell-safe 命令、明确工具版本、退出码、测试/构建计数或稳定成功行；失败保留首个根因和有界上下文，
   不保留无关进度噪声。
3. 为每条命令和整份入库日志设置有证据支撑的 byte/line 上限；超过时使用显式 truncation marker、原始
   行数/字节数和完整日志 SHA-256，不能静默截断。失败片段不得因上限丢失首个根因。
4. CI 的 check、Android、iOS 命令通过同一脱敏路径生成完整日志，并使用官方、固定 commit SHA 的 Artifact
   Action，以 `if: always()` 上传；`retention-days: 14`、名称含 Job/run attempt、无隐藏文件、找不到日志
   时失败关闭。Job 仍透传原命令退出码，上传步骤不能掩盖失败。
5. Harness 归档检查从“存在 Exit code”升级为校验 bounded evidence 必填段、上限、truncation metadata 和
   digest；evidence lint 同时扫描 summary 和准备上传的 Artifact，错误只报告文件与规则，不回显命中内容。
6. 更新 `capture-evidence`、执行工作流、README/相关文档为同一规则。不得同时保留“完整输出必须入库”的
   旧叙述。
7. Fixture 覆盖成功/失败、巨大输出、首因位于头/尾、CR/行尾、追加、多命令、digest、Artifact 缺失、
   `if: always()`/14 天/固定 SHA 漂移、敏感值和失败退出码透传。

## 验收与验证

- 新任务证据在固定上限内仍能独立判断每条命令、版本、结果和失败根因。
- CI 全量脱敏日志可在成功和失败 Job 后作为 14 天 Artifact 获取，过期不影响仓库内审计。
- 既有证据继续兼容且不被本任务改写或删除。

```bash
make format
make analyze
make evidence-test
make evidence-lint
make harness-check
make harness-test
make check
git diff --check
```

## 环境限制

本地验证只能静态检查 Workflow 与采集 Fixture；Artifact 上传和 14 天保留必须由真实 GitHub Actions run
证明。Action commit、Artifact 名称和 run link 不能在规划时伪造，执行证据应记录实际 run 或明确未验证。
