---
task: fix-hook-fixture-safe-cleanup
status: passed
p0: 0
p1: 0
implementationFiles:
  - scripts/git-hooks/safe-fixture-cleanup.sh
  - scripts/git-hooks/test-safe-fixture-cleanup.sh
  - scripts/git-hooks/test-pre-commit.sh
implementationDigest: af9fca3eddf19b2bd734ee7b933f6d16da3a88cd74286734ef77251d706457af
---

# Security Review：Git Hook Fixture 安全清理

## 结论

P0/P1/P2 均为 0，安全审查通过。

## 信任边界

- 删除目标只能来自当前进程调用 `mktemp -d` 创建的目录。
- `TMPDIR` 可以改变临时父目录，但脚本立即记录其物理父目录和新目录物理路径；后续不能借此扩大到
  其它目录。
- 目录内容可能包含只读 Git object 和符号链接，因此删除实现必须拒绝根链接并禁止遍历内部链接。

## 审查结果

- 删除前验证参数非空且为绝对路径、根存在且不是符号链接、根是目录、basename 使用固定前缀和六字符
  `mktemp` 后缀、物理根与创建时记录完全一致、物理父目录与创建时记录完全一致。
- 删除命令接收已验证的物理根，不使用 glob、未解析环境变量或命令拼接；`find -P` 明确禁止跟随链接。
- 非法目标 fail closed，只输出固定脱敏诊断，不回显用户目录、临时路径或 Git object 内容。
- 清理失败不会被 EXIT trap 吞掉，测试主体失败也不会被成功清理覆盖。
- 测试覆盖根符号链接、内部符号链接、前缀漂移、预期路径漂移、只读文件和重复调用。

## 剩余风险

同一 OS 用户已经拥有临时目录及仓库文件权限；不存在由该测试脚本新增的跨用户权限提升。临时目录由
`mktemp -d` 创建且内部链接不被遍历，未发现可把删除范围扩大到仓库或其它用户数据的路径。
