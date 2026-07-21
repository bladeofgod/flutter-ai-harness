---
executor: task-executor
blockedBy: []
uiSpec: not-required
---

# Demo 基础 Service 设计清册

## 背景

`AI Harness Shoppe` 需要通过真实业务链路展示基础设施、全局会话和当前用户分层。用户已批准在 Demo 中采用 `ApiClient`、`AuthService` 和 `UserService`，但当前没有真实 Endpoint、Wire Contract、登录页面行为或跨重启持久化需求。

三个 Service 必须保持模板中立，不得绑定 Proto 信封、Token 刷新、SecureStorage、IM、账号切换、私有缓存或平台环境。本任务先把它们的 Demo 化边界写入基础模块清册；具体运行时代码必须与首个 Auth 或 Catalog 消费任务一起创建，避免无消费者实现。

## 输入与事实来源

- `CLAUDE.md`
- `docs/architecture.md`
- `docs/api-contracts.md`
- `docs/figma-links.md`
- `docs/infrastructure-modules.md`
- 用户批准的本地 Mock 和三个基础 Service 决策

## 目标

- 将 `docs/infrastructure-modules.md` 从占位文档更新为可执行的基础能力采用清册。
- 将 `ApiClient`、`AuthService` 和 `UserService` 分别标记为“决策状态：已批准、实现状态：未实现”，并固化职责、依赖方向、数据流和实现门槛。
- 明确其他基础能力何时采用、延后以及禁止引入哪些业务耦合，为后续 Figma Feature 任务提供统一检查入口。

## 非目标

- 不在本任务中创建 ApiClient、AuthService、UserService 或 ServiceInitializer 运行时代码。
- 不引入 GetX、Dio、Proto、Drift、Secure Storage、Shared Preferences 或 Connectivity 依赖。
- 不定义 Product、User、Token、Session、Cart 等尚未由具体页面确认字段的 Entity。
- 不生成业务 API、Fixture、Route、Controller、页面或 UI 行为 Spec。
- 不引入私有 Endpoint、业务错误码、SDK 标识、未公开协议结构、账号切换或 IM/RTC 编排。

## 具体要求

1. 将 `docs/infrastructure-modules.md` 的文档状态改为“维护中，当前无已实现公共模块”，并记录当前 Workspace Package 仍是职责边界；清册结束占位状态后，同步移除 `CLAUDE.md` 重要参考中的“占位”说明。
2. 增加基础能力决策矩阵，至少包含：日志门面、运行环境、ApiClient、AuthService、UserService、安全存储、普通 KV、数据库生命周期、网络状态和全局 Service 初始化器。矩阵必须使用独立的“决策状态”和“实现状态”字段，不得用单个“采用状态”混合表达。
3. 每项能力必须记录：目标所有者、决策状态、实现状态、首个真实消费者条件、采用的设计模式、禁止引入的业务耦合，以及启用时需要补充的测试或门禁。决策状态只允许“已批准、延后、禁止”；实现状态只允许“未实现、已实现”。
4. `ApiClient` 必须记录为“已批准、随首个 Auth/Catalog API 消费者实现”，并遵守：
   - 位于 `app_core`，只负责请求编排、传输委托、统一结果和错误边界，不引用业务 Entity。
   - 通过构造函数接收 `ApiTransport`；当前由 `app_data` 提供确定性 `FixtureApiTransport`，未来真实 API 使用 `DioApiTransport`。
   - Fixture Transport 使用本地结构化数据和稳定请求键，不启动伪 HTTP Server、不依赖测试 Mock Adapter、不伪造 Proto。
   - `app_data` 的 LocalDataSource 和 Mapper 负责把 Fixture Payload 转换为 Domain Entity；Feature API 实现不得接收或解析原始 Payload。
5. `AuthService` 必须记录为“已批准、随首个 Auth 流程实现”，并遵守：
   - 位于 `apps/demo` 的全局 Service 层，管理 `isLoggedIn`、当前内存 Session 和登录态变化。
   - 当前 App 重启后恢复未登录状态，不读取或写入 SecureStorage。
   - 不包含 Access/Refresh Token 刷新、游客 Token、账号切换、IM/RTC 登录或服务端错误码 UI 编排。
   - 认证错误事件和页面/Dialog/路由编排不得塞入 AuthService。
6. `UserService` 必须记录为“已批准、随首个 Auth/Profile 消费者实现”，并遵守：
   - 位于 `apps/demo` 的全局 Service 层，与 AuthService 分离，管理当前用户 Entity 的内存快照、更新和清除。
   - 用户 Entity 字段由具体 Figma 页面和业务流程决定，不预置无消费者字段。
   - 登录成功后由壳工程回调或 Use Case 同时更新 AuthService 与 UserService；Feature API 实现不得反向依赖壳工程 Service。
7. 清册必须给出计划链路：

   ```text
   Feature Controller → Abstract API → Local API Impl
                      → LocalDataSource
                      → ApiClient → FixtureApiTransport → Fixture
                      → LocalDataSource / Mapper → Domain Entity
                      → 壳工程回调 / Use Case
                      → AuthService + UserService
   ```

8. Secure Storage、KV 和 Drift 分别由敏感持久化、普通跨重启持久化和结构化迁移需求触发；当前内存状态不触发。NetworkService 只有远程请求或明确联网差异行为出现时才创建。
9. ServiceInitializer 只编排已经存在且确需启动期初始化的全局 Service；在 AuthService/UserService 实现任务之前不得创建空初始化框架。
10. 日志能力只有出现两个以上生产消费者、统一错误采集或 App Operator 证据需求时才下沉；不得预置业务标签或无消费者静态门面。
11. 后续任务创建基础 Service 时必须先查清册，并在同一任务中回填模块路径、公共 API、消费者、生命周期和验证命令。
12. 文档不得包含本机绝对路径、内部工程名称、私有域名、凭据、真实账号或不可公开的协议值。

## 同时编写的测试

- 本任务只修改文档，不新增应用测试。
- 使用 `make harness-check` 验证 Markdown 链接、任务卡结构和敏感路径边界。

## 验收标准

- `docs/infrastructure-modules.md` 不再是占位状态，并包含完整的基础能力决策矩阵。
- `CLAUDE.md` 的重要参考准确反映清册已进入维护状态，不再标记为占位。
- ApiClient、AuthService 和 UserService 的决策状态均为“已批准”、实现状态均为“未实现”，并具有可执行的实现边界。
- 只有后续消费者任务创建运行时代码并回填模块路径、公共 API、生命周期和验证结果后，能力的实现状态才能改为“已实现”。
- 清册能够回答每项能力“现在是否实现、由什么需求触发、放在哪个 Package、禁止引入什么”。
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
