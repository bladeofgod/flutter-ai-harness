---
name: getx-patterns
description: "适用：代码使用 GetxController、GetxService、Rx、Obx、GetBuilder、Get.find、Bindings 或 Worker。不适用：GetX 路由、Dialog、Snackbar，或 Controller 内隐式查找 API。触发词：GetX、Obx、.obs、Rx、Get.find、GetxService、Worker、Binding。"
paths: ["app/apps/**/lib/**", "app/packages/**/lib/**"]
---

# GetX 状态与 DI 模式

本仓库使用公开、固定 Commit 的 GetX 精简版 fork，只提供状态管理和轻量依赖注册。路由归 `go_router`，UI Overlay 使用 Flutter/Context 所有的 API。

## Fork 依赖与能力边界

所有真实消费者必须使用同一个依赖源，不得写成 `get: ^4.x`：

```yaml
get:
  git:
    url: https://github.com/bladeofgod/getx.git
    ref: 7bfcd9c3711c8880ee730579724dabe54f4e2598
```

精简 fork 保留 `GetxController`、`GetxService`、`Rx`、`Obx`、`GetBuilder`、Worker、轻量 DI，以及适配 `go_router` 页面生命周期的 `Binder<T>`。

以下官方 GetX 全家桶能力已经移除，不得假设存在：

- `GetMaterialApp`、`GetPage` 和 GetX 导航 API
- `Get.snackbar`、`Get.dialog`、`Get.bottomSheet`
- `Translations`、Middleware、`GetConnect`
- `Get.context`、`Get.overlayContext`

页面级 Controller 可由路由装配点显式构造后交给页面管理；需要服务定位与自动释放时，优先在 `GoRoute.builder` 使用 fork 的 `Binder<T>`。两种方式都必须保证 Controller 只创建一次并随 Route 销毁。

## 依赖规则

- Controller 通过构造函数接收必需 API。
- API 在 Route 或模块装配点解析。
- Controller 内 `Get.find` 只允许查找已记录的全局 `GetxService`。
- UI 不得持有 API，也不得把服务定位器结果沿 Widget Tree 传递；交互走 Controller Facade。

## 状态选择

- UI 不观察的值使用普通字段。
- 明确的粗粒度刷新使用 `GetBuilder`。
- 独立细粒度状态使用 `Rx`/`Obx`。
- `Obx` 只包裹读取 `.value` 的最小子树，不包整页。

## 生命周期

- 页面 Controller 随 Route 创建和销毁。
- 全局 Service 只注册一次，不持有页面 `BuildContext`。
- 在 `onClose` 或真实所有者中释放 Worker、Stream、Timer、FocusNode 和 TextController。
- 副作用进入 Worker 或显式方法，不在响应式 Widget Builder 中执行。

## 测试

直接用 Fake/Mock 构造 Controller；teardown 中重置全局 GetX 状态。必需 API 的测试不得依赖服务定位器。

该 fork 的 `Obx` 通过 microtask 调度 `markNeedsBuild`。Widget Test 在测试代码中直接修改 Rx 后，应先让 microtask 入队，再推进重建帧（通常连续两次 `pump()`，有持续异步任务时使用有界的 `pumpAndSettle()`），不要在首个 `pump()` 后立即断言新 UI。

修改依赖 lint 时读取 `.claude/memories/api-injection-gate.md`。
