---
name: native-testing-strategy
description: "适用：设计或审查 Kotlin/Swift 原生模块、Bridge Adapter、Host 编译、模拟器/设备和系统能力验证。不适用：纯 Dart/Flutter 测试或用 Fake 代替相机和权限真机验证。触发词：JUnit、XCTest、Robolectric、instrumented test、Swift Testing、Framework Fake、Gradle test、xcodebuild、模拟器、真机。"
paths: ["app/native/android/**/src/test/**", "app/native/android/**/src/androidTest/**", "app/apps/*/android/**/src/test/**", "app/apps/*/android/**/src/androidTest/**", "app/packages/*/android/**/src/test/**", "app/packages/*/android/**/src/androidTest/**", "app/native/ios/**/Tests/**", "app/apps/*/ios/**/*Tests/**", "app/packages/*/ios/**/*Tests/**"]
---

# 原生测试策略

## 选择证明层级

1. 纯单元测试：状态机、值类型、错误、取消、并发和资源所有权；不启动 Flutter 或系统 UI。
2. Framework Fake：把 Camera、文件、Clock、Dispatcher/Executor 等平台边界包在窄接口后，
   确定性验证模块编排；Fake 不是系统能力验证。
3. Bridge Adapter 测试：使用 Native Module Fake 验证 Wire/Native 映射、线程切换、listener 和 detach。
4. Host 编译：用 Gradle 或 Xcode/SwiftPM 构建真实依赖图，证明 Module、Adapter、注册和平台配置可解析。
5. 模拟器/设备测试：验证 Activity/Scene 生命周期、平台线程、配置变化及支持的系统交互。
6. 真机系统能力：相机、麦克风、系统权限、硬件中断和性能必须在明确设备上留证。

## 规则

- 测试公共行为，不绑定私有调用顺序；Clock、Dispatcher/Executor 和 Framework Wrapper 可替换。
- 覆盖成功、拒绝、受限、取消、重复 stop、并发竞争、后台/前台和资源释放。
- Android local test、instrumented test 与 iOS unit/UI test 的能力边界必须准确记录。
- Host 编译不能替代 Native Module 单测，Fake 通过不能宣称 Camera 或系统权限已验证。
- 环境缺少 SDK、Xcode、模拟器或真机时，列出未运行命令、受影响文件和剩余风险。
- 证据不得记录设备 ID、用户名、主机路径、真实媒体、账号或其他敏感信息。
