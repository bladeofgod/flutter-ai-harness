---
task: bound-test-evidence-retention
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/bound-test-evidence-retention.md
  - CLAUDE.md
  - .claude/commands/execute-tasks.md
  - docs/review-checklist.md
  - .github/workflows/ci.yml
  - scripts/quality/capture-evidence.sh
  - scripts/quality/evidence-lint.sh
  - scripts/quality/test-evidence.sh
  - scripts/quality/summarize-evidence.rb
  - scripts/quality/validate-bounded-evidence.rb
  - scripts/quality/validate-evidence-workflow.rb
  - scripts/quality/test-harness.sh
  - app/lib/src/harness_validator.dart
  - app/tool/redact_evidence.dart
  - app/test/harness_validator_test.dart
implementationDigest: 62b60fbfd90c67e52ec3926e5e87e7795eca8b3133da822d4a2cc6322d39296c
---

# Security Review：建立有界测试证据与 CI 日志保留策略

## 首轮问题

### P2：Artifact 中间临时文件没有纳入中断清理

- 影响：原始和主要脱敏临时文件已由 EXIT trap 清理，但 `artifact_record` 在后半段动态创建；若进程恰好在
  组装 Artifact 时被中断，可能在系统临时目录留下完整脱敏日志副本。
- 修复：预先声明 `artifact_record`，统一 EXIT trap 在非空时精确删除，并在正常删除后清空变量；完整 Fixture
  与 evidence lint 复跑通过。

## 已检查边界

- 原始 stdout/stderr 只写权限受限的 `mktemp` 文件，所有退出路径由 trap 清理；仓库 summary 和 CI Artifact
  都先经过同一 redactor，不上传原始输出。
- Redactor/门禁覆盖用户目录、Xcode 设备、临时路径、Bearer/token/API key/password/private key及常见凭据
  形态；错误只指出文件和规则，不回显命中内容。
- CI Artifact 使用官方 Action 固定 commit SHA，`if: always()`、14 天、显式单文件、hidden files 关闭、
  missing file fail-closed；Job 原命令退出状态保留，上传不能把失败改成成功。
- Summary 的 output digest、原始/摘要计数、selection 和 truncation marker 由 Harness 与 evidence lint 独立
  复核，防止静默截断或手工篡改。
- 没有增加 workflow write permission、secrets 注入、外部网络目的地、签名、发布、Agent/MCP、commit 或 push
  能力。Artifact 的真实上传/14 天取回需 GitHub Actions run 验证，本地没有伪造 run 信息。

## 结论

首轮 P2 已关闭，最终 P0/P1/P2 为 0/0/0。完整脱敏 Artifact 仍可能包含未被模式识别的业务敏感文本，因此
限定为 CI 权限边界内的 14 天诊断材料；永久仓库只保留有界摘要。
