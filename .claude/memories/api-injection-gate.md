# API 注入门禁

权威语义见 `CLAUDE.md`：Controller 通过构造函数接收必需 API，服务定位器只用于装配点或全局服务。

仓库 lint 应在 Feature 的 `pages/` 和 `widgets/` 中识别直接持有或调用，并在 `controllers/` 中拒绝任何 `Get.find<XxxApi>()`：

```dart
Get.find<SomeApi>().call();       // UI 直接调用
final api = Get.find<SomeApi>();  // UI 持有 API
final api = Get.find<SomeApi>();  // Controller 服务定位，始终禁止
```

允许的装配点把解析后的 API 直接传入 Controller 或模块工厂：

```dart
ExampleController(api: Get.find<ExampleApi>());
```

lint 必须区分直接调用/持有和内联构造注入，不使用项目特定文件白名单。确有合理例外时，在装配点旁使用窄范围、有理由的 Suppression，不增加全局基线。

这条规则保证 Controller 测试只需构造 Fake、依赖归属清晰、UI 不感知数据层类型，并缩小 API 变更影响面。
