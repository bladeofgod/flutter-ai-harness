# API 契约

> 状态：占位。当前 Demo 尚未建立真实 API 或 Protobuf 协议。

首个 API 任务必须明确契约的唯一事实源、版本策略、生成工具版本和可复现命令。采用 Protobuf 时，`.proto` 定义与注释是 Wire 契约的权威来源，生成类型只能停留在数据适配层，公共接口仍使用 Domain Entity。

生成链路建立前，`protobuf-workflow`、`make proto` 和 `make proto-check` 只代表预留入口，不得宣称可用。
