---
name: go-router
description: "适用：新增 Route、Redirect、ShellRoute/StatefulShellRoute、DeepLink、路由参数、Observer 或 Route 级 Controller 装配。不适用：GetX 导航或没有明确兼容边界的任意 Navigator Stack。触发词：GoRouter、GoRoute、redirect、deep link、shell route、context.go、context.push。"
paths: ["app/apps/**/lib/main.dart", "app/apps/**/lib/*app.dart", "app/apps/**/lib/**/*router*.dart", "app/apps/**/lib/**/routes/**", "app/packages/app_features/lib/**/routes.dart", "app/packages/app_core/lib/router/**"]
---

# go_router 路由模式

## 归属

- Feature 声明自己的 Route 和 Route 级装配。
- `app_features` 汇总 Feature Route。
- 壳工程拥有根 `GoRouter`、NavigatorKey、全局 Redirect、Observer 和错误页。
- 根 Widget 使用 `MaterialApp.router`。

## 导航

- 替换位置和主导航使用 `context.go`。
- 需要返回结果的详情栈使用 `context.push`。
- 优先使用命名/强类型参数，避免无结构 Map。
- 外部 DeepLink 解析和认证决策不得放在页面 Widget。
- 只有没有有效 `BuildContext` 的 App 级事件才使用全局 Router。

## Redirect

- Redirect 必须纯且快速，不执行网络请求。
- 需要重新计算时使用认证状态 Refresh Notifier。
- 显式列出公开/认证 Route，避免循环。
- 测试登录、未登录、非法链接和状态恢复。

## Controller 生命周期

在 Route Builder 或专用装配 Widget 中创建页面 Controller，并随 Route 销毁。页面 Controller 不得 permanent 注册。

## 跨 Feature 导航

通过 Route 常量、强类型 Helper 或窄 Navigation API 暴露目标，不 import 其他 Feature 的 Page 或 Controller。
