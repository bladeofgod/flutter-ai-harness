# Session 基础能力

> 状态：`AuthService`、`UserService`、`AuthStateCoordinator` 均已批准但未实现。

[返回基础模块索引](../infrastructure-modules.md)

本文件只覆盖 App 壳中的登录态和当前用户状态。具体输入、Session/User Entity 字段和页面行为由首个真实 Auth 或 Profile 任务确定。

## AuthService

- 决策状态：已批准。
- 实现状态：未实现。
- 目标所有者：`apps/demo` 全局 Service 层，只在组合根注册。
- 首个消费者：首个 Auth 流程已经明确 Session 定义和登录态变化时实现。
- 采用模式：管理 `isLoggedIn` 和当前内存 Session；当前 App 重启后恢复未登录状态，不读取或写入安全存储。状态写入只由 `AuthStateCoordinator` 编排，不独立向 Router 发出通知。
- 禁止耦合：不得包含 Access/Refresh Token 刷新、游客 Token、账号切换、IM/RTC 登录、服务端错误码 UI 编排、页面、Dialog 或 Route 跳转。
- 启用验证：覆盖初始未登录、Session 设置、清除和重复写入；登录态参与 Route Redirect 时由 `AuthStateCoordinator` 的测试覆盖通知与路由行为。

## UserService

- 决策状态：已批准。
- 实现状态：未实现。
- 目标所有者：`apps/demo` 全局 Service 层，与 `AuthService` 分离。
- 首个消费者：首个 Auth 或 Profile 流程已经明确 User Entity 字段时实现。
- 采用模式：管理当前 User Entity 的内存快照、更新和清除。状态写入只由 `AuthStateCoordinator` 编排，不独立实现 Feature 的可观察契约。
- 禁止耦合：不得预置无消费者字段，不负责认证、Token、导航、页面状态或持久化；Feature API 实现不得反向依赖壳工程 Service。
- 启用验证：覆盖初始空用户、设置、更新和清除，并验证 Feature 不依赖壳工程 Service。

## AuthStateCoordinator

- 决策状态：已批准。
- 实现状态：未实现。
- 目标所有者：`apps/demo` 组合根可见的认证状态协调层，组合 `AuthService` 与 `UserService`。
- 首个消费者：首个 Auth 成功流程与受认证保护的 Profile Route 同批实现。
- 采用模式：作为 Session/User 的唯一公共写入入口，同时实现 GoRouter 刷新 `Listenable` 和 Feature 所需的只读 `CurrentUserProvider`。认证事务先写入 ID 匹配的 User 与 Session，登出事务先清空二者，再各发送一次共享通知。
- 状态不变量：每次对外通知时，已登录必须同时存在 User 和 Session 且 User ID 匹配；未登录必须同时不存在 User 与 Session。不得公开可绕过 Coordinator 的单 Service 写入路径。
- 禁止耦合：不负责调用 Auth API、保存密码、显示 UI、执行导航或持久化 Session；Feature 不 import、查找或持有 Coordinator 类型。
- 启用验证：监听认证与登出的完整通知序列，断言单次事务只通知一次且没有不一致中间快照；覆盖重复认证/登出的幂等性、Router Redirect 和 `CurrentUserProvider` 释放。

实现任一能力后，在本文件补充真实模块路径、公共 API、消费者、生命周期和精确验证命令。
