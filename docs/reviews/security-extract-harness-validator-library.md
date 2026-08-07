---
task: extract-harness-validator-library
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/lib/harness_validator.dart
  - app/lib/src/harness_validator.dart
  - app/lib/src/codex_adapters.dart
  - app/lib/src/implementation_digest.dart
  - app/tool/harness_check.dart
  - app/tool/codex_adapters.dart
  - app/tool/implementation_digest.dart
  - app/test/harness_validator_test.dart
  - scripts/quality/test-harness.sh
implementationDigest: 70e98a40b379ff4d194d0dfed5746169b44e426a0c4af5f72b3a0c4412b462f0
---

# Security Review：提取 Harness Validator Library

## 首轮问题

### P1：历史 Security Review 必须迁移 Validator 实现绑定

- 资产：12 份历史安全报告保护的 Media Capture、Harness 与 Agent 安全不变量。
- 入口与路径：真实 Validator 主体已从 `app/tool/harness_check.dart` 移至
  `app/lib/src/harness_validator.dart`；门禁只按报告 `implementationFiles` 计算摘要。
- 影响：如果只用旧清单重算摘要，今后削弱实际 Validator 不会使这些报告失效。
- 修法：保留薄 CLI 和 Shell Fixture 绑定，并在相关报告增加公开入口、真实 Validator
  与摘要计算器；Native Harness 报告还需绑定迁移后的 Adapter 实现。

## 已检查边界

- Library 只返回不可变有序诊断，不输出、不退出进程。
- CLI 只用参数数组处理 root，没有 Shell 插值；`bash -n <file>` 子进程为既有行为。
- `crypto`/`xml`/`yaml` 仅从直接 dev 依赖转为直接 main 依赖，`test` 从传递依赖转为
  直接 dev 依赖；版本、来源和摘要未变。
- 未修改 Agent、MCP、凭据、网络或发布能力。

## 验证缺口

完成历史绑定迁移后，需重跑聚焦 Dart 测试、`make harness-check`、`make harness-test`、
`make check` 和 `git diff --check`。

## 修复与安全复审

- 12 份原本绑定 `app/tool/harness_check.dart` 的历史报告已保留薄 CLI 与 Shell Fixture，
  并新增 `app/lib/harness_validator.dart`、`app/lib/src/harness_validator.dart` 和
  `app/lib/src/implementation_digest.dart`；Native Harness 报告额外绑定
  `app/lib/src/codex_adapters.dart`。
- 每份报告的摘要都由 `tool/implementation_digest.dart` 按新清单重算；`make harness-check`
  已验证全部归档任务绑定与当前实现一致。
- 聚焦 Dart 测试、完整 573 次 Harness Fixture、`make check` 和 `git diff --check`
  均为退出码 0，证据脱敏检查通过。

复审确认真实 Validator、摘要计算器、Adapter、CLI 和 Fixture 任一受审文件变化都会
使对应历史报告失效。未发现新的 Agent、MCP、网络、凭据、发布或任意命令能力；
最终 P0/P1/P2 为 0/0/0。

## Workspace 消费检查器影响

根工具新增既有锁定版本 `analyzer 10.0.1` 的直接 dev 声明；Validator 的实现、CLI、摘要算法和 Harness
Fixture 均未改变。lockfile 的版本、来源与 SHA-256 不变。

## Workspace 冗余依赖清理影响

根 Workspace 清单移除空的 `app_im` entry，lockfile 没有新增依赖版本或来源。Validator Library、CLI、
摘要算法、Adapter 与 Harness Fixture 均未修改；本报告仅按当前根清单和 lockfile 重新绑定摘要，
P0/P1/P2 维持 0/0/0。

## Wire 生成 Profile Validator 扩展复审

2026-08-06 复审确认 Library 仅新增闭合 codeGeneration manifest、固定 Schema 摘要、精确 manual-only pointer 和失败 Fixture 校验；公开结果仍不可变，CLI、进程退出、网络与文件写权限均未扩大。P0/P1/P2 维持 0/0/0。

## Wire Formatter 工具依赖影响

根 Workspace 新增精确固定的 `dart_style 3.1.7` direct dev dependency，只由独立 Wire generator import。
Validator Library、CLI、摘要算法、Adapter 和 Fixture 不调用 formatter，也未获得新的文件、进程或网络
能力；P0/P1/P2 维持 0/0/0。
