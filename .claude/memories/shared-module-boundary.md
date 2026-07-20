# 何时下沉共享模块

只有同时满足以下条件，代码才可以从所属 Feature 下沉到已有共享层：

1. 至少两个当前 Feature 需要同一行为或资源。
2. 实现不包含 Feature 专属产品规则。
3. 实现不依赖平台专属能力。
4. 目标位置不会反转包依赖方向。

目标位置必须按职责确定：

- 无业务视觉原语进入 `app_ui`。
- 平台无关基础设施进入 `app_core`。
- 协议/持久化映射进入 `app_data`。
- 跨 Feature 交互只在 `app_features/lib/api/` 定义抽象，具体产品实现仍归所属 Feature。
- 平台差异通过抽象 API 和分端实现处理。

单消费者代码或无法归入上述职责的产品行为继续留在所属 Feature。不得自行创建 `app_features/lib/shared/` 等模糊共享目录；确需新增 Package 时，必须先更新架构职责、依赖矩阵和门禁。共享输入或编辑原语应提供一套经过测试的 API，不允许各 Feature 分别手工操作 Selection、Token 或状态。
