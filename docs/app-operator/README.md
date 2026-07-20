# UI 行为 Spec

> 状态：Version 1 Schema 已建立；当前没有 Demo 产品 Spec，也没有预置运行历史。

UI 行为 Spec 是任务/原型与运行态验收之间的独立契约。`spec-writer` 负责生成，`spec-auditor` 负责检查实现覆盖，`app-operator` 只执行已经 Review 且 `status: ready` 的 Spec。

```text
已批准任务或原型
        ↓
spec-writer
        ↓
draft/ready .spec.yaml
        ↓
实现 → spec-auditor → app-operator → 运行报告
```

## 文件位置

- 有任务卡：与任务卡同目录，命名为 `<task-basename>.spec.yaml`。
- 只有原型：`docs/app-operator/specs/<spec-id>.spec.yaml`。
- 运行报告：`docs/app-operator/runs/<spec-id>/<YYYYMMDD-HHMMSS>.md`。

原型单独输入时允许生成 `draft`。只有产品行为、Setup 和断言已经确定，`openQuestions` 为空时才能改为 `ready`。

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
  - type: figma
    ref: docs/tasks/sprint-2/.figma-plan/design-context.md
platforms: [android, ios]
setup:
  - id: profile-open
    description: App 已进入个人资料编辑页，并使用非真实用户的测试数据
steps:
  - id: enter-name
    action: enter_text
    target:
      by: key
      value: profile_name_input
    value: Demo User
  - id: save
    action: tap
    target:
      by: semantics
      value: 保存
assertions:
  - id: save-succeeded
    condition: visible
    target:
      by: text
      value: 保存成功
teardown:
  - id: restore-profile
    description: 恢复固定测试资料
openQuestions: []
```

### 顶层字段

- `version`：当前固定为 `1`。
- `id`：小写 kebab-case，在仓库中保持稳定。
- `status`：`draft` 或 `ready`。
- `task`：可选任务 ID；有任务卡时必填，且 Spec 文件必须与任务卡同名。
- `sources`：至少一个事实来源，`type` 只允许 `task`、`product`、`prototype`、`figma`、`code`。
- `platforms`：一个或多个目标平台，只允许 `android`、`ios`。
- `setup`：调用 Operator 前已经满足的状态，不是 Operator 代办的登录或环境准备。
- `steps`：Operator 执行的操作。
- `assertions`：用户可观察结果。
- `teardown`：运行后清理；无清理动作时显式使用 `[]`。
- `openQuestions`：待决产品问题；`ready` 时必须为空，`draft` 时必须非空。

### Step

Version 1 支持：

- `tap`
- `enter_text`，必须提供字符串 `value`
- `scroll_until_visible`
- `wait_for`

每个 Step 必须包含稳定 `id`、`action` 和 `target`。Target 的 `by` 只允许 `key`、`semantics`、`text`；禁止坐标或 Widget 层级索引。可以使用正整数 `timeoutMs` 覆盖默认等待时间。

### Assertion

Version 1 支持：

- `visible`
- `not_visible`
- `text_equals`，必须提供字符串 `expected`
- `enabled`
- `disabled`

Assertion 必须验证用户可观察状态，不能断言私有方法、Controller 内部字段或 Mock 调用顺序。

## 执行规则

1. 运行 `make spec-check`。
2. `spec-auditor` 对照实现写 `<spec-basename>.audit.md`；不修改 Spec。
3. 调用方启动 Debug App 并提供 VM Service URI。
4. `app-operator` 检查 Setup，按顺序执行 Step 和 Assertion，最后执行 Teardown。
5. 运行报告不得记录 VM Service URI、凭据、设备标识或真实用户数据。

Marionette 只操作 Flutter Widget Tree。涉及系统权限弹窗或其他原生系统 UI 的流程必须使用其他平台自动化方案，不能写入本 Schema 的 Step。
