# Network 基础能力

> 状态：`ApiClient` 已实现；`NetworkService` 延后且未实现。

[返回基础模块索引](../infrastructure-modules.md)

本文件只覆盖传输编排、Fixture Transport 和网络状态。完整业务 API 与 Fixture 数据链路以 [`api-contracts.md`](../api-contracts.md) 为准。

## ApiClient

- 决策状态：已批准。
- 实现状态：已实现。
- 目标所有者：`app_core`。
- 模块路径：`app/packages/app_core/lib/network/`，由 `package:app_core/app_core.dart` 导出。
- 公共 API：`ApiRequest`、`ApiResponse<T>`、`ApiSuccess<T>`、`ApiError<T>`、`ApiFailure`、`ApiTransport`、`ApiClient`、`Secret<T>` 和脱敏 Transport 异常。
- 首个消费者：`AuthLocalDataSource` 通过 `FeaturesRegistry.local()` 装配 `FixtureApiTransport -> ApiClient`。
- 采用模式：只负责编排传输、统一结果和错误边界，通过构造函数接收传输中立的 `ApiTransport`，不引用业务 Entity。
- 首个 Transport：由 `app_data` 提供确定性的 `FixtureApiTransport`，使用本地结构化数据和稳定请求键；LocalDataSource 与 Mapper 在 `app_data` 内把 Payload 转换为 Domain Entity。
- 生命周期：`FeaturesRegistry.local()` 每次创建 Transport、ApiClient、DataSource 和 Auth API；Auth Fixture 按输入确定性返回结果，不保存账号状态，当前对象也不持有 Stream、Socket 或其他待释放资源。
- 未来替换：只有真实 Endpoint、鉴权、错误和版本契约出现后才增加 `DioApiTransport`；业务 API 不随 Transport 改变。
- 禁止耦合：不得解析具体 Fixture Payload，不得加入 Token 刷新、缓存策略、页面文案、业务错误码 UI 编排或 Feature 分支；不得启动伪 HTTP Server、使用测试 Mock Adapter 或伪造 Proto。
- 启用验证：`app/packages/app_core/test/network/api_client_test.dart`、`app/packages/app_data/test/auth/`、`app/packages/app_features/test/feature_auth/`，以及 `make analyze`、`make lint`。

验证命令：

```bash
TOOL_WORKDIR=app/packages/app_core bash scripts/dart-tool.sh test test/network/api_client_test.dart
TOOL_WORKDIR=app/packages/app_data bash scripts/dart-tool.sh test test/auth
TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_auth
```

## NetworkService

- 决策状态：延后。
- 实现状态：未实现。
- 目标所有者：`app_core` 定义窄契约，`apps/demo` 装配平台 Adapter。
- 首个消费者：出现真实远程请求，或产品明确要求区分联网状态行为时实现。
- 采用模式：暴露可观察的网络状态；远程请求结果仍是服务可用性的最终事实来源。
- 禁止耦合：不得在没有远程请求时创建，不得把 Connectivity 状态当作请求一定成功的证明，不得在 Service 内编排页面提示。
- 启用验证：覆盖初始状态、状态去重、订阅释放和请求失败行为，并验证 Android/iOS 生命周期差异。

实现任一能力后，在本文件补充真实模块路径、公共 API、消费者、生命周期和精确验证命令。
