---
description: 仅在人工明确安排时，对 ready UI Spec 执行静态审计和指定平台运行验证
argument-hint: "<spec-path> <android|ios>..."
---

本命令是独立 UI 自动化入口，不属于任务实现、Review、归档或发版默认门禁。只有用户明确调用本命令并提供真实 Spec 路径与至少一个平台时才执行；不得从任务类型、Figma 输入或 `ready` 状态自动触发。

## 前置条件

1. Spec 必须位于 `docs/app-operator/specs/<spec-id>.spec.yaml`，状态为 `ready`，且 `make spec-check` 通过。
2. 平台必须由用户显式指定，只允许 `android`、`ios`；不得因为 Spec 声明了多个平台就自动扩大本次范围。
3. 读取 `CLAUDE.md`，加载 `ui-behavior-spec`、`flutter-debug-runtime` 和 `marionette-debug` Skill。
4. 本流程只验证当前实现，不授权修改生产代码、测试、任务卡或 Spec。发现实现缺失时报告结果并停止，修复需用户另行安排。

## 执行

1. 调用 `spec-auditor` 对照当前实现写入同目录 `<spec-id>.audit.yaml`，再运行 `make spec-check`。
2. Audit 不是 `passed`、任一条目不是 `covered` 或实现摘要无效时，停止，不启动 App Operator。
3. 对用户明确指定的每个平台分别加载 `flutter-debug-runtime`，构建、安装并保持 Debug App 运行；设备、签名、系统权限、账号或测试数据缺失时请求人工介入。
4. 每个平台取得 VM Service URI 后只在当前调用中交给 `app-operator`。Operator 严格执行 Spec，并覆盖写入 `docs/app-operator/runs/<spec-id>/<platform>.run.yaml`。
5. 每个平台结束后确认断开 Marionette，最后运行 `make spec-check`。

## 交付

汇报 Spec、Audit、用户指定平台的 Run 报告、失败证据、运行环境缺口和精确命令结果。不得修改或归档普通任务，不得自动修复审计/运行发现，也不得因本次未选择其他声明平台而把已有任务判定为失败。
