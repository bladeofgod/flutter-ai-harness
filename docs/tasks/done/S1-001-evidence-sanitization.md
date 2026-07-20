---
executor: task-executor
blockedBy: []
---

# S1-001 测试证据脱敏与门禁

## 背景

`execute-tasks` 要求提交完整命令证据，但 Flutter/Pub 输出会包含本机绝对路径，也可能出现凭据形态。证据必须继续保留，同时满足仓库隐私规则。

## 输入与事实来源

- `docs/reviews/harness-baseline.md` P1-3
- `.claude/commands/execute-tasks.md`
- `README.md`
- `CLAUDE.md` 安全策略

## 目标

提供统一命令采集、脱敏和 evidence lint，使任务执行可以保存命令、退出码和输出，而不提交本机用户目录或常见凭据值。

## 非目标

- 不忽略或删除测试证据。
- 不宣称能识别所有可能的敏感业务数据。
- 不记录环境变量全集。

## 具体要求

- 新增证据采集脚本，支持首次写入与追加命令记录，并保留原命令退出码。
- 将仓库路径、用户主目录和常见平台用户目录替换为稳定占位符。
- 遮蔽 Authorization、Token、Password、Secret、API Key、常见访问 Token 和私钥块。
- 新增 evidence lint，扫描 `docs/reviews/test-evidence/*.log`。
- 更新 `/execute-tasks` 和仓库 README，要求通过采集器写证据。

## 同时编写的测试

- 验证普通输出被保留。
- 验证本机路径和伪凭据被遮蔽。
- 验证追加模式。
- 验证失败命令的退出码透传。

## 验收标准

- Fixture 中的路径和伪凭据不会出现在产物中。
- evidence lint 拒绝未脱敏日志。
- 失败命令仍生成证据且调用方收到非零退出码。

## 验证命令

```bash
make evidence-test
make evidence-lint
```

## 风险与待决问题

日志中自由文本形式的用户数据仍依赖任务设计和 Review；自动门禁只兜底稳定模式。
