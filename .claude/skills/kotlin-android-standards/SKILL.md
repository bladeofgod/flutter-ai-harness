---
name: kotlin-android-standards
description: "适用：编写或审查 Android Kotlin Native Module、Bridge Adapter、Host 接线、Manifest、Gradle 和原生 UI。不适用：Swift/iOS、Dart Client 或 Wire Contract 设计。触发词：Kotlin、Android、Gradle、Manifest、Coroutine、Flow、CameraX、Activity。"
paths: ["app/native/android/**", "app/apps/*/android/**", "app/packages/*/android/**"]
---

# Kotlin / Android 编码规范

## API 与边界

- 默认使用最小可见性；只让真实消费者需要的类型进入 `public` API。
- 公共 API 使用非空、带类型的 Kotlin Model 和稳定错误，不暴露 Flutter、Wire Map、Host
  类型或不必要的 Android SDK 对象。
- 使用构造函数注入协作者、`CoroutineDispatcher`、Clock 和 Framework Wrapper；生产代码
  不直接查找全局依赖。
- Native Module 不 import Flutter；Flutter 类型、Channel DTO 和错误映射只留在 Bridge Adapter。
- 避免 `!!`、平台类型扩散和宽泛 `Any`；在系统或 Java 边界立即完成空值和类型校验。

## 并发与生命周期

- 使用由明确所有者提供的 `CoroutineScope` 和结构化并发；不创建 `GlobalScope` 或无所有者任务。
- 注入 I/O、CPU 和测试 Dispatcher；只在 Android UI/System API 要求时切到 Main Dispatcher。
- Flow 明确冷/热语义、重放策略和收集生命周期；UI 收集绑定可见生命周期并可取消。
- 取消必须继续传播，不把 `CancellationException` 映射成普通失败。
- Activity、Fragment、Service、Engine detach 和配置变化时，资源所有者必须确定地停止并释放。
- close、stop、cancel 和 detach 可重复调用，并覆盖并发竞态。

## Android 工程

- Manifest、权限和组件声明保持最小；导出组件、Intent 和 URI 输入必须显式验证。
- Native Module 的 Gradle 依赖声明在模块自身，Bridge Adapter 只声明对 Module 的 project dependency。
- UI 状态由单一所有者管理；不得在 View/Composable 中启动无法取消的能力任务。
- 底层异常可以保留为内部 cause，对外只暴露稳定、可测试且不含敏感详情的错误。

## 验证

运行 Kotlin 单元测试和受影响 Gradle 构建。依赖相机、权限对话框或设备硬件的行为必须单独
列为模拟器/真机验证，不能用 Fake 结果代替。
