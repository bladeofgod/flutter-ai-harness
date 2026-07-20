# 架构说明

## 包职责

| 包 | 负责 | 禁止承担 |
| --- | --- | --- |
| `app_core` | 网络、存储抽象、日志、环境、平台无关基础设施 | Feature 业务或 UI |
| `app_data` | Domain Entity、LocalDataSource、确定性 Fixture、协议/持久化适配和 Mapper | 页面、Controller、Feature 导航或业务 API 实现 |
| `app_ui` | 设计 Token 和无业务通用 UI | 产品业务规则 |
| `app_im` | IM Engine 契约和消息基础设施 | Feature 页面或壳工程装配 |
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
| `app_features` | `app_core`、`app_data`、`app_im`、`app_ui` |
| `apps/demo` | `app_core`、`app_data`、`app_im`、`app_ui`、`app_features` |

`apps/demo` 位于最上层，负责装配所有公开模块入口；`app_core` 和 `app_ui` 位于基础层，不得反向依赖业务、数据或壳工程。新增 Workspace Package 时必须先在本矩阵中确定层级，再同步更新结构化依赖门禁。

## 类型边界

```text
Wire/Proto 类型 → Mapper → Domain Entity → API/Controller/UI
数据库 Row      → Mapper → Domain Entity → API/Controller/UI
本地 Fixture    → LocalDataSource → Domain Entity → API/Controller/UI
```

协议类型和持久化类型只能出现在 Adapter 与 Mapper 内。公共方法、Controller 构造参数、Route 参数和跨包 API 必须使用 Domain Entity 或明确的 Value Object。

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
Deterministic Fixture
      ↓
Domain Entity                        app_data
```

未来存在真实 Endpoint 和 Wire Contract 后，可以增加远程实现，但不改变 Page、Controller 和抽象 API：

```text
Abstract API                         app_features/lib/api/
      ↓
Remote API Impl                      app_features/lib/feature_xxx/api/
      ↓
ApiClient                            app_core
      ↓
Proto Message → Mapper → Entity      app_data
```

本地和远程实现由 `app_features` 的模块级 Registry 绑定。`apps/demo` 只调用 Registry 入口并提供壳工程回调或环境选择，不直接 import `LocalXxxApiImpl`、`RemoteXxxApiImpl` 等 Feature 内部实现。切换数据来源时只调整 Registry 装配，不把分支散落到 Controller 或 UI。

初始目录在产生真实消费者时按以下职责逐步形成：

```text
app_data/lib/
├── models/                          # Domain Entity
└── local/                           # LocalDataSource 与确定性 Fixture

app_features/lib/
├── api/                             # 业务抽象接口
├── feature_xxx/api/                 # 本地或远程 API 实现
└── features_registry.dart           # 抽象接口与实现的统一绑定
```

测试 Fake 只服务测试，不作为 Demo 运行时的数据实现；Demo 使用可重复执行的 LocalDataSource。不得为了填充目录提前创建未被页面或流程消费的 Entity、API、Fixture 或 Adapter。

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
2. 注册基础设施依赖。
3. 按需注册 IM 基础设施。
4. 通过模块级 Registry 注册 Feature API。
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

有平台差异的能力走抽象接口和分端实现；无业务 UI 原语进入 `app_ui`；其他代码留在所属 Feature。
