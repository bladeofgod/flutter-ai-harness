# API 与数据契约

> 状态：当前 Demo 使用确定性本地数据，尚无真实远程 API 或 Protobuf Wire Contract。

## 业务 API

业务 API 是 Controller 依赖的业务能力边界，不要求背后存在网络请求：

- 抽象接口位于 `app_features/lib/api/`，只接受和返回 Domain Entity 或明确的 Value Object。
- 本地实现位于对应 `app_features/lib/feature_xxx/api/`，通过构造函数接收 `app_data` 提供的 LocalDataSource。
- Controller 通过构造函数接收抽象 API，不查找具体实现或自行选择本地/远程来源。
- `app_features/lib/features_registry.dart` 统一绑定抽象接口和实现；`apps/demo` 只调用 Registry 入口。
- 测试 Fake 与 Demo 运行时 Local 实现分离，不把 Mock 框架或测试专用行为带入应用代码。

## 当前本地数据策略

- 商品、分类等只读数据使用固定 ID、固定排序和固定内容的本地 Fixture。
- 不使用随机数、当前时间或在线资源作为默认数据，保证 Widget Test 和 App Operator 可重复执行。
- 购物车、收藏等可变状态在对应流程出现时默认使用进程内存；App 重启后恢复初始状态。
- 本地 API 保持异步边界，但不得随机延迟或随机失败。空数据、失败等场景通过显式构造参数或测试 Fake 注入。
- 图片、字体和图标只使用许可明确且已登记来源的仓库资源；授权不明时使用替代资源。
- 没有真实消费者的 Entity、API、Fixture、持久化表和场景配置不得提前创建。

## 依赖启用条件

当前不得为了模拟完整技术栈而建立伪 HTTP Server、虚构 Endpoint 或伪 Proto 协议：

| 能力 | 允许引入的条件 |
| --- | --- |
| Dio / Remote API Impl | 已有真实 Endpoint、鉴权、错误和版本契约 |
| Protobuf | 已有真实 Wire Contract、权威 `.proto` 来源、生成工具版本和可复现命令 |
| Drift | 已有跨 App 重启保留数据的明确产品需求和迁移策略 |

采用 Protobuf 后，`.proto` 定义与注释是 Wire 契约的权威来源，生成类型只能停留在数据适配层；API 实现负责通过 Mapper 转换为 Domain Entity，公共接口不得暴露 Proto Message。采用 Drift 后，数据库 Row 同样不得离开持久化 Adapter。

生成链路建立前，`protobuf-workflow` 和 `make proto` 只代表预留入口；`make proto-check` 在不存在 Proto 时保持明确跳过。一旦出现首个 `.proto`，必须在同一任务中建立生成、同步检查和 Mapper 测试，不能提交不可复现的占位协议。
