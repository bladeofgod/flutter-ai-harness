---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy: []
securityReview: required
---

# 修复 Git Hook Fixture 的非交互安全清理

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 1 项已确认方案。
- `scripts/git-hooks/test-pre-commit.sh` 当前通过 `mktemp -d` 创建临时 Git 仓库，并在 `EXIT` trap 中执行
  `rm -r`。
- `scripts/quality/media-capture-ios.sh` 和 `scripts/install-ripgrep.sh` 已使用
  `find -P <validated-root> -depth -delete` 清理自建临时目录。
- 审查实测：macOS 交互式 TTY 会对临时仓库的只读 Git object 逐项询问，导致 `make check` 挂起。

## 目标

- 让 Hook Fixture 在交互式和非交互式终端都能无提示退出。
- 只删除当前脚本本次创建、且经过真实路径和命名前缀校验的临时目录。
- 保持 Hook 安装冲突、pre-commit 暂存区和 pre-push 门禁的现有断言不变。

## 非目标

- 不修改真实仓库 Hook，不删除或放宽现有 Hook Fixture。
- 不批量改写其它临时目录脚本；只读审计后仅修复能够复现同类只读文件提示的问题。
- 不使用 `rm -rf`，不跟随符号链接，不扩大删除根目录。

## 实现要求

1. 在创建 Fixture 后立即记录预期临时父目录、`mktemp` 返回路径和 `pwd -P` 解析结果；清理前重新校验值
   非空、为绝对路径、目录本身不是符号链接，且真实路径仍位于预期临时父目录并匹配
   `flutter-ai-harness-hook.*` basename。
2. 校验通过后使用 `find -P "$FIXTURE_ROOT" -depth -delete`。路径验证失败时拒绝删除并输出固定、脱敏
   诊断；不得回显用户主目录或把未解析变量交给删除命令。
3. cleanup 必须处理部分初始化、重复调用和已不存在目录；测试主体已失败时保留原失败语义，测试主体成功
   但清理失败时返回非零。
4. 为只读 `.git/objects`、目录内符号链接、篡改/不符合前缀的清理目标增加 Fixture。符号链接目标必须
   保持原样，非法根目录必须被拒绝。
5. 审计其它 Fixture cleanup，只在测试能证明相同 TTY 挂起且能复用同一安全边界时纳入本卡；否则记录
   审计结论，不做无证据改写。

## 验收与验证

- 有只读 Git object 时清理不读取 stdin、不输出 `override ...?`，目录最终删除。
- 非法或符号链接根目录不触发删除；目录内符号链接不会导致外部目标被遍历。
- 现有 Hook 行为断言和完整质量门禁保持通过。

```bash
bash -n scripts/git-hooks/test-pre-commit.sh
make hook-test
make harness-check
make check
git diff --check
```

## 环境限制

至少在 macOS/BSD `find` 的本地环境复测一次交互式问题；Linux CI 继续证明脚本兼容性。没有可用 TTY 时，
必须运行只读 object 与关闭 stdin 的自动化 Fixture，并准确记录未执行的交互式复测。
