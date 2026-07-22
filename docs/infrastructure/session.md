# Session 基础能力

> 状态：`AuthService`、`UserService`、`AuthStateCoordinator`、根 Router、注册/登录成功回调与 Profile 注入均已实现。

[返回基础模块索引](../infrastructure-modules.md)

本文件只覆盖 App 壳中的登录态和当前用户状态。具体输入、Session/User Entity 字段和页面行为由首个真实 Auth 或 Profile 任务确定。

## AuthService

- 决策状态：已批准。
- 实现状态：已实现。
- 目标所有者：`apps/demo` 全局 Service 层，只在组合根注册。
- 模块路径：`app/apps/demo/lib/auth/auth_state.dart`。
- 公共只读 API：`session`、`isLoggedIn`；写入方法保持 library-private，只允许 Coordinator 调用。
- 首个消费者：Shoppe Auth 结果与受认证保护的 Profile Route；当前由根组合装配创建并交给 `AuthStateCoordinator` 管理。
- 采用模式：管理 `isLoggedIn` 和当前内存 Session；当前 App 重启后恢复未登录状态，不读取或写入安全存储。状态写入只由 `AuthStateCoordinator` 编排，不独立向 Router 发出通知。
- 生命周期：由壳工程组合根创建，随 App 进程存在；自身不持有 Listener 或需单独释放的资源。
- 禁止耦合：不得包含 Access/Refresh Token 刷新、游客 Token、账号切换、IM/RTC 登录、服务端错误码 UI 编排、页面、Dialog 或 Route 跳转。
- 启用验证：`app/apps/demo/test/auth/auth_state_test.dart` 覆盖初始状态、认证、登出和幂等性；`app/apps/demo/test/router/demo_router_test.dart` 覆盖 Route Redirect。

## UserService

- 决策状态：已批准。
- 实现状态：已实现。
- 目标所有者：`apps/demo` 全局 Service 层，与 `AuthService` 分离。
- 模块路径：`app/apps/demo/lib/auth/auth_state.dart`。
- 公共只读 API：`currentUser`；写入方法保持 library-private，只允许 Coordinator 调用。
- 首个消费者：Shoppe Auth/Profile 的 `UserEntity`；根组合装配通过同一个 `AuthStateCoordinator` 向 Profile Controller 注入只读 `CurrentUserProvider`。
- 采用模式：管理当前 User Entity 的内存快照、更新和清除。状态写入只由 `AuthStateCoordinator` 编排，不独立实现 Feature 的可观察契约。
- 生命周期：与 `AuthService` 由同一个 Coordinator 持有，随 App 进程存在。
- 禁止耦合：不得预置无消费者字段，不负责认证、Token、导航、页面状态或持久化；Feature API 实现不得反向依赖壳工程 Service。
- 启用验证：`app/apps/demo/test/auth/auth_state_test.dart` 覆盖设置、匹配用户更新、拒绝不匹配用户和清除。

## AuthStateCoordinator

- 决策状态：已批准。
- 实现状态：已实现。
- 目标所有者：`apps/demo` 组合根可见的认证状态协调层，组合 `AuthService` 与 `UserService`。
- 模块路径：`app/apps/demo/lib/auth/auth_state.dart`。
- 公共 API：`authenticate(AuthResult)`、`updateCurrentUser(UserEntity)`、`logout()`、`session`、`isLoggedIn` 和 `CurrentUserProvider.value`；同时实现 `Listenable`。
- 首个消费者：受认证保护的 Profile Route 与 Shoppe Auth 成功回调；根组合装配、Router 刷新、注册/登录认证提交和 Profile Provider 注入均已接线。
- 采用模式：作为 Session/User 的唯一公共写入入口，同时实现 GoRouter 刷新 `Listenable` 和 Feature 所需的只读 `CurrentUserProvider`。认证事务先写入 ID 匹配的 User 与 Session，登出事务先清空二者，再各发送一次共享通知。
- 生命周期：由壳工程组合根创建一个实例并交给 Router/Profile，根 App 销毁时调用 `dispose()`；页面切换和登出不销毁实例。
- 状态不变量：每次对外通知时，已登录必须同时存在 User 和 Session 且 User ID 匹配；未登录必须同时不存在 User 与 Session。不得公开可绕过 Coordinator 的单 Service 写入路径。
- 禁止耦合：不负责调用 Auth API、保存密码、显示 UI、执行导航或持久化 Session；Feature 不 import、查找或持有 Coordinator 类型。
- 启用验证：`app/apps/demo/test/auth/auth_state_test.dart` 监听完整通知序列，断言单次事务只通知一次且没有不一致中间快照；`app/apps/demo/test/router/demo_router_test.dart` 覆盖未登录/已登录 Redirect 与登出；`app/packages/app_features/test/feature_profile/profile_dashboard_page_test.dart` 覆盖 Provider 更新和页面销毁时释放监听。

验证命令：

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/auth/auth_state_test.dart
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/router/demo_router_test.dart
TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_profile
```

实现任一能力后，在本文件补充真实模块路径、公共 API、消费者、生命周期和精确验证命令。
