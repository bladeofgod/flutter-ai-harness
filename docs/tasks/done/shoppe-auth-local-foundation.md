---
executor: task-executor
blockedBy: []
---

# 建立 Shoppe 本地 Auth、Session 与 User 基础能力

## 背景

Shoppe 注册和登录设计已经确定账号识别、8 位密码、当前用户头像/名称以及登录成功后的 Profile 行为。它们是 `ApiClient`、`AuthService` 和 `UserService` 的首个真实消费者，满足 [`docs/infrastructure-modules.md`](../../infrastructure-modules.md) 记录的实现门槛。

本任务先建立平台无关的本地 Auth 数据链路和壳工程会话能力，不实现任何页面。后续注册、登录和 Profile 任务只依赖 Domain Entity、业务 API 与壳工程回调，不直接读取 Fixture Payload 或 Feature 内部实现。

## 输入

- [`CLAUDE.md`](../../../CLAUDE.md)
- [`docs/architecture.md`](../../architecture.md)
- [`docs/api-contracts.md`](../../api-contracts.md)
- [`docs/infrastructure/network.md`](../../infrastructure/network.md)
- [`docs/infrastructure/session.md`](../../infrastructure/session.md)
- [`docs/figma/shoppe-auth-flow-design-context.md`](../../figma/shoppe-auth-flow-design-context.md)

## 目标与范围

1. 在 `app_core` 实现传输中立的 `ApiRequest`、`ApiResponse`、`ApiFailure`、`ApiTransport` 和 `ApiClient`。`ApiClient` 只负责委托、统一成功/失败边界和未知请求错误，不 import 业务 Entity 或解析具体 Payload。敏感请求值必须使用显式 Secret 包装或等价红线机制；`ApiRequest`、`ApiFailure` 和异常字符串化不得展开敏感 Payload。
2. 在 `app_data` 实现确定性、进程内 `FixtureApiTransport`。首批稳定请求键为账号查询、注册和登录；不得启动 HTTP Server、引入 Dio 或伪造 Proto。
3. 在 `app_data` 定义 Auth 当前真实需要的 Domain 类型：
   - `UserEntity`：稳定 ID、displayName、email、国家区号、phone、头像 Value Object。
   - `AuthSession`：稳定 session ID 与 user ID，不包含 Access/Refresh Token。
   - 注册/登录输入 Value Object 与成功结果；密码使用手写不可变 Password/Secret Value Object，`toString`、诊断属性和异常输出固定脱敏，不使用会自动展开字段的 Freezed `toString`。密码只存在请求输入和私有 Fixture 认证记录中，不进入 `UserEntity`、`AuthSession`、日志或错误文本。
4. `UserAvatar` 必须保持 Flutter/Plugin 中立，支持 Fixture Asset 标识或可选的内存图片字节；不得暴露 `ImageProvider`、`XFile`、绝对文件路径或平台 URI。
5. 在 `app_data` 创建 Auth LocalDataSource、Fixture Payload 和 Mapper。初始账号使用明确的 Demo 数据，例如 `romina@example.com`、8 位测试密码 `shoppe01`、Romina 名称和设计头像；这些值是公开测试 Fixture，不得被描述为真实凭据。
6. 注册在当前进程中新增账号；重复 Email 返回稳定业务失败。App 重启后恢复初始 Fixture，注册账号和图片不持久化。
7. 在 `app_features/lib/api/` 定义窄 `AuthApi` 和 `CurrentUserProvider`。AuthApi 至少支持 `findAccountByEmail`、`register` 和 `login`，公共方法只使用 Domain Entity/Value Object；`CurrentUserProvider` 以 `ValueListenable<UserEntity?>` 或等价只读可观察契约暴露当前用户，不暴露壳工程 Service 类型。在 `feature_auth/api/` 提供本地 Auth 实现。
8. 创建 `app_features/lib/features_registry.dart` 作为公开装配入口，由它绑定 `ApiClient`、Fixture Transport、DataSource 和本地 Auth API；`apps/demo` 不 import `feature_auth/api/`。
9. 在 `apps/demo` 实现职责分离的 `AuthService`、`UserService`，并增加唯一写入与通知入口 `AuthStateCoordinator`：
   - `AuthService` 只管理内存 Session 和 `isLoggedIn`；不独立驱动 Router 刷新，也不向 Coordinator 之外暴露会产生通知的写入口。
   - `UserService` 只管理当前 `UserEntity`；不独立实现 Feature 可观察契约，也不向 Coordinator 之外暴露写入口。
   - `AuthStateCoordinator` 组合两个 Service，同时实现 GoRouter `refreshListenable` 所需的窄 `Listenable` 和 `CurrentUserProvider`。Feature 只接收后者，不 import 或 `Get.find<AuthStateCoordinator>()`。
   - 登录/注册事务先写入相互匹配的 User 与 Session，再对外发送一次共享通知；登出事务先清空两者，再发送一次共享通知。每次对外通知都必须满足：已登录时当前用户非空且 User ID 与 Session User ID 一致，未登录时 Session 与当前用户均为空。
   - 重复提交相同认证结果或重复登出保持幂等；不得存在可以绕过 Coordinator 单独改变登录态或当前用户的公共调用路径。
