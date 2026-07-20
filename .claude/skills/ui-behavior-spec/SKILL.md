---
name: ui-behavior-spec
description: "适用：根据已批准任务、产品规则、原型或 Figma 输入生成、审计或执行 Version 1 UI 行为 Spec。不适用：替代产品决策、实现 UI、操作系统原生界面或探索未定义流程。触发词：UI Spec、行为契约、plan-spec、spec-writer、spec-auditor、app-operator、Marionette 验收。"
paths: ["docs/**/*.spec.yaml", ".claude/agents/spec-writer.md", ".claude/agents/spec-auditor.md", ".claude/agents/app-operator.md", ".claude/commands/plan-spec.md", "app/tool/validate_ui_specs.dart"]
---

# UI 行为 Spec

把产品输入转换为独立于实现、可静态审计并可由 Marionette 执行的行为契约。

## 事实与输出

事实优先级依次为：已批准任务和产品规则、Figma/原型中的明确行为、代码中的 Route、Key、Semantics 与可操作边界。代码不得反向定义产品要求；存在会改变用户行为的缺失决策时生成 `draft`，不得猜测。

- 有任务卡：写入任务卡同目录 `<task-basename>.spec.yaml`，并声明任务 ID。
- 仅有原型：写入 `docs/app-operator/specs/<spec-id>.spec.yaml`。
- 静态审计：写入同目录 `<spec-basename>.audit.md`。
- 运行报告：写入 `docs/app-operator/runs/<spec-id>/<YYYYMMDD-HHMMSS>.md`。

## Version 1 Schema

```yaml
version: 1
id: profile-save-name
status: ready
task: S2-003
title: 保存个人资料名称
sources:
  - type: task
    ref: docs/tasks/sprint-2/S2-003-profile.md
platforms: [android, ios]
setup:
  - id: profile-open
    description: App 已进入个人资料编辑页，并使用非真实用户的测试数据
steps:
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
  - id: restore-profile
    description: 恢复固定测试资料
openQuestions: []
```

## 字段约束

- `version` 固定为 `1`；`id` 和各条目 `id` 使用小写 kebab-case。
- `status` 只允许 `draft`、`ready`。
- `task` 在任务目录中必填，格式为 `S<非零 Sprint>-<三位编号>`；Spec 与任务卡同名。
- `sources` 至少一个，`type` 只允许 `task`、`product`、`prototype`、`figma`、`code`。
- `platforms` 至少一个，只允许 `android`、`ios`。
- `setup` 描述执行前已经满足的状态；不得让 Operator 代办登录或环境准备。
- `teardown` 无动作时显式写 `[]`。
- `ready` 必须有 Setup、Step、Assertion 且 `openQuestions` 为空；`draft` 必须列出 `openQuestions`，不得执行。

Step 的 `action` 只允许 `tap`、`enter_text`、`scroll_until_visible`、`wait_for`。Assertion 的 `condition` 只允许 `visible`、`not_visible`、`text_equals`、`enabled`、`disabled`。Target 的 `by` 只允许 `key`、`semantics`、`text`；禁止坐标和 Widget 层级索引。`enter_text` 必须提供字符串 `value`，`text_equals` 必须提供字符串 `expected`，等待覆盖使用正整数 `timeoutMs`。

Assertion 只验证用户可观察状态，不断言私有方法、Controller 字段或 Mock 调用顺序。

## 角色流程

1. `spec-writer` 从事实来源生成或修改 Spec，运行 `make spec-check`，等待 Review。
2. `spec-auditor` 只审计通过校验且为 `ready` 的 Spec，对照实现输出独立审计报告，不修改 Spec 或实现。
3. `app-operator` 只执行通过静态审计的 `ready` Spec；调用方负责启动 Debug App、提供 VM Service URI 并满足 Setup。
4. Operator 依次执行 Step、Assertion、Teardown，首次失败时采集脱敏截图和日志，最终断开连接并写运行报告。

Marionette 只操作 Flutter Widget Tree。系统权限弹窗等原生系统 UI 必须使用平台自动化，不得写成本 Schema 的 Step。Spec、审计和运行报告均不得记录凭据、VM Service URI、设备标识或真实用户数据。
