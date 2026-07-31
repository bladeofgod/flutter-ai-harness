---
name: swift-ios-standards
description: "适用：编写或审查 iOS Swift Native Module、Bridge Adapter、Host 接线、Info.plist/Entitlements、SwiftPM 和原生 UI。不适用：Kotlin/Android、Dart Client 或 Wire Contract 设计。触发词：Swift、iOS、Xcode、SwiftPM、Info.plist、Entitlements、actor、Sendable、AVFoundation。"
paths: ["app/native/ios/**", "app/apps/*/ios/**", "app/packages/*/ios/**"]
---

# Swift / iOS 编码规范

## API 与边界

- 遵守 Swift API Design Guidelines，使用清楚的调用点名称和最小 `public` 可见性。
- 公共 API 使用稳定值类型、`async`/`throws`、`AsyncSequence` 和有类型错误；不暴露 Flutter、
  Wire Dictionary、Host 类型或不必要的 Apple Framework 对象。
- 通过 initializer 注入协作者、Clock、Executor/Scheduler 和 Framework Wrapper；不在实现内部
  隐式查找全局依赖。
- Native Module 不 import Flutter；Channel DTO、`FlutterError` 和线程回调只留在 Bridge Adapter。
- 禁止强制解包、`try!` 和无依据类型转换；系统边界的 Optional 必须显式处理。

## 并发与生命周期

- 跨并发域的值满足 `Sendable`，可变共享状态由 actor 或明确隔离域拥有。
- 只有 UI、Flutter callback 或 Apple API 明确要求时使用 `@MainActor`；重工作不得占用主线程。
- 使用结构化 Task，并保存需要跨作用域取消的句柄；不创建无法追踪的 detached work。
- 取消使用 `CancellationError` 语义并继续传播，不映射成普通能力失败。
- Delegate 默认弱引用以避免环，确需强所有权时记录生命周期并在 stop/deinit 时解除。
- Session、Observer、Notification、Continuation 和文件资源必须由明确对象释放；stop/cancel 可重复。

## iOS 工程

- Info.plist、Entitlements 和隐私声明保持最小，并由真实 Host 产品流程接入。
- Native Module 的依赖声明在 Swift Package；Bridge Adapter 只声明到 Package Product 的依赖。
- Objective-C/Flutter 边界显式映射错误与值，不让弱类型字典进入 Module。
- 公共错误保持稳定并保留内部诊断 cause，不暴露用户数据、绝对路径或私有 Framework 对象。

## 验证

运行 Swift 单元测试和受影响 Xcode/SwiftPM 构建。依赖相机、系统授权 UI 或真机硬件的行为必须
单独列为模拟器/真机验证，不能用 Framework Fake 结果代替。
