---
name: getx-patterns
description: "适用：代码使用 GetxController、GetxService、Rx、Obx、GetBuilder、Get.find、Bindings 或 Worker。不适用：GetX 路由、Dialog、Snackbar，或 Controller 内隐式查找 API。触发词：GetX、Obx、.obs、Rx、Get.find、GetxService、Worker、Binding。"
paths: ["app/apps/**/lib/**", "app/packages/**/lib/**"]
---

# GetX 状态与 DI 模式

只使用公开 GetX 包提供状态管理和轻量依赖注册。路由归 `go_router`，UI Overlay 使用 Flutter/Context 所有的 API。

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

修改依赖 lint 时读取 `.claude/memories/api-injection-gate.md`。
