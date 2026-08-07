---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy:
  - extract-harness-validator-library
securityReview: required
---

# 实现 Workspace 依赖消费检查器

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 4 项已确认方向。
- `app/tool/check_package_dependencies.dart` 当前只校验允许依赖矩阵，不判断声明的直接依赖是否有消费者。
- `scripts/lint/repository-boundaries.sh`、`scripts/lint/test-repository-boundaries.sh` 和
  `app/tool/check_flutter_plugin_discovery.dart`。
- 当前事实：`app_im` 没有源码消费者；Demo 的若干 Workspace 直接依赖和 `app_features -> app_im` 没有
  import；Media Capture Plugin 仍需保持可发现。

## 目标

- 实现可独立调用的依赖消费检查器，识别无源码消费者的直接依赖和无任何真实消费者的 Workspace
  Package。
- 正确区分生产源码、测试源码和 Flutter Plugin discovery，为后续清理提供 fail-closed 事实。

## 非目标

- 本卡不删除任何 Package 或真实 `pubspec.yaml` 依赖；清理由后续卡执行。
- 不把新规则接入真实 Workspace 的默认 `make lint`；当前已知冗余边清理前接入会让本卡自身无法闭环。
- 不把所有传递依赖提升为直接依赖，不根据包名猜测 Plugin 职责。
- 不用简单文本命中误判注释、字符串或条件 import；不扫描生成/构建目录。

## 实现要求

1. 为依赖检查工具增加显式消费检查模式，使其同时获得 `dart pub deps --json` 的直接/开发依赖图、
   Workspace root 和每个 Package 的真实路径。既有默认矩阵检查行为保持兼容；Fixture 模式必须可传入
   隔离 root 与结构化 graph，不读取真实 Workspace 补数据。
2. 使用 Dart 语法解析 import/export URI，分别扫描生产入口与 test/tool/bin；生产 dependency 必须由生产
   源码消费，纯测试消费者只能支撑 `dev_dependencies`。如需 analyzer 依赖，作为根工具的直接
   `dev_dependency` 引入并由生成命令更新 lockfile。
3. 对 Flutter Plugin 建立结构化例外：只有依赖图和 `.flutter-plugins-dependencies` 能证明该直接边对目标
   Host 的 plugin reachability/registration 必需时才算消费；如果移除该边后 Plugin 仍通过其它直接依赖
   可达，则该边仍是冗余。Android/iOS 声明平台都必须检查，不能只看一个数组条目。
4. 识别无入边、无应用/工具入口、无 Plugin/生成职责的 Workspace Package，并输出稳定包名诊断。根工具
   Package、最终 App 和明确的独立 Native bridge package按结构化角色处理，不建手写 basename allowlist。
5. 诊断区分：禁止依赖、未消费生产依赖、仅测试消费却放在 production、冗余 Plugin 直连、无消费者
   Workspace Package。失败不得回显本机绝对路径。
6. Fixture 至少覆盖合法生产/dev import、conditional import/export、注释假命中、未使用依赖、仅测试
   使用、必要/冗余 Plugin discovery、无消费者 Package、未知 Package 和现有允许矩阵。
7. 提供后续清理卡可以直接调用的只读命令，并用测试 Fixture 断言它能精确报告当前已知的 `app_im`、Demo
   冗余边和 `app_features -> app_im`；该命令的预期非零只用于 Fixture/清理前盘点，不进入默认 lint。

## 验收与验证

- 新检查器能精确报告当前待清理边；既有 `make lint` 在清理完成并正式接线前继续通过。
- 不改变现有 Feature、Controller、壳工程和 Plugin discovery 的其它边界检查。

```bash
make format
make analyze
make lint-test
make harness-check
git diff --check
```

## 环境限制

门禁只证明静态消费与生成的 Plugin 图；不能替代 Flutter Host 构建。后续清理任务必须重新运行 pub get、
双平台 discovery 检查和至少一个真实 Host build。
