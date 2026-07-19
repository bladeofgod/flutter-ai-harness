# UI 自动化 Spec

> 状态：占位。当前没有真实 UI 自动化 Spec，也没有预置虚构执行历史。

首个需要稳定回归的 Demo 流程出现时，再在真实任务中定义 Spec Schema、Setup、Steps、Assert、Teardown、选择器优先级、失败证据和 History 规则，并同步校准 `app-operator` 与 `spec-auditor`。

在 Schema 建立前，只允许使用 `marionette-debug` 做临时诊断，不创建仅为触发 Agent 而存在的 `.spec.yaml`。
