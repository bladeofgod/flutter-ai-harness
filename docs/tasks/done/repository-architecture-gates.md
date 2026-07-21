---
executor: task-executor
blockedBy: [workspace-dependency-contract]
---

# 补强仓库架构边界 lint

## 背景

当前 lint 会放行 Controller 内 `Get.find<XxxApi>()`、壳工程直接引用 Feature 实现和 Package 反向依赖。

## 输入与事实来源

- `docs/reviews/harness-baseline.md` P1-2
- `CLAUDE.md` 架构不变量
- `.claude/memories/api-injection-gate.md`
- `scripts/lint/repository-boundaries.sh`

## 目标

让 `make lint` 对三类关键越界可靠失败，并用 Fixture 固化允许与拒绝行为。

## 非目标

- 不用正则模拟完整 Dart 类型系统。
- 不禁止 Page/Route 装配点把 `Get.find<Api>()` 直接传给 Controller 构造函数。

## 具体要求

- Controller 目录禁止 `Get.find<XxxApi>()`。
- Demo 壳禁止 import `app_features` 的 Feature 内部目录，只能依赖公开 Barrel/Registry。
- 使用 `dart pub deps --json` 的结构化输出检查 Workspace 直接依赖允许矩阵。
- 校验器支持传入 Fixture JSON，不依赖修改真实 Pub Workspace。
- 扩充 lint Fixture，覆盖三类违规和合法装配点。

## 同时编写的测试

- Controller 服务定位拒绝。
- 壳工程内部 import 拒绝。
- `app_core -> app_features` 反向依赖拒绝。
- 当前合法依赖图通过。

## 验收标准

- 审查中曾被错误放行的三项 Fixture 全部失败。
- 现有 Demo 和允许装配点通过。

## 验证命令

```bash
make lint
make lint-test
```

## 风险与待决问题

若未来 Package 拆分，需要同步更新架构矩阵和 Fixture。
