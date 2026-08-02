# 架构说明

## 跨运行时总览

Flutter Workspace、平台 Host 和已实现/后续 Native Module 遵循以下单向关系：

```text
Android Native Consumer -> Android Native Module
iOS Native Consumer     -> iOS Native Module

Flutter Consumer -> Dart Client -> Channel -> Android Bridge Adapter -> Android Native Module
Flutter Consumer -> Dart Client -> Channel -> iOS Bridge Adapter     -> iOS Native Module

Android/iOS Host -> Native Module 装配与对应 Bridge Adapter 注册
Native Module    -x-> Flutter
```

下文的 Package 职责和依赖矩阵约束 Dart/Flutter Workspace。Native Module、聚焦 Bridge
Package、两端 Adapter、Host 构建接线、生命周期及测试边界统一见
[`native-architecture.md`](./native-architecture.md)；具体 Channel wire 契约见
[`bridge/README.md`](./bridge/README.md)。

## 包职责

| 包 | 负责 | 禁止承担 |
| --- | --- | --- |
| `app_core` | `ApiClient`、`ApiTransport`、存储抽象、日志、环境和平台无关基础设施 | Feature 业务、业务 Entity 或 UI |
| `app_data` | Domain Entity、LocalDataSource、确定性 Fixture 及其 Transport、协议/持久化适配和 Mapper | 页面、Controller、Feature 导航或业务 API 实现 |
| `app_ui` | 设计 Token 和无业务通用 UI | 产品业务规则 |
| `app_im` | IM Engine 契约和消息基础设施 | Feature 页面或壳工程装配 |
| `app_media` | App 私有媒体资源导入、opaque 引用、进程级生命周期以及无业务图片/视频缩略图和预览 | 业务消息、上传/持久化、Native Capture 状态机、业务 Route 或原始路径传播 |
| `app_media_capture_bridge` | Media Capture 类型化 Dart Client、Wire Codec 和平台 Plugin 入口 | Feature 业务、原生能力状态机或 Host 装配 |
| `app_features` | Feature、Controller、Page、Route、业务 API 抽象及其 Feature 实现 | 全局启动、基础数据适配或原生工程配置 |
| `apps/demo` | 全局服务、依赖装配、Router 创建和 `runApp` | Feature 内部实现 |

## Package 依赖矩阵

`A -> B` 表示 Package A 可以在 `dependencies` 或 `dev_dependencies` 中声明并 import Package B。表中未列出的 Workspace 依赖均禁止：

| Package | 允许直接依赖的 Workspace Package |
| --- | --- |
| `app_core` | 无 |
| `app_ui` | 无 |
| `app_data` | `app_core` |
| `app_im` | `app_core` |
| `app_media` | `app_core`、`app_ui` |
| `app_media_capture_bridge` | 无 |
| `app_features` | `app_core`、`app_data`、`app_im`、`app_media`、`app_media_capture_bridge`、`app_ui` |
| `apps/demo` | `app_core`、`app_data`、`app_im`、`app_media`、`app_media_capture_bridge`、`app_ui`、`app_features` |

`apps/demo` 位于最上层，负责装配所有公开模块入口；`app_core` 和 `app_ui` 位于基础层，不得反向依赖业务、数据或壳工程。`app_media` 位于二者之上、`app_features` 之下，允许复用传输中立 ID 与 UI Token，但不得反向依赖 Feature、数据层、Capture Bridge 或壳工程。新增 Workspace Package 时必须先在本矩阵中确定层级，再同步更新结构化依赖门禁。

## 类型边界

```text
Fixture Payload → Mapper → Domain Entity → API/Controller/UI
Wire/Proto 类型 → Mapper → Domain Entity → API/Controller/UI
数据库 Row      → Mapper → Domain Entity → API/Controller/UI
```

`app_core` 只能定义并处理传输中立的 Request、Response、Failure 和不透明 Payload，不得定义、import 或解析具体 Fixture、协议或持久化类型。具体 Fixture Payload、协议类型和数据库 Row 及其解析只能位于 `app_data` 的 Transport、Adapter 和 Mapper 内。Feature 公共方法、Controller 构造参数、Route 参数和跨 Feature API 必须使用 Domain Entity 或明确的 Value Object。

`MediaResourceId` 是 `app_core` 唯一批准的聚焦基础设施 ID 例外：它允许 `app_data` Domain Entity 与 `app_media` API 共享同一个传输中立 opaque Value Object，但只负责闭合格式校验。绝对路径、URI、Native/Bridge handle、Store、Resolver、引用计数、媒体 metadata 和预览行为都不属于 `app_core`。媒体消息保存 ID 与轻量 metadata，物理文件和可解析 locator 由 `app_media` 在进程级管理；详细所有权见 [`infrastructure/media-resources.md`](./infrastructure/media-resources.md)。

## 业务 API 与数据来源

