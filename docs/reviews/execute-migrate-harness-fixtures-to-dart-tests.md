---
task: migrate-harness-fixtures-to-dart-tests
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：将 Harness Fixture 迁移为参数化 Dart 测试

## 结论

- legacy Shell 的 578 个校验状态已生成稳定 inventory 和参数化 catalog：37 个合法、541 个非法；case ID、
  mutation、call site 和完整有序诊断一一对应且唯一。
- 613 个去重 blob 使用 `SHA-256.gz` 存储，catalog 只引用 digest；加载时验证相对安全路径、blob 存在性、
  解压后 SHA-256，并为每个 case 建立独立的含空格临时 root和确定性清理。
- 578 个 case 在同一 Dart VM 中调用完整 `validateHarness(root)`；没有直接调用私有子校验，也没有 skip、
  focus 或生产绕过参数。
- Shell 保留 Fixture capture/legacy inventory 生成能力；公共 `make harness-test` 只运行 inventory、catalog、
  Validator/CLI smoke，不再执行 573 次 Validator 子进程。
- CLI smoke 保留默认 root、`--root`、带空格 root、usage 64、validation failure 1 和 success 0；Repository
  smoke 继续校验真实工作树。

## 性能目标

前置 Library 卡记录 legacy 完整 Shell 为 573 次 Validator 进程调用，同机基线 977.10 秒。首轮参数化迁移
运行约 66.20 秒后，基于实测而非规划值将验收目标定为：相同环境三次完整 `make harness-test` 中位数不超过
75 秒，同时 578 个 catalog case 和 CLI smoke 全部通过。

任务图、Security binding 与 Repository smoke 全部闭合后，三次完整结果为 66.88 秒、66.87 秒、66.86
秒，每轮 1172 tests 全部通过；中位数 66.87 秒，满足不超过 75 秒的目标。相对 977.10 秒 legacy 基线减少
910.23 秒（93.16%，约 14.61x）。剩余主要耗时是 578 个隔离文件树的完整 Validator 校验，不再是 573 次
Dart 进程启动。

## 验证范围

- inventory 测试逐项校验 call site 仍指向 `run_check`，防止 legacy 场景被删除或重排后静默漏测。
- catalog 测试逐项精确比较完整有序 diagnostics 和 `isValid`。
- Validator 测试还覆盖独立合法 root、诊断不可变、同 VM root 间无状态泄漏、当前仓库 smoke，以及六种
  generator drift mutation。

最终有界命令与三次计时见[测试证据](test-evidence/migrate-harness-fixtures-to-dart-tests.log)。复审未发现
P0/P1/P2。性能数据来自当前 macOS 26.2 arm64、Flutter 3.41.9 / Dart 3.11.5 本机，不外推为 Linux CI
的绝对秒数。
