---
task: extract-harness-validator-library
status: passed
p0: 0
p1: 0
---

# Review：提取 Harness Validator Library

## 首轮问题

### P1：聚焦测试未锁定兼容契约

- 影响：Validator 诊断文案或顺序发生一致漂移、CLI 无参数入口回归时，现有测试仍可能通过；
  真实工作树也不是独立的合法最小 Fixture。
- 证据：`app/test/harness_validator_test.dart` 的成功用例直接校验当前仓库；错误用例只比较
  两次运行彼此相等，CLI 失败只断言 `错误：` 前缀，且没有无参数用例。
- 修法：增加确定性的独立 Fixture builder；对固定失败 Fixture 断言完整有序诊断和完整
  stderr；增加 CLI 无参数成功用例。

### P2：基线证据把源码行数当作 Validator 实际调用次数

- 影响：`rg -c "run_check"` 会计入函数声明，也无法展开循环，不能证明拆分前后的
  运行负载一致。
- 修法：在 `run_check` 运行时入口中累计每次真实调用，在 Harness 测试成功后输出计数；
  后续证据使用运行时计数而非源码匹配。

## 验证缺口

首轮审查时，证据尚未包含最终聚焦 Dart 测试、`make format`、`make analyze`、
`make harness-check`、`make check` 和 `git diff --check`。

## 修复与复审

- P1 已修复：Shell 在首个合法正例处可导出独立的 64 文件 Fixture，Dart builder 负责
  受控临时目录校验、case 副本和清理。测试对固定双缺失 mutation 断言两条完整有序
  诊断和完整 CLI stderr，并覆盖 `--root`、无参数、失败和 usage 退出码。
- P2 已修复：`run_check` 运行时入口在 `mktemp` 父目录中计数，完整 Fixture 实测为
  573 次。首轮 `rg` 结果 312 只是源码行数，明确作废，不再用于前后负载比较。
- 最终证据中聚焦 Dart 测试 8 项通过；`make format`、`make analyze`、
  `make harness-check`、`make harness-test`、`make check` 和 `git diff --check` 均为退出码 0。

复审未发现新的 P0/P1。Shell 仍保留 573 次进程调用，属于依赖卡
`migrate-harness-fixtures-to-dart-tests` 的已知性能工作，不是本卡的剩余正确性问题。
