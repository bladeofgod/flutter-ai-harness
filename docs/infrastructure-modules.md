# 基础模块索引

> 状态：维护中。当前 Workspace 只有包职责边界，尚无已实现的公共基础模块。

本文件只用于发现能力和路由详情。开始新功能前先查下表；找到相关能力时只读取对应子文档，不批量加载 `docs/infrastructure/`。包职责见 [`architecture.md`](./architecture.md)，数据链路见 [`api-contracts.md`](./api-contracts.md)。

## 状态

- 决策状态：`已批准`、`延后`、`禁止`。
- 实现状态：`未实现`、`已实现`。包入口存在不等于能力已经实现。

## 能力速查

| 能力 | 入口或计划入口 | 目标所有者 | 决策状态 | 实现状态 | 首个真实消费者或触发条件 | 详情 |
| --- | --- | --- | --- | --- | --- | --- |
| 日志门面 | 待首个实现确定 | `app_core` | 延后 | 未实现 | 至少两个生产消费者、统一错误采集或 App Operator 证据需求 | [app-runtime.md](./infrastructure/app-runtime.md) |
| 运行环境 | 待首个实现确定 | `app_core` 契约、`apps/demo` 装配 | 延后 | 未实现 | 出现真实环境、Endpoint 或构建行为差异 | [app-runtime.md](./infrastructure/app-runtime.md) |
| API 传输编排 | `ApiClient` | `app_core` | 已批准 | 未实现 | 首个 Auth 或 Catalog API 已确定请求键、Fixture 结构和 Entity 映射 | [network.md](./infrastructure/network.md) |
| 登录态 | `AuthService` | `apps/demo` | 已批准 | 未实现 | 首个 Auth 流程已确定 Session 和登录态行为 | [session.md](./infrastructure/session.md) |
| 当前用户 | `UserService` | `apps/demo` | 已批准 | 未实现 | 首个 Auth 或 Profile 流程已确定 User Entity 字段 | [session.md](./infrastructure/session.md) |
| 安全存储 | 待首个实现确定 | `app_data` | 延后 | 未实现 | 敏感信息需要跨 App 重启持久化和明确清除策略 | [storage.md](./infrastructure/storage.md) |
| 普通 KV | 待首个实现确定 | `app_data` | 延后 | 未实现 | 非敏感小规模配置或偏好需要跨重启持久化 | [storage.md](./infrastructure/storage.md) |
| Drift 数据库生命周期 | 待首个实现确定 | `app_data` | 延后 | 未实现 | 结构化数据需要跨重启保留、Schema 和迁移 | [storage.md](./infrastructure/storage.md) |
| 网络状态 | `NetworkService` | `app_core` 契约、`apps/demo` 装配 | 延后 | 未实现 | 引入真实远程请求或明确联网差异行为 | [network.md](./infrastructure/network.md) |
| 全局 Service 初始化 | `ServiceInitializer` | `apps/demo` | 延后 | 未实现 | 多个已存在 Service 确需按顺序执行启动初始化 | [app-runtime.md](./infrastructure/app-runtime.md) |

## 维护规则

- 新增或实现能力时，在同一任务中更新本索引和对应子文档。
- 索引只记录入口、所有者、状态、触发条件和详情链接；职责、模式、禁令与验证留在子文档。
- 能力实现后，子文档必须回填真实模块路径、公共 API、消费者、生命周期和验证命令，不记录推测代码。
