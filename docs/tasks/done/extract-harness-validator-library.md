---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy: []
securityReview: required
---

# 提取可导入的 Harness Validator Library

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 2 项已确认方案。
- `app/tool/harness_check.dart` 当前把 CLI 参数、进程退出和约 13,000 行 Validator 实现放在同一文件。
- `scripts/quality/test-harness.sh` 通过约 312 次独立 Dart 进程调用验证成功与失败 Fixture。
- `Makefile` 与根 `app/pubspec.yaml` 的 `harness-check`、`harness-test` 入口。

## 目标

- 把 Validator 提取为可由 Dart 测试直接调用的 library，并把现有 CLI 收敛为参数解析、结果输出和退出码
  映射的薄入口。
- 在迁移大批 Fixture 前建立稳定、无进程副作用的测试 API 和耗时基线。
- 保持现有合法状态、拒绝语义、诊断文案、CLI 用法和退出码完全兼容。

## 非目标

- 本卡不迁移 `test-harness.sh` 的完整成功/失败场景；该工作由依赖卡完成。
- 不因文件行数机械拆分类，不改变 Harness 校验强度、任务路由或安全策略。
- 不删除 Shell Fixture，不跳过 `make harness-test` 或 `make check`。

## 实现要求

1. 修改前在固定环境记录 `make harness-test` 的墙钟耗时、Dart/Flutter 版本、OS 和 Validator 调用次数；
   基线证据不得包含主机名、用户名或绝对路径。
2. 在根 Dart Package 中建立可导入入口，例如 `lib/harness_validator.dart` 与私有实现目录。公开 API 接受
   显式仓库根，返回不可变的验证结果和有序诊断，不调用 `exit`、不设置全局 `exitCode`、不直接打印。
3. 保持一次 `validate()` 调用覆盖当前 CLI 的全部阶段，保留确定顺序与 fail-closed 行为；I/O、JSON/YAML/
   XML 解析和实现摘要逻辑可以留在 library，但进程控制只能在 CLI。
4. `tool/harness_check.dart` 仅处理无参数与 `--root <path>` 两种既有形式、输出现有成功/错误前缀，并把
   usage error 映射为 64、校验失败映射为 1、成功映射为 0。
5. 为 library 增加聚焦 Dart 测试：合法最小根、多个错误的稳定顺序、重复调用无状态泄漏、路径带空格、
   CLI 成功/失败/usage 兼容。若新增 `package:test` 等根工具依赖，写入真实消费者的 `dev_dependencies`，
   通过生成命令更新 lockfile，不手工编辑。
6. 保持 `make harness-check` 和所有现有 Shell Fixture 调用方式不变，为后续同 VM 参数化迁移提供明确的
   fixture builder/session 扩展点，但不预置绕过完整 Validator 的测试专用分支。

## 验收与验证

- Library 测试可以在同一 Dart VM 中对多个 root 连续调用且不触发进程退出。
- CLI 的 stdout/stderr、退出码和调用参数与拆分前一致。
- 当前 Harness 正反 Fixture 数量、诊断和拒绝行为没有减少。

```bash
cd app && dart test test/harness_validator_test.dart
make format
make analyze
make harness-check
make harness-test
make check
git diff --check
```

## 环境限制

基线和拆分后复测必须使用同一机器、SDK、工作树状态和命令。耗时波动只记录，不把本卡的代码拆分误报为
完整性能收益；主要收益由后续 Fixture 迁移卡验收。
