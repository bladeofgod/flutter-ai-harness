---
task: shoppe-auth-local-foundation
status: passed
p0: 0
p1: 0
---

# Shoppe Auth 本地基础能力执行审查

## 首轮结论

- P0：0
- P1：2
- P2：1
- 状态：需要修复后复审。

## P1：AuthFailure 映射丢失 Transport 原始调用栈

- 位置：`app/packages/app_data/lib/src/auth/auth_local.dart`
- 问题：`ApiClient` 已把 Transport 原始 `StackTrace` 保存到 `ApiFailure`，DataSource 使用普通 `throw _mapFailure(failure)` 后，最终栈只指向失败映射位置。
- 影响：真实 Transport 故障跨层后缺少原始定位信息，违反异常转换保留 Stack Trace 的项目约束。
- 修法：统一通过窄 `_throwMappedFailure` 抛出；存在原始栈时使用 `Error.throwWithStackTrace`，并增加最终 `AuthFailure` 栈来源测试。

## P1：API 与 Mapper 使用宽 `on Object` 掩盖编程错误

- 位置：`app/packages/app_core/lib/network/api_client.dart`、`app/packages/app_data/lib/src/auth/auth_local_mapper.dart`
- 问题：任意 `Error` 或未声明异常会被伪装成可恢复的 Transport/invalidResponse 失败。
- 影响：`AssertionError`、`NoSuchMethodError`、裸 `StateError` 等代码缺陷可能无法暴露。
- 修法：ApiClient 只捕获明确的 `UnknownApiRequestException` 和 `ApiTransportException`；Mapper 只捕获无效 Payload 实际产生的 `FormatException`、`ArgumentError` 等解析异常。测试同时证明包装异常被映射、裸编程错误继续抛出。

## P2：Coordinator 可共享同一组 Service

- 位置：`app/apps/demo/lib/auth/auth_state.dart`
- 问题：公开注入参数允许多个 Coordinator 共享 AuthService/UserService；一个 Coordinator 修改后，另一个实例的 getter 静默变化但不会通知自身监听者。
- 修法：由每个 Coordinator 独占创建内部 Service，移除公开 Service 注入参数，从结构上保证唯一通知所有者。

## 首轮证据核对

- 首次 `make analyze` 发现并记录错误的 `const AuthSession` 调用，修复后的同命令通过。
- app_core、app_data、app_features、demo 聚焦测试通过。
- 修复测试发现器后，第二次 `make test` 已覆盖 demo、app_core、app_data、app_features、app_ui。
- `make lint`、`make harness-check`、`make bootstrap`、`make format`、`git diff --check` 通过。
- 证据文件：[`test-evidence/shoppe-auth-local-foundation.log`](test-evidence/shoppe-auth-local-foundation.log)

## 剩余边界

- Route、Profile 注入和根 App 中 Coordinator 的实际单实例装配属于后续 Profile Dashboard 任务。
- 当前没有真实远程 Transport；异常包装契约由 Fixture 和测试 Transport 验证。

## 第二轮独立复审

- P0：0
- P1：0
- P2：0
- 状态：通过，可以归档。

首轮 2 个 P1 和 1 个 P2 均已关闭：

- ApiClient 只捕获明确的未知请求与 `ApiTransportException`，裸编程错误继续抛出。
- DataSource 映射 `AuthFailure` 时保留 Transport 原始 Stack Trace；Mapper 只捕获具体解析异常并显式验证内存图片字节范围。
- 每个 `AuthStateCoordinator` 独占内部 AuthService/UserService，不再允许多个 Coordinator 共享状态源。

复审确认聚焦测试、`make analyze`、全 Workspace `make test`、`make lint`、`make harness-check`、`make format` 和 `git diff --check` 最终均通过，未发现新的 P0、P1 或 P2。
