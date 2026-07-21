---
executor: task-executor
blockedBy: []
---

# Demo 基础 Service 设计清册

## 背景

`AI Harness Shoppe` 需要通过真实业务链路展示基础设施、全局会话和当前用户分层。用户已批准在 Demo 中采用 `ApiClient`、`AuthService` 和 `UserService`，但当前没有真实 Endpoint、Wire Contract、登录页面行为或跨重启持久化需求。

三个 Service 必须保持模板中立，不得绑定 Proto 信封、Token 刷新、SecureStorage、IM、账号切换、私有缓存或平台环境。本任务先固化它们的 Demo 化边界；具体运行时代码必须与首个 Auth 或 Catalog 消费任务一起创建，避免无消费者实现。

`docs/infrastructure-modules.md` 只承担能力发现和按需路由。完整设计拆到 `docs/infrastructure/` 的领域子文档，避免 Agent 为确认一项能力而加载全部基础模块说明。

## 输入与事实来源

- `CLAUDE.md`
- `docs/architecture.md`
- `docs/api-contracts.md`
- `docs/figma-links.md`
- `docs/infrastructure-modules.md`
- 用户批准的本地 Mock 和三个基础 Service 决策

## 目标

- 将 `docs/infrastructure-modules.md` 从占位文档更新为轻量能力索引。
- 将基础能力详细决策按领域拆到 `docs/infrastructure/`，让 Agent 只读取当前任务相关的子文档。
- 将 `ApiClient`、`AuthService` 和 `UserService` 分别标记为“决策状态：已批准、实现状态：未实现”，并固化职责、依赖方向和实现门槛。
- 明确其他基础能力何时采用、延后以及禁止引入哪些业务耦合，为后续 Figma Feature 任务提供统一发现入口。

## 非目标

- 不在本任务中创建 ApiClient、AuthService、UserService 或 ServiceInitializer 运行时代码。
- 不引入 GetX、Dio、Proto、Drift、Secure Storage、Shared Preferences 或 Connectivity 依赖。
- 不定义 Product、User、Token、Session、Cart 等尚未由具体页面确认字段的 Entity。
- 不生成业务 API、Fixture、Route、Controller、页面或 UI 行为 Spec。
- 不引入私有 Endpoint、业务错误码、SDK 标识、未公开协议结构、账号切换或 IM/RTC 编排。

## 具体要求

1. 将 `docs/infrastructure-modules.md` 改为维护中的轻量索引。索引只保留使用方式、状态定义和能力速查表，不复制包职责、完整数据链路、设计模式、禁令或测试细节。
2. 速查表至少包含：能力、入口或计划入口、目标所有者、决策状态、实现状态、首个真实消费者条件和详情链接。决策状态只允许“已批准、延后、禁止”；实现状态只允许“未实现、已实现”。
3. 创建四份按需读取的领域文档：
   - `docs/infrastructure/network.md`：ApiClient、FixtureApiTransport 和 NetworkService。
   - `docs/infrastructure/session.md`：AuthService 和 UserService。
   - `docs/infrastructure/storage.md`：安全存储、普通 KV 和 Drift 数据库生命周期。
   - `docs/infrastructure/app-runtime.md`：日志门面、运行环境和 ServiceInitializer。
4. 每份子文档只记录本领域能力的决策状态、实现状态、首个真实消费者条件、目标所有者、采用模式、禁止耦合和启用验证；不得复制其他领域内容，也不得为未实现能力编造 API 签名、代码示例或注册代码。
5. `ApiClient` 必须记录为“已批准、随首个 Auth/Catalog API 消费者实现”，并遵守：
   - 位于 `app_core`，只负责请求编排、传输委托、统一结果和错误边界，不引用业务 Entity。
   - 通过构造函数接收 `ApiTransport`；当前由 `app_data` 提供确定性 `FixtureApiTransport`，未来真实 API 使用 `DioApiTransport`。
   - Fixture Transport 使用本地结构化数据和稳定请求键，不启动伪 HTTP Server、不依赖测试 Mock Adapter、不伪造 Proto。
   - `app_data` 的 LocalDataSource 和 Mapper 负责把 Fixture Payload 转换为 Domain Entity；Feature API 实现不得接收或解析原始 Payload。
