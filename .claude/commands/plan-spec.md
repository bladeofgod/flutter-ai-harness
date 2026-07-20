---
description: 根据任务卡或原型文档生成可审查的 UI 行为 Spec，不实现或执行 App
argument-hint: "<task-card-or-prototype-path>..."
---

使用 `spec-writer` 把 `$ARGUMENTS` 转换为 UI 行为 Spec。

1. 至少确认一个真实存在的任务卡、Figma 输入快照或原型文档。
2. 读取 `CLAUDE.md`、`docs/app-operator/README.md`、相关任务和设计输入。
3. 区分产品事实、原型可见事实、工程可操作性和待决问题。
4. 有任务卡时把 Spec 写在任务卡同目录；只有原型时写入 `docs/app-operator/specs/`。
5. 运行 `make spec-check`。
6. 汇报 `draft`/`ready` 状态、来源和待决问题，停在实现与 App 操作之前等待用户 Review。

不得调用 `app-operator`，不得为了让 Spec 可执行而编造 Setup、数据、错误态或成功条件。
