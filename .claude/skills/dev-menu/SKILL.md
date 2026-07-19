---
name: dev-menu
description: "适用：新增或修改仅 Debug 可见的开发菜单入口，用于导航、Mock、缓存、网络、账号或 Feature Flag。不适用：生产设置，或散落在业务 UI 中的隐藏调试控件。触发词：DevMenu、调试菜单、开发者工具、Mock 状态、调试快捷入口、Feature Flag。"
paths: ["app/packages/app_features/lib/feature_dev_menu/**", "app/apps/**/lib/**/dev/**"]
---

# DevMenu

所有 Debug 行为集中到一个可发现、Release 不可达的 Feature。

模板只提供约束，不预置虚构菜单项。Demo 首次出现真实的 Mock、缓存、网络、账号或 Feature Flag 操作时，再创建 `feature_dev_menu`，并把入口和 Action 一起纳入任务卡与测试。

## 规则

- Route 注册、菜单入口和唤起方式尽量使用编译期 Build Mode Gate。
- 普通 Feature Widget 中不得散落 Debug Trigger。
- 入口按用途分组，破坏性操作必须二次确认。
- 壳工程 Service 通过 Registry Callback 注入，不得从 Feature import 壳实现。
- Mock Fixture 不包含生产数据和凭据。
- Cache、Network、Account 修改必须可回滚或范围清晰。
- Release 构建即使收到 DeepLink 也无法进入菜单。

测试 Debug 注册、Release 不可达和 Action Facade；设备限定验证需明确记录。
