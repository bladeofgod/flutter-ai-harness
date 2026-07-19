# 架构说明

## 包职责

| 包 | 负责 | 禁止承担 |
| --- | --- | --- |
| `app_core` | 网络、存储抽象、日志、环境、平台无关基础设施 | Feature 业务或 UI |
| `app_data` | Domain Entity、协议适配、持久化适配、Mapper | 页面、Controller、Feature 导航 |
| `app_ui` | 设计 Token 和无业务通用 UI | 产品业务规则 |
| `app_im` | IM Engine 契约和消息基础设施 | Feature 页面或壳工程装配 |
| `app_rtc` | RTC 契约、Bridge Client 和生命周期基础设施 | Feature 页面或壳工程装配 |
| `app_features` | Feature、Controller、Page、Route 和跨 Feature API 抽象 | 全局启动或原生工程配置 |
| `apps/demo` | 全局服务、依赖装配、Router 创建和 `runApp` | Feature 内部实现 |

## Package 依赖矩阵

`A -> B` 表示 Package A 可以在 `dependencies` 或 `dev_dependencies` 中声明并 import Package B。表中未列出的 Workspace 依赖均禁止：

| Package | 允许直接依赖的 Workspace Package |
| --- | --- |
| `app_core` | 无 |
| `app_ui` | 无 |
| `app_data` | `app_core` |
| `app_im` | `app_core` |
| `app_rtc` | `app_core` |
| `app_features` | `app_core`、`app_data`、`app_im`、`app_rtc`、`app_ui` |
| `apps/demo` | `app_core`、`app_data`、`app_im`、`app_rtc`、`app_ui`、`app_features` |

`apps/demo` 位于最上层，负责装配所有公开模块入口；`app_core` 和 `app_ui` 位于基础层，不得反向依赖业务、数据或壳工程。新增 Workspace Package 时必须先在本矩阵中确定层级，再同步更新结构化依赖门禁。

## 类型边界

```text
Wire/Proto 类型 → Mapper → Domain Entity → API/Controller/UI
数据库 Row      → Mapper → Domain Entity → API/Controller/UI
```

协议类型和持久化类型只能出现在 Adapter 与 Mapper 内。公共方法、Controller 构造参数、Route 参数和跨包 API 必须使用 Domain Entity 或明确的 Value Object。

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

跨 Feature 调用通过 `app_features/lib/api/` 下的抽象完成，由统一 Registry 绑定实现。任何 Feature 都不得 import 其他 Feature 的 `controllers/`、`pages/`、`widgets/` 或私有 Service。

## 装配顺序

壳工程按以下顺序完成装配：

1. 初始化平台无关的全局服务。
2. 注册基础设施依赖。
3. 按需注册 IM/RTC 基础设施。
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
