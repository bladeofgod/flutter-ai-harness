---
task: repository-architecture-gates
status: passed
p0: 0
p1: 0
---

# Review：补强仓库架构边界 lint

## 结论

P0/P1/P2 均为 0，任务通过。

## 审查结果

- Controller 目录中的 `Get.find<XxxApi>()` 会被拒绝，Page/Route 内联构造注入仍允许。
- Demo 壳直接 import Feature 内部目录会被拒绝，公开 `app_features.dart` 入口仍允许。
- Package 依赖通过 `dart pub deps --json` 结构化解析，没有用文本拼接读取真实 `pubspec.yaml`。
- `dependencies` 与 `dev_dependencies` 中的 Workspace 反向依赖都会进入矩阵检查。
- 未登记的新 Workspace Package 会失败，防止新增层级静默绕过门禁。

## 验证

完整输出见 `docs/reviews/test-evidence/repository-architecture-gates.log`：

- `make lint`：通过。
- `make lint-test`：允许/拒绝 Fixture 通过。
- `dart analyze tool/check_package_dependencies.dart`：通过。

## 剩余风险

正则只承担稳定语法反模式；需要识别类型别名或复杂语义时，应升级为 analyzer/AST 工具。
