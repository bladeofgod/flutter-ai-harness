---
name: ui-behavior-spec
description: "适用：根据已批准任务、产品规则、原型或 Figma 输入生成、审计或执行 Version 1 UI 行为 Spec。不适用：替代产品决策、实现 UI、操作系统原生界面或探索未定义流程。触发词：UI Spec、行为契约、plan-spec、spec-writer、spec-auditor、app-operator、Marionette 验收。"
paths: ["docs/**/*.spec.yaml", "docs/**/*.audit.yaml", ".claude/agents/spec-writer.md", ".claude/agents/spec-auditor.md", ".claude/agents/app-operator.md", ".claude/commands/plan-spec.md", ".claude/commands/execute-tasks.md", "app/tool/validate_ui_specs.dart"]
---

# UI 行为 Spec

把产品输入转换为独立于实现、可静态审计并可由 Marionette 执行的行为契约。

## 事实与输出

事实优先级依次为：已批准任务和产品规则、Figma/原型中的明确行为、代码中的 Route、Key、Semantics 与可操作边界。代码不得反向定义产品要求；存在会改变用户行为的缺失决策时生成 `draft`，不得猜测。

- 有任务卡：写入任务卡同目录 `<task-basename>.spec.yaml`，并声明任务 ID。
- 仅有原型：写入 `docs/app-operator/specs/<spec-id>.spec.yaml`。
- 静态审计：写入同目录 `<task-basename>.audit.yaml` 或 `<spec-id>.audit.yaml`。
- 运行报告：写入 `docs/app-operator/runs/<spec-id>/<YYYYMMDD-HHMMSS>.md`。

## Version 1 Schema

```yaml
version: 1
revision: 1
id: profile-save-name
status: ready
task: S2-003
title: 保存个人资料名称
sources:
  - type: task
    ref: docs/tasks/sprint-2/S2-003-profile.md
platforms: [android, ios]
steps:
  - id: open-profile
    action: tap
    target: {by: semantics, value: 个人资料}
  - id: enter-name
    action: enter_text
    target: {by: key, value: profile_name_input}
    value: Demo User
  - id: save
    action: tap
    target: {by: semantics, value: 保存}
assertions:
  - id: save-succeeded
    condition: visible
    target: {by: text, value: 保存成功}
teardown:
  - id: close-profile
    action: tap
    target: {by: semantics, value: 关闭}
openQuestions: []
```

## 字段约束

- `version` 固定为 `1`；`revision` 从 `1` 开始，行为内容变化时递增；`id` 和各条目 `id` 使用小写 kebab-case。
- `status` 只允许 `draft`、`ready`。
- `task` 在任务目录中必填，格式为 `S<非零 Sprint>-<三位编号>`；Spec 与任务卡同名。
- `sources` 至少一个，`type` 只允许 `task`、`product`、`prototype`、`figma`、`code`。
- `platforms` 至少一个，只允许 `android`、`ios`。
- `teardown` 使用与 Step 相同的结构，无清理动作时显式写 `[]`。
- Steps 必须从 App 启动后的可观察界面开始，完整编码 App 内导航和交互，不依赖未声明的页面状态。
- `ready` 表示内容完整、没有待决问题且通过机器校验，不要求逐条人工 Review；`draft` 必须列出 `openQuestions`，由人补充决策后再继续。
- `ready` 必须有 Step 和 Assertion，且 `openQuestions` 为空。

Step 的 `action` 只允许 `tap`、`enter_text`、`scroll_until_visible`、`wait_for`。Assertion 的 `condition` 只允许 `visible`、`not_visible`、`text_equals`、`enabled`、`disabled`。Target 的 `by` 只允许 `key`、`semantics`、`text`；禁止坐标和 Widget 层级索引。`enter_text` 必须提供字符串 `value`，`text_equals` 必须提供字符串 `expected`，等待覆盖使用正整数 `timeoutMs`。

Assertion 只验证用户可观察状态，不断言私有方法、Controller 字段或 Mock 调用顺序。

## 静态审计

审计文件使用 Version 1 YAML：

```yaml
version: 1
spec: docs/tasks/sprint-2/S2-003-profile.spec.yaml
specId: profile-save-name
specRevision: 1
status: passed
items:
  - id: open-profile
    status: covered
    evidence: [app/packages/app_features/lib/feature_profile/routes.dart:18]
  - id: enter-name
    status: covered
    evidence: [app/packages/app_features/lib/feature_profile/pages/profile_page.dart:42]
  - id: save
    status: covered
    evidence: [app/packages/app_features/lib/feature_profile/pages/profile_page.dart:51]
  - id: save-succeeded
    status: covered
    evidence: [app/packages/app_features/lib/feature_profile/pages/profile_page.dart:64]
  - id: close-profile
    status: covered
    evidence: [app/packages/app_features/lib/feature_profile/pages/profile_page.dart:72]
```

审计项必须逐一覆盖 Spec 中的 Step、Assertion 和 Teardown ID，状态只允许 `covered`、`missing`、`wrong`。`passed` 要求全部为 `covered`；存在 `missing` 或 `wrong` 时必须为 `failed`。`spec`、`specId` 和 `specRevision` 必须与同目录 Spec 一致；修改 Spec 后必须重新审计。

## 角色流程

1. `spec-writer` 从事实来源生成或修改 Spec，运行 `make spec-check`；无待决问题时直接输出 `ready`。
2. `spec-auditor` 只审计通过校验且为 `ready` 的 Spec，对照实现输出结构化审计，不修改 Spec 或实现。
3. 审计为 `passed` 后，调用方按 `flutter-debug-runtime` Skill 构建、安装并启动 Debug App。
4. `app-operator` 校验 Spec 与审计版本一致，只执行静态审计通过的行为验证。
5. Operator 依次执行 Step、Assertion、Teardown，首次失败时采集脱敏截图和日志，最终断开连接并写运行报告。

Marionette 只操作 Flutter Widget Tree。系统权限弹窗等原生系统 UI 必须使用平台自动化，不得写成本 Schema 的 Step。Spec、审计和运行报告均不得记录凭据、VM Service URI、设备标识或真实用户数据。
