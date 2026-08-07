---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy: []
securityReview: required
---

# 为 Session Reset 注册增加解除生命周期

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 3 项已确认方向。
- `app/apps/demo/lib/auth/auth_state.dart` 的 `AuthStateCoordinator.attachSessionReset` 当前把闭包永久组合到
  `_onSessionReset`。
- `app/apps/demo/lib/demo_app.dart` 会把 `FeaturesRegistry.resetUserSession` 注册到可能由外部持有的
  Coordinator，但 `DemoApp.dispose` 不解除注册。
- `docs/infrastructure/session.md`、`app/apps/demo/test/auth/auth_state_test.dart` 和
  `app/apps/demo/test/demo_app_test.dart` 的现有生命周期约束。

## 目标

- 让每次 Session Reset 注册返回只解除自身的幂等句柄，避免已卸载 `DemoApp` 继续被外部 Coordinator
  持有或在后续 logout 中调用旧 Registry。
- 保持认证状态事务、通知次数、reset 调用顺序和内部/外部所有权语义不变。

## 非目标

- 不改变登录、登出、Router redirect、Feature reset 的产品行为。
- 不把 Coordinator 下沉到 Feature，不引入服务定位器或持久 Session。
- 不让 `DemoApp` 释放外部持有的 Coordinator 或 Registry。

## 实现要求

1. `attachSessionReset` 返回 `VoidCallback` 或等价的聚焦解除句柄。解除必须幂等、只移除对应注册，即使
   注册了同一函数对象多次也不能误删其它条目。
2. 保留构造参数 `onSessionReset` 的兼容语义；内部使用有稳定注册顺序的回调集合。logout 分发使用快照：
   分发中解除不跳过其它既有回调，新注册项只能从下一次有效 logout 起生效。
3. `DemoApp` 保存自己的解除句柄，并在 Router dispose 后、Registry dispose 前调用；无论 Coordinator/
   Registry 分别由内部还是外部持有，都必须解除 Demo 自己的注册。
4. 重复 dispose/解除不得抛错。内部 Coordinator 仍由 App 最后 dispose；外部 Coordinator 卸载后继续有效，
   但 logout 不得触碰旧 Registry。
5. 更新 Session 基础能力文档，准确说明注册句柄、所有者和销毁顺序。

## 同时编写的测试

- 单元测试覆盖注册顺序、只解除一个、重复解除、同一 callback 多次注册、自解除、分发中新增和 logout
  幂等。
- Widget 测试覆盖挂载、卸载、重新挂载，以及内部/外部 Coordinator x 内部/外部 Registry 的所有权组合。
- 使用跟踪 Registry 证明卸载后的外部 Coordinator logout 不调用旧 reset，重新挂载只调用新注册一次；
  外部对象不被 App dispose。

## 验收与验证

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/auth/auth_state_test.dart
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/demo_app_test.dart
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/router/demo_router_test.dart
make format
make analyze
make lint
make harness-check
git diff --check
```

## 环境限制

纯 Flutter 生命周期任务，不需要设备或原生 SDK。Widget 测试必须显式等待异步 Registry dispose，不能用
未观察的 `unawaited` 清理结果制造假通过。
