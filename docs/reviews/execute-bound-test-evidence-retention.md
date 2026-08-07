---
task: bound-test-evidence-retention
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：建立有界测试证据与 CI 日志保留策略

## 结论

- `capture-evidence.sh` 每条命令只执行一次，原始 stdout/stderr 仅在受限临时文件中存在；随后经统一 Dart
  redactor 生成仓库内 `bounded-v1` summary，并可同时生成 `redacted-full-v1` CI Artifact。
- 每条 summary 上限 65,536 bytes/600 lines，整份 evidence 上限 524,288 bytes/4,800 lines。记录 command、
  工具版本、退出码、原始/摘要字节与行数、完整输出 SHA-256、选择策略和显式 truncation marker。
- 成功摘要保留稳定完成/计数行；失败摘要保留首个根因及有界上下文。追加模式支持多命令，并独立校验每个
  record 的 metadata 与实际摘要计数。
- evidence lint 同时检查 bounded 结构、用户目录、Xcode 设备、临时路径、凭据/私钥形态；只报告文件与规则，
  不回显敏感命中内容。既有历史 evidence 保持兼容且未被改写或删除。
- GitHub Actions 的 check/Android/iOS Job 使用同一采集器，完整脱敏日志以固定 commit SHA 的官方
  `actions/upload-artifact`、`if: always()`、`retention-days: 14`、Job/run attempt 唯一名称上传；显式单文件、
  不含 hidden files、缺失即失败，原命令退出码不被上传步骤掩盖。
- 本地没有真实 GitHub Actions run，因此没有伪造 Artifact URL/run ID；14 天上传/取回仍是明确的真实 CI
  验证项。

## 验证

Fixture 覆盖成功、失败、巨大输出、根因在头/尾、CR/行尾、追加、多命令、digest/计数篡改、Artifact、
敏感值、退出码透传，以及 Workflow 的 always/retention/action SHA/缺失策略漂移。`make evidence-test`、
`make evidence-lint` 和 Workflow validator 均退出 0。

完整命令摘要见[测试证据](test-evidence/bound-test-evidence-retention.log)。复审未发现 P0/P1/P2。