业务 API 表达 Feature 需要的业务能力，不等同于 HTTP 接口。抽象接口统一位于 `app_features/lib/api/`，只使用 Domain Entity 或明确的 Value Object；具体实现位于所属 `feature_xxx/api/`，负责选择并编排数据来源。

Demo 当前没有真实远程 API，使用以下本地链路：

```text
Page / Widget
      ↓
Controller
      ↓ 构造函数注入
Abstract API                         app_features/lib/api/
      ↓
Local API Impl                       app_features/lib/feature_xxx/api/
      ↓
LocalDataSource                      app_data
      ↓
ApiClient                            app_core
      ↓
FixtureApiTransport                  app_data
      ↓
Deterministic Fixture
      ↓ 返回 Fixture Payload
LocalDataSource Mapper               app_data
      ↓
Domain Entity                        app_data
```

`ApiClient` 只负责请求编排、传输委托以及统一结果和错误边界，不引用业务 Entity。`ApiTransport` 是 `app_core` 定义的传输抽象；`FixtureApiTransport` 由 `app_data` 实现，使用稳定请求键读取确定性 Fixture。LocalDataSource 和 Mapper 同样位于 `app_data`，Feature API 实现不得接收或解析原始 Payload。

未来存在真实 Endpoint 后，可以注入 `DioApiTransport`；存在真实 Wire Contract 后，再由 `app_data` 增加协议 Adapter 和 Mapper。Page、Controller 和抽象 API 不随传输方式变化：

```text
Abstract API                         app_features/lib/api/
      ↓
Remote API Impl                      app_features/lib/feature_xxx/api/
      ↓
RemoteDataSource / Adapter           app_data
      ↓
ApiClient → DioApiTransport          app_core
      ↓ 返回 Wire Payload
Protocol Mapper → Domain Entity      app_data
```

本地和远程实现及其 DataSource、ApiClient 和 Transport 依赖由 `app_features` 的模块级 Registry 统一装配。`apps/demo` 只调用 Registry 入口并提供壳工程回调或环境选择，不直接 import `LocalXxxApiImpl`、`RemoteXxxApiImpl` 等 Feature 内部实现。切换数据来源时只调整 Registry 装配，不把分支散落到 Controller 或 UI。

初始目录在产生真实消费者时按以下职责逐步形成：

```text
app_core/lib/
└── network/                         # ApiClient、ApiTransport 与统一结果/错误

app_data/lib/
├── models/                          # Domain Entity
├── local/                           # FixtureApiTransport、Fixture、LocalDataSource 与 Mapper
└── remote/                          # 有真实协议后增加 Adapter、Mapper 与 RemoteDataSource

app_features/lib/
├── api/                             # 业务抽象接口
├── feature_xxx/api/                 # 本地或远程 API 实现
└── features_registry.dart           # 抽象接口与实现的统一绑定
```

测试 Fake 只服务测试，不作为 Demo 运行时的数据实现；Demo 使用可重复执行的 FixtureApiTransport 和 LocalDataSource。不得为了填充目录提前创建未被页面或流程消费的 Entity、API、Fixture、Transport 或 Adapter。

## Feature 边界

常规 Feature 结构：

```text
feature_example/
├── api/             公共 Feature API 的实现
├── controllers/     状态与交互编排
├── pages/           路由级 UI
├── widgets/         Feature 私有复用 UI
└── routes.dart      路由与 Controller 装配
```

复杂 Feature 可以增加私有 `models/`、`mappers/`、`services/` 或 `usecases/`，但不得外露。

跨 Feature 调用通过 `app_features/lib/api/` 下的抽象完成，由统一 Registry 绑定实现。任何 Feature 都不得 import 其他 Feature 的 `controllers/`、`pages/`、`widgets/`、私有 Service 或 `api/` 实现。

## 装配顺序

壳工程按以下顺序完成装配：

1. 初始化平台无关的全局服务。
2. 注册基础设施依赖；需要媒体消息时创建进程级 `app_media` Store。
3. 按需注册 IM 基础设施。
4. 通过模块级 Registry 注册 Feature API，并以构造函数注入同一 Store。
5. 创建 GoRouter 并调用 `runApp`。

Controller 通过构造函数接收必需 API。`Get.find<T>()` 或其他服务定位器只允许出现在装配点和显式全局服务中。

## 路由

每个 Feature 导出 `List<RouteBase>` 或路由构造函数，`app_features` 负责汇总；壳工程拥有根 `GoRouter`、全局 Observer、Redirect 和错误页。

统一使用 `MaterialApp.router`，不得混用 GetX 路由。

## 共享代码判断

只有同时满足以下条件才下沉共享：

1. 至少两个当前消费者需要同一能力。
2. 不包含 Feature 专属业务规则。
3. 目标包处于正确依赖层级。

有平台差异的能力走抽象接口和分端实现；无业务 UI 原语进入 `app_ui`；文件生命周期与图片/视频预览进入已批准的聚焦 `app_media` Package；其他代码留在所属 Feature。
