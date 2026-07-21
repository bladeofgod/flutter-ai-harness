---
description: 仅在人工明确安排 UI 自动化时，根据任务、产品规则或原型生成独立行为 Spec
argument-hint: "<task-card-or-prototype-path>..."
---

只有用户明确要求规划 UI 自动化或显式调用本命令时，才使用 `spec-writer` 把 `$ARGUMENTS` 转换为 UI 行为 Spec。普通任务规划和执行不得自动进入本流程。

1. 至少确认一个真实存在的任务卡、Figma 设计输入文档或原型文档。
2. 读取 `CLAUDE.md`，加载 `ui-behavior-spec` Skill，并读取相关任务和设计输入。
3. 区分产品事实、原型可见事实、工程可操作性和待决问题。
4. 无论输入是否包含任务卡，Spec 都写入 `docs/app-operator/specs/<spec-id>.spec.yaml`；任务卡仅可作为 `sources` 之一，Spec 不随任务归档移动。
5. 运行 `make spec-check`。
6. 汇报 `draft`/`ready` 状态、来源和待决问题。`ready` 只表示行为契约可以在实现存在后由人显式交给 `/execute-ui-spec`，不改变任何任务状态；`draft` 停止并请求补充待决产品信息。

不得调用 `spec-auditor` 或 `app-operator`，不得为了让 Spec 可执行而编造数据、错误态或成功条件。
