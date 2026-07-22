---
task: shoppe-profile-dashboard
status: passed
p0: 0
p1: 0
---

# Shoppe Profile Dashboard 执行审查

## P1：已登录 Auth Deep Link 的 Redirect 分支没有验收测试

- 位置：[`app/apps/demo/lib/router/demo_router.dart:21`](../../app/apps/demo/lib/router/demo_router.dart#L21)、[`app/apps/demo/test/router/demo_router_test.dart:21`](../../app/apps/demo/test/router/demo_router_test.dart#L21)、[`docs/tasks/done/shoppe-profile-dashboard.md:42`](../tasks/done/shoppe-profile-dashboard.md#L42)
- 问题：根 Redirect 已实现 `isAuth` 分支，但路由测试只覆盖未登录 `/profile`、已登录 Welcome、登出和未知 Route，没有覆盖“已登录直接访问 `/auth/...` 进入 `/profile`”。这正是任务卡明确要求的独立分支，当前全绿证据无法证明它在无匹配 Auth Route的当前阶段，以及后续注册/登录 Route 接入后都能正常工作。
- 影响：注册和登录任务将直接依赖这条守卫；如果 `matchedLocation`、Auth Route 结构或 Redirect 顺序发生变化，已登录用户可能落入 Auth 页面或错误页，而现有门禁仍会通过。
- 修法：在 `demo_router_test.dart` 增加已认证状态下以 `/auth/register` 或 `/auth/login` 冷启动的测试，断言最终 URI 为 `/profile`、Profile 页面可见且没有 Redirect loop/error；后续真实 Auth Route 接入时保留该根级回归测试。

## P2：Session 文档仍把已完成接线描述为后续工作

- 位置：[`docs/infrastructure/session.md:3`](../infrastructure/session.md#L3)、[`docs/infrastructure/session.md:16`](../infrastructure/session.md#L16)、[`docs/infrastructure/session.md:29`](../infrastructure/session.md#L29)、[`docs/infrastructure/session.md:42`](../infrastructure/session.md#L42)、[`docs/infrastructure/session.md:47`](../infrastructure/session.md#L47)
- 问题：当前实现已经由 Demo 组合根创建 `AuthStateCoordinator`、作为 GoRouter 唯一 `refreshListenable`、注入 Profile，并验证 Provider 释放；文档仍多处写成“由后续任务完成/补充”。
- 影响：后续 Agent 按基础模块索引加载该文档时会得到错误的完成状态，可能重复设计接线或漏读现有验证。
- 修法：回填当前真实消费者、Router/Profile 接线路径和现有验证命令；只把尚未实现的注册/登录成功回调保留为后续范围。

## 已确认边界

- `app_features` 使用公开 GetX 精简 fork，并锁定完整 Commit `7bfcd9c3711c8880ee730579724dabe54f4e2598`；Lockfile 的 `resolved-ref` 一致，Harness 有官方 GetX 回退失败 Fixture。
- Controller 通过构造函数接收 `ProfileDashboardApi` 与 `CurrentUserProvider`，`GetBuilder` 在本地模式启动 Controller 并显式调用 `onDelete()`，Provider Listener 在 `onClose()` 释放；未发现服务定位或 GetX 路由/Overlay 越界。
- Fixture Payload 和 Mapper 留在 `app_data`，Feature API 只暴露 Domain Entity；运行时代码扫描未发现 MCP URL、在线图片、跨 Feature 内部 import 或 Fixture Payload 泄漏。
- 页面使用单一 `CustomScrollView`，横向 Rail 有界，Bottom Navigation 固定且无未提供 Route；图片均为本地 PNG，Asset 解码测试通过。
- 共享颜色已进入 `AppColors`，Profile 私有商品/Story 组件没有提升到全局 UI 包。

## 验证

- 已读取：[`test-evidence/shoppe-profile-dashboard.log`](test-evidence/shoppe-profile-dashboard.log)，其中 `make check` 退出码为 0。
- 独立复跑：`TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_profile`，16 个测试通过。
- 独立复跑：`TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/router/demo_router_test.dart`，4 个测试通过。
- 独立复跑：`bash scripts/lint/repository-boundaries.sh`、`bash scripts/dart-tool.sh run tool/harness_check.dart`、`git diff --check`，均通过。

## 剩余风险

- 本轮未在真机/模拟器上做 Profile 视觉截图对比；375 x 812 的结构、布局尺寸和多视口无溢出由 Widget 测试覆盖，像素级视觉差异仍需人工核对。
- 注册与登录页面尚未实现，因此真实成功回调到 Profile 的端到端路径仍由后续任务完成；本报告只要求先锁住已经存在的根 Redirect 分支。

## 第二轮独立复审

- P0：0
- P1：0
- P2：0
- 状态：通过，可以归档。

首轮 1 个 P1 和 1 个 P2 均已关闭：

- `demo_router_test.dart` 新增已认证 `/auth/register` Deep Link 回归测试，断言最终 URI 为 `/profile`、Profile 内容可见、错误页不可见且没有未处理异常，覆盖了根 Redirect 的 Auth 分支。
- `session.md` 已回填根 Router、`AuthStateCoordinator` 与 Profile Provider 的真实接线和验证路径，同时明确注册/登录页面成功回调仍属于后续任务，没有提前声明未实现流程完成。

复审读取追加后的测试证据，确认 Router 聚焦测试由 4 个增加到 5 个且全部通过；独立复跑同一测试同样 5 个通过。`make analyze`、`make harness-check` 和 `git diff --check` 的追加证据均通过，本轮独立执行 `harness-check` 与 `git diff --check` 也通过，未发现新的 P0、P1 或 P2。
