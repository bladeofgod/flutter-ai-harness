# Session 基础能力

> 状态：`AuthService`、`UserService` 均已批准但未实现。

[返回基础模块索引](../infrastructure-modules.md)

本文件只覆盖 App 壳中的登录态和当前用户状态。具体输入、Session/User Entity 字段和页面行为由首个真实 Auth 或 Profile 任务确定。

## AuthService

- 决策状态：已批准。
- 实现状态：未实现。
- 目标所有者：`apps/demo` 全局 Service 层，只在组合根注册。
- 首个消费者：首个 Auth 流程已经明确 Session 定义和登录态变化时实现。
- 采用模式：管理 `isLoggedIn`、当前内存 Session 和登录态变化；当前 App 重启后恢复未登录状态，不读取或写入安全存储。
- 禁止耦合：不得包含 Access/Refresh Token 刷新、游客 Token、账号切换、IM/RTC 登录、服务端错误码 UI 编排、页面、Dialog 或 Route 跳转。
- 启用验证：覆盖初始未登录、登录、登出、重复状态切换和事件通知；登录态参与 Route Redirect 时增加路由测试。

## UserService

- 决策状态：已批准。
- 实现状态：未实现。
- 目标所有者：`apps/demo` 全局 Service 层，与 `AuthService` 分离。
- 首个消费者：首个 Auth 或 Profile 流程已经明确 User Entity 字段时实现。
- 采用模式：管理当前 User Entity 的内存快照、更新和清除。登录成功后由壳工程回调或 Use Case 同时更新 `AuthService` 与 `UserService`。
- 禁止耦合：不得预置无消费者字段，不负责认证、Token、导航、页面状态或持久化；Feature API 实现不得反向依赖壳工程 Service。
- 启用验证：覆盖初始空用户、设置、更新、清除和登出协作，并验证 Feature 只依赖业务 API 或回调。

实现任一能力后，在本文件补充真实模块路径、公共 API、消费者、生命周期和精确验证命令。
