---
task: shoppe-main-navigation-shell
status: passed
p0: 0
p1: 0
---

# Shoppe 主导航 Shell 独立 Review

## Findings

最终复审未发现未解决的 P0/P1 问题。

## 已关闭问题

### 已关闭：重复点击当前 Tab 执行两次回根导航

- [`demo_router.dart`](../../app/apps/demo/lib/router/demo_router.dart#L57) 现在只执行一次 `navigationShell.goBranch(index, initialLocation: true)`，已移除延迟 post-frame 导航副作用。
- [`demo_router_test.dart`](../../app/apps/demo/test/router/demo_router_test.dart#L112) 继续验证当前 Wishlist Tab 重复点击后回到分支根页。

### 已关闭：分支滚动位置没有回归证据

- [`demo_router_test.dart`](../../app/apps/demo/test/router/demo_router_test.dart#L194) 现在把 Shop 滚动到非零偏移，切换到 Wishlist 子页并返回 Shop 后比较 `ScrollPosition.pixels`，验证 `StatefulShellRoute.indexedStack` 保留分支滚动状态。

### 已关闭：Deep Link、根级 Back、子页登出和内容遮挡证据不完整

- [`demo_router_test.dart`](../../app/apps/demo/test/router/demo_router_test.dart#L285) 直接启动五个根路径和 Recently Viewed，验证目标内容、Route 路径及目的地 `selected` Semantics；同批测试也覆盖六个路径的未登录守卫。
- [`demo_router_test.dart`](../../app/apps/demo/test/router/demo_router_test.dart#L233) 先从 Recently Viewed Back 到 Wishlist，再在分支根执行 Back，验证不会返回 Welcome/Auth；[`demo_router_test.dart`](../../app/apps/demo/test/router/demo_router_test.dart#L345) 从 Recently Viewed 登出并验证回 Welcome。
- [`demo_router_test.dart`](../../app/apps/demo/test/router/demo_router_test.dart#L265) 把 Shop 滚动到最大偏移，并断言最后 recommendation marker 的 `bottom` 不超过 Shell bar 的 `top`。

## 已确认行为

- 根路由使用 `StatefulShellRoute.indexedStack` 建立 Shop、Wishlist、Categories、Cart、Profile 五个独立 Navigator 分支，分支顺序与底栏一致。
- `ShoppeMainNavigationShell` 位于 `app_features/lib/shared/`，只接收当前索引、导航回调和 child，不读取 Controller/API。
- Demo 壳只通过 `app_features.dart` 公共入口装配 Route/API；未发现 Feature 私有实现 import。
- Profile 私有静态底栏已移除，Profile 内容与当前用户订阅继续由原 Controller/Page 管理。
- Redirect 同步读取 `AuthStateCoordinator`，五个主路径及其子路径都被识别为认证区域；静态检查未发现循环或 API 调用。
- 底栏提供五个 label、button 与 selected Semantics，并使用 50px 固定内容高度和底部 `SafeArea`。

## 验证

- 已读取最终重新录制的 [`shoppe-main-navigation-shell.log`](./test-evidence/shoppe-main-navigation-shell.log)：记录的 Analyze、Shell/Profile 测试、Demo Router 19 项测试和仓库边界检查均为 exit 0。
- Reviewer 最终复跑 `TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh test test/router/demo_router_test.dart`：19 项通过，包含六个已登录 Deep Link 的 selected Semantics 断言。
- 首轮 Reviewer 复跑 `TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/shared/main_navigation_shell_test.dart`：3 项通过；第二轮证据继续通过 Shell/Profile 回归。
- Reviewer 复跑 `git diff --check`：通过。
- 未执行 Android/iOS 真机 UI 自动化；按仓库契约，这不是普通任务默认门禁。

## 摘要

Shell 架构、公开边界、Profile 底栏迁移、同步认证 Redirect、单次回根导航、分支栈/滚动保持、Deep Link、Back、子页登出和安全区内容可达性均已形成绿色回归证据。最终 Review 结论为 `passed`，P0/P1 均为 0。
