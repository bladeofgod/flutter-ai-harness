---
name: ui-behavior-spec
description: "适用：根据已批准任务、产品规则、原型或 Figma 输入生成、审计或执行 Version 1 UI 行为 Spec。不适用：替代产品决策、实现 UI、操作系统原生界面或探索未定义流程。触发词：UI Spec、行为契约、plan-spec、spec-writer、spec-auditor、app-operator、Marionette 验收。"
paths: ["docs/app-operator/**/*.spec.yaml", "docs/app-operator/**/*.audit.yaml", "docs/app-operator/**/*.run.yaml", ".claude/agents/spec-writer.md", ".claude/agents/spec-auditor.md", ".claude/agents/app-operator.md", ".claude/commands/plan-spec.md", ".claude/commands/execute-ui-spec.md", "app/tool/validate_ui_specs.dart", "app/tool/implementation_digest.dart"]
---

# UI 行为 Spec

把产品输入转换为独立于实现、可静态审计并可由 Marionette 执行的行为契约。

## 事实与输出

事实优先级依次为：已批准任务和产品规则、Figma/原型中的明确行为、代码中的 Route、Key、Semantics 与可操作边界。代码不得反向定义产品要求；存在会改变用户行为的缺失决策时生成 `draft`，不得猜测。

- Spec 统一写入 `docs/app-operator/specs/<spec-id>.spec.yaml`；任务卡、产品规则、Figma 和原型只作为 `sources`。
- 静态审计写入同目录 `<spec-id>.audit.yaml`。
- 运行报告：按平台写入 `docs/app-operator/runs/<spec-id>/<platform>.run.yaml`；同一平台重新执行时覆盖当前报告，历史由 Git 保存。

Spec、Audit 和 Run 是人工独立安排的自动化证据，不属于普通任务卡元数据、执行门禁或归档产物。`ready` Spec、passed Audit 或已有 Run 均不得自动触发后续阶段。

## Version 1 Schema

```yaml
version: 1
revision: 1
id: profile-save-name
status: ready
title: 保存个人资料名称
sources:
  - type: task
    ref: profile-save-name
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
- `sources` 至少一个，`type` 只允许 `task`、`product`、`prototype`、`figma`、`code`。`task` Source 的 `ref` 使用稳定任务 slug，校验器同时查找活动与归档任务，不保存会随归档变化的任务路径；其他本地 Source 使用仓库相对路径。
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
spec: docs/app-operator/specs/profile-save-name.spec.yaml
specId: profile-save-name
specRevision: 1
status: passed
implementationDigest: <sha256>
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

审计项必须逐一覆盖 Spec 中的 Step、Assertion 和 Teardown ID，状态只允许 `covered`、`missing`、`wrong`。`covered`、`wrong` 的证据必须是仓库内真实生产实现的 `file:line`，不得引用测试、文档、生成文件、仓库外路径或越界行号；`missing` 不得包含证据。`passed` 要求全部为 `covered`，并运行 `bash scripts/dart-tool.sh run tool/implementation_digest.dart <证据文件路径...>` 计算去重后全部证据文件的 `implementationDigest`；实现文件变化后旧审计自动失效。`spec`、`specId` 和 `specRevision` 必须与同目录 Spec 一致；修改 Spec 后必须重新审计。

## 运行报告

每个由人实际选择并执行的平台单独生成 Version 1 YAML：

```yaml
version: 1
spec: docs/app-operator/specs/profile-save-name.spec.yaml
audit: docs/app-operator/specs/profile-save-name.audit.yaml
specId: profile-save-name
specRevision: 1
implementationDigest: <与 Audit 一致的 sha256>
platform: android
status: passed
environment:
  osVersion: Android 15
  deviceKind: emulator
  buildMode: debug
  flutterVersion: 3.41.9
  marionetteVersion: 0.6.0
items:
  - id: open-profile
    status: passed
    evidence: []
  - id: enter-name
    status: passed
    evidence: []
  - id: save
    status: passed
    evidence: []
  - id: save-succeeded
    status: passed
    evidence: []
  - id: close-profile
    status: passed
    evidence: []
```

报告必须逐一覆盖 Spec 的全部 ID，条目状态只允许 `passed`、`failed`、`skipped`；总体 `passed` 要求全部条目 `passed`。失败条目必须引用 `docs/app-operator/evidence/<spec-id>/` 下的脱敏截图或日志。环境只记录平台复现所需的非敏感信息，不记录设备 ID、主机名、用户名、VM Service URI、账号或真实数据。只要求本次由人明确选择的平台生成报告；未选择的声明平台不影响普通任务状态。

## 角色流程

1. 人明确调用 `/plan-spec` 后，`spec-writer` 从事实来源生成或修改 Spec，运行 `make spec-check`；无待决问题时输出 `ready`。
2. 人明确调用 `/execute-ui-spec` 并选择平台后，`spec-auditor` 才审计 ready Spec，对照实现输出结构化审计，不修改 Spec 或实现。
3. 审计为 `passed` 后，`execute-ui-spec` 按 `flutter-debug-runtime` Skill 只为用户选择的平台构建、安装并启动 Debug App。
4. `app-operator` 校验 Spec、审计和实现摘要一致，每次只执行一个用户明确选择的平台。
5. Operator 依次执行 Step、Assertion、Teardown，首次失败时采集脱敏截图和日志，最终断开连接并写该平台的结构化运行报告。

Marionette 只操作 Flutter Widget Tree。系统权限弹窗等原生系统 UI 必须使用平台自动化，不得写成本 Schema 的 Step。Spec、审计和运行报告均不得记录凭据、VM Service URI、设备标识或真实用户数据。
