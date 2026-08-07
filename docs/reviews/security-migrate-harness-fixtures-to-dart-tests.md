---
task: migrate-harness-fixtures-to-dart-tests
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/migrate-harness-fixtures-to-dart-tests.md
  - Makefile
  - scripts/quality/test-harness.sh
  - scripts/quality/run-harness-tests.sh
  - app/tool/harness_validation_server.dart
  - app/test/support/harness_fixture_catalog.dart
  - app/test/harness_fixture_inventory_test.dart
  - app/test/harness_fixture_catalog_test.dart
  - app/test/harness_validator_test.dart
  - app/test/fixtures/harness_fixture_inventory.jsonl
  - app/test/fixtures/harness_cases/cases.jsonl
  - app/pubspec.yaml
  - app/pubspec.lock
implementationDigest: 1aa0f0055c43d43ecfc714b48f7bbda4bd2ec7d96f30aa3f34656f2190c68384
---

# Security Review：将 Harness Fixture 迁移为参数化 Dart 测试

## 已检查边界

- Catalog 路径必须为非空仓库相对路径，拒绝绝对路径、反斜线、空 segment 和 `..`；每个 case 只在独立
  系统临时父目录下物化，完成后递归清理其精确父目录。
- Blob 文件名必须是小写 SHA-256，解压后重新计算 digest；catalog mutation 只能引用存在且内容匹配的 blob。
  `cases.jsonl` 自身绑定全部 blob digest，Security implementation binding 无需列出 613 个机械文件名。
- Capture 仅由显式 `HARNESS_FIXTURE_CAPTURE_DIRECTORY` 开启，要求绝对且目标目录不存在，不覆盖既有目录；
  snapshot 使用 `followLinks: false`，保留 symlink 作为待 Validator 检查的实体。
- 参数化测试仍调用公开完整 Validator，不提供跳过安全、Schema、Capability、Wire、Host、依赖或安全审查
  子校验的入口；各 root 间状态隔离测试已通过。
- Fixture 内容是仓库测试数据，不包含凭据、用户数据或媒体；未增加网络、外部命令、权限、Agent/MCP、CI
  token、签名、发布、commit 或 push 能力。

## 结论

P0/P1/P2 为 0/0/0。迁移减少进程启动但没有缩减校验语义；legacy Shell capture 只用于受审计的 corpus 更新，
日常 `make harness-test` 不启用写入模式。
