---
name: testing-strategy
description: "适用：编写或审查 Dart 单测、Flutter Widget 测试、Route 测试、集成测试、Fake 或 Mocktail Mock。不适用：Kotlin/Swift 测试框架，也不替代生产实现。触发词：testWidgets、flutter test、Mocktail、Fake、Get.reset、integration_test、coverage、flaky。"
paths: ["app/**/test/**/*.dart", "app/**/integration_test/**/*.dart", "app/**/*_test.dart"]
---

# Flutter 测试策略

## 选择最小证明层

- Mapper/Value 行为：单元测试。
- Controller/Use Case 状态和副作用：构造注入 Fake/Mock 的单元测试。
- 渲染和交互：Widget 测试。
- Redirect 和导航：Router/Widget 测试。
- Plugin/原生集成和完整用户旅程：Integration 或原生测试。

## 规则

- 测试公共行为和边界契约，不测试私有调用顺序。
- 有状态协作者优先用 Fake，窄交互断言使用 Mock。
- 不在期望值 Helper 中复制生产算法。
- teardown 清理 GetX/全局注册、Platform Channel、Storage、Clock 和 Binding。
- Route 测试使用 `MaterialApp.router`，不得引入 `GetMaterialApp`。
- 按需覆盖加载、成功、空、错误、重试、取消和重复操作。
- AssetBundle、Font、Plugin 和图片解码都视为显式测试依赖。

## 稳定性

- 优先使用有依据的 `pump` 或状态等待，避免无边界 `pumpAndSettle`。
- 只有 Semantics 或自动化需要时才增加稳定 Key。
- 确认测试确实执行到目标断言，没有因 Setup 静默失败而假通过。
- 先运行新增测试文件，再运行受影响包测试。

重新确认产品契约前，不得削弱失败断言。