6. `AuthService` 必须记录为“已批准、随首个 Auth 流程实现”，并遵守：
   - 位于 `apps/demo` 的全局 Service 层，管理 `isLoggedIn`、当前内存 Session 和登录态变化。
   - 当前 App 重启后恢复未登录状态，不读取或写入 SecureStorage。
   - 不包含 Access/Refresh Token 刷新、游客 Token、账号切换、IM/RTC 登录或服务端错误码 UI 编排。
   - 认证错误事件和页面/Dialog/路由编排不得塞入 AuthService。
7. `UserService` 必须记录为“已批准、随首个 Auth/Profile 消费者实现”，并遵守：
   - 位于 `apps/demo` 的全局 Service 层，与 AuthService 分离，管理当前用户 Entity 的内存快照、更新和清除。
   - 用户 Entity 字段由具体 Figma 页面和业务流程决定，不预置无消费者字段。
   - Auth/Profile 同批消费 Session 与当前用户时，由壳工程增加唯一协调入口，原子更新 AuthService 与 UserService 后统一通知；Feature API 实现不得反向依赖壳工程 Service。
8. 整体 Fixture 数据链路继续以 `docs/api-contracts.md` 为事实源，包职责和依赖方向继续以 `docs/architecture.md` 为事实源；索引和子文档只链接，不重复展开。
9. Secure Storage、KV 和 Drift 分别由敏感持久化、普通跨重启持久化和结构化迁移需求触发；当前内存状态不触发。NetworkService 只有远程请求或明确联网差异行为出现时才创建。
10. ServiceInitializer 只编排已经存在且确需启动期初始化的全局 Service；在 AuthService/UserService 实现任务之前不得创建空初始化框架。
11. 日志能力只有出现两个以上生产消费者、统一错误采集或 App Operator 证据需求时才下沉；不得预置业务标签或无消费者静态门面。
12. 后续任务创建基础 Service 时必须先查索引并只读取相关子文档；在同一任务中回填索引状态，以及子文档中的模块路径、公共 API、消费者、生命周期和验证命令。
13. `CLAUDE.md` 只把清册描述为“能力速查与详情路由”，不要求默认加载所有子文档。
14. 文档不得包含本机绝对路径、内部工程名称、私有域名、凭据、真实账号或不可公开的协议值。

## 同时编写的测试

- 本任务只修改文档，不新增应用测试。
- 使用 `make harness-check` 验证 Markdown 链接、任务卡结构和敏感路径边界。

## 验收标准

- `docs/infrastructure-modules.md` 不再是占位状态，且只包含轻量能力索引。
- `docs/infrastructure/` 的四份领域文档可以独立按需读取，不需要先加载其他领域详情。
- `CLAUDE.md` 的重要参考准确反映索引与按需路由定位，不默认加载所有子文档。
- ApiClient、AuthService 和 UserService 的决策状态均为“已批准”、实现状态均为“未实现”，并具有可执行的实现边界。
- 只有后续消费者任务创建运行时代码并回填模块路径、公共 API、生命周期和验证结果后，能力的实现状态才能改为“已实现”。
- 索引能够回答每项能力“是否存在、由什么需求触发、放在哪个 Package、详情在哪里”；禁止事项和验证只存在于相关子文档。
- 没有新增运行时代码、依赖、生成文件或空目录。
- 文档与 `CLAUDE.md`、`docs/architecture.md`、`docs/api-contracts.md` 的本地数据策略一致。
- `make harness-check` 通过。

## 验证命令

```bash
make harness-check
git diff --check
```

## 平台或环境限制

纯文档任务，不需要 Android/iOS 设备、Figma MCP 或 Marionette。不得读取或记录任务范围外的本机工程路径。

## 风险与待决问题

- 具体登录输入、Session/User Entity 字段和 Auth API 方法仍取决于后续 Figma 页面，不得在本任务中补写。
- `FixtureApiTransport` 的具体请求键和响应结构必须由首个真实 Auth/Catalog API 消费任务定义，不能在清册中预造 Endpoint。
- 是否持久化会话、购物车或收藏仍是独立产品决策，不因采用三个基础 Service 而自动启用。