10. 不创建 `ServiceInitializer`、SecureStorage、Drift、NetworkService、Token 刷新、账号切换、页面提示或 Route。Service 不持有 `BuildContext`。
11. 回填 `docs/infrastructure-modules.md`、`docs/infrastructure/network.md` 和 `docs/infrastructure/session.md` 的真实模块路径、公共 API、消费者、生命周期、实现状态与验证命令，不复制完整数据链路。
12. 如新增 GetX 依赖，只允许使用仓库约定的公开精简 fork 并固定完整 Commit；把 `Get.find` 限定在壳工程组合根，业务 Controller 仍通过构造函数接收 `AuthApi`。

## 同批测试

- `app_core`：请求委托、成功/失败、未知请求键、Transport 异常归一化；ApiRequest/Failure/异常字符串化不会展开 Secret 或敏感 Payload。
- `app_data`：初始 Fixture、账号查询、正确/错误密码、注册、重复账号、重启等价初始状态、Mapper 和 Payload 不泄漏；Password、认证输入和 Fixture 记录的 `toString` 固定脱敏。
- `app_features`：本地 `AuthApi` 只返回 Domain 类型，输入规范化和失败映射稳定。
- `apps/demo`：AuthService/UserService 初始状态与内部读写；AuthStateCoordinator 登录、注册、登出、重复切换和释放。监听每次通知并断言不存在“已登录但当前用户为空/不匹配”或“已登出但仍有用户”的中间快照，单次认证/登出事务只产生一次 Router/Provider 共享通知。Service 测试是补充，不能替代 `app_core`/`app_data` 的 Secret 脱敏测试。
- 架构测试：壳工程只使用 Registry 公开入口，公共 API/Controller 不 import Fixture 或生成类型。

## 验收标准

- Auth 数据链路为 `Controller -> AuthApi -> LocalDataSource -> ApiClient -> FixtureApiTransport`，返回路径在 `app_data` 内完成 Payload 到 Domain 映射。
- `ApiClient`、`AuthService`、`UserService`、`AuthStateCoordinator` 从“已批准、未实现”更新为具有真实消费者的“已实现”。
- Demo 账号、8 位密码与注册行为完全确定且无随机延迟；密码不出现在日志、证据、Semantics、Entity 或 Session。
- 没有 UI、Route、真实网络、Proto、数据库或持久化实现。
- 受影响包测试、静态分析、边界 lint 和 Harness 检查通过。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
make harness-check
git diff --check
```

## 风险与限制

- 本地明文 Fixture 密码只服务公开 Demo，不代表生产认证方案。
- 当前 Session 不跨重启；不得因测试便利提前引入安全存储。
- Profile Dashboard 数据不属于本卡，由 `shoppe-profile-dashboard` 扩展同一 Fixture Transport 和 Registry。

## 后续规则调整

[`demo-stateless-auth-policy`](demo-stateless-auth-policy.md) 已覆盖本卡第 5、6 条中的本地账号行为：当前 Auth Fixture 不再保存注册账号或私有密码记录，而是允许任意有效 Email 按确定性规则查询和登录。注册仍返回当次完整用户快照，所选头像只进入当前会话；公共重复账号、账号不存在失败契约继续保留给未来真实 API 和测试 Fake。
