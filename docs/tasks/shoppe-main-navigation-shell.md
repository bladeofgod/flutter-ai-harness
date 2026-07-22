---
executor: task-executor
blockedBy: [shoppe-shop-home-catalog, shoppe-categories-tab, shoppe-wishlist-recently-viewed, shoppe-cart-tab, shoppe-profile-dashboard]
---

# 集成 Shoppe 五栏主导航 App Shell

## 背景与输入

Shop、Wishlist、Categories、Cart 和现有 Profile 都使用同一五栏底部导航。当前 Profile 页内部的 `ProfileBottomNavigationBar` 是上一阶段无目标页面时的静态占位；五个根页面完成后，应由根 Shell 统一管理导航、选中态和分支生命周期。

- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- 五个依赖任务提供的公开 Route、页面和 API
- `apps/demo/lib/router/demo_router.dart` 与现有 Auth Redirect

## 目标与非目标

- 建立可操作的 Shop、Wishlist、Categories、Cart、Profile 五分支主导航并保持分支状态。
- 只迁移 Profile 的底栏归属，不重做 `01–14` 页面内容或改变认证成功进入 `/profile` 的既定行为。
- 本卡不实现 Product、Search、Checkout、Orders、Rewards、Settings 或 Chat 内容。

## 实现要求

1. 重新核对节点 15、25、40、45、13 的底栏结构、图标、选中标记、安全区和页面背景；优先使用仓库 Icon，产品专属图标才本地化 Asset。
2. 根 GoRouter 使用 `StatefulShellRoute.indexedStack` 或等价结构建立五个独立 Navigator 分支。Tab 切换保留各自滚动位置与子栈；重复点击当前 Tab 的回根行为必须明确并测试。
3. App Shell Widget 属于 `app_features` 的主应用共享业务 UI，不放入 `app_ui`，也不归属 Profile 私有目录。它接收当前分支与导航回调，不直接读取 Feature Controller/API。
4. 从 `ProfileDashboardPage` 删除静态 `ProfileBottomNavigationBar`，并更新 Profile 测试为 Shell 负责固定底栏；Profile 内容、当前用户订阅和 `/profile` Route 不重写。
5. 根 Redirect 把所有五个主应用 Route 视为受认证区域：未登录 direct link 返回 Welcome；已登录访问 Welcome/Auth 仍进入 `/profile`。Redirect 保持同步、无 API 调用、无循环。
6. Deep Link 到任一 Tab 选择正确分支；系统 Back 先处理分支子栈，再按平台预期处理根页面，不返回已完成 Auth 页面。
7. Route/API 装配只使用各 Feature 公开入口和 `FeaturesRegistry`；壳工程不得 import Feature 私有 Page、Controller 或 Local API 实现。
8. 底栏尺寸固定、Semantics 包含五个 label 与 selected 状态，320 宽、横屏和安全区下不溢出，不遮挡各页最后内容。
9. 本卡由主执行器串行完成第一轮共享热点集成：更新 Handler 列表、公开 barrel、`FeaturesRegistry`、根 Router 和 Profile 底栏迁移。第二波并行子任务不得同时编辑这些文件。

## 同批测试与验收

- Route：五 Tab 点击、Deep Link、分支栈/滚动保持、重复点击、Back、认证/登出 Redirect 和未知 Route。
- Widget：底栏视觉结构、选中态、Semantics、安全区、窄屏和各根页面内容不被遮挡。
- 回归：Welcome/Auth/Profile 测试继续通过，注册/登录仍进入 Profile；`01–14` 没有重复页面或新的 Auth Route。
- App 启动后可从 Profile 操作五个主 Tab，所有入口都指向真实页面，无 no-op Tab 或占位 Scaffold。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 本卡无原生宿主改动；Android/iOS 返回手势差异由 Widget/Route 测试覆盖，真机 UI 自动化由人工另行安排。
