# S1-002 Review：修正依赖方向契约

## 结论

P0/P1/P2 均为 0，任务通过。

## 审查结果

- `A -> B` 在权威契约、英文 README、中文 README 和架构文档中统一表示 A 可以 import B。
- 允许依赖矩阵与当前各 Package `pubspec.yaml` 一致。
- `apps/demo` 的装配层例外被显式列出，没有改变下层包职责。
- `app_core`、`app_ui` 的基础层方向明确，不再使用含义相反的箭头。

## 验证

完整输出见 `docs/reviews/test-evidence/S1-002-dependency-contract.log`：

- `git diff --check`：通过。
- `make lint`：真实 Workspace 依赖矩阵通过。

## 剩余风险

新增 Workspace Package 时必须同步更新矩阵和结构化门禁；`S1-003` 已覆盖该失败场景。
