---
task: fix-hook-fixture-safe-cleanup
status: passed
p0: 0
p1: 0
---

# Review：Git Hook Fixture 安全清理

## 结论

P0/P1/P2 均为 0，任务通过。

## 审查范围

- `scripts/git-hooks/safe-fixture-cleanup.sh`
- `scripts/git-hooks/test-safe-fixture-cleanup.sh`
- `scripts/git-hooks/test-pre-commit.sh`

## 审查结果

- 主测试在安装 EXIT trap 前记录 `mktemp` 路径、物理路径和物理父目录，清理时重新核对三者。
- 清理只接受固定六字符后缀的 `flutter-ai-harness-hook.*` 目录，并拒绝空值、相对路径、根符号链接、
  非目录、前缀漂移和物理路径漂移。
- `find -P ... -depth -delete` 不跟随目录内符号链接；Fixture 证明外部 marker 保持存在，且只读 Git object
  不再触发交互询问。
- EXIT trap 保留测试主体原退出码；只有主体成功而清理失败时才把结果提升为失败。
- 其它使用 `rm -r` 的 Fixture 未创建只读 Git object，当前没有同类可复现证据，因此未做批量改写。

## 验证

完整输出见 `docs/reviews/test-evidence/fix-hook-fixture-safe-cleanup.log`。最终记录中：

- Shell 语法、聚焦安全清理 Fixture、`make hook-test`：通过。
- macOS 伪终端与关闭 stdin 的复测：无 `override ...?` 且 Hook Fixture 完成。
- `make harness-check`、`git diff --check`、完整 `make check`：通过。

证据中的初始非零用于证明旧实现可复现交互询问；另一次非零来自复测包装脚本匹配了错误的完成文案，
修正断言后同一伪终端路径已通过，不是实现回归。
