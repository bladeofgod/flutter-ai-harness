---
task: shoppe-promotions-live-stories
status: passed
p0: 0
p1: 0
---

# Shoppe Promotions / Live / Stories 执行 Review

## 当前结论

最终独立复审通过，未发现未解决的 P0/P1 问题。Promotions 公共边界、Fixture Handler、Local API、Registry、根 Router 和 Shop 入口已经形成完整生产链路；Flash Sale、Live 与 Story 均可从 Shop 进入，顶层路由受登录态保护，商品目标通过公共 Product Route 打开。

## 共享装配复审

- `app_data` 与 `app_features` barrel 已导出 Promotions Domain、API 和 Route 工厂。
- `FeaturesRegistry.local()` 只装配一个 `PromotionsFixtureHandler`，通过共享 `FixtureApiTransport`、`ApiClient`、`PromotionsLocalDataSource` 和 `LocalPromotionsApi` 向 Feature 注入窄接口。
- 根 Router 注册 `/promotions/flash-sale`、`/live`、`/stories/:storyId`，统一登录态保护，并把商品目标映射到公共 Product Route。
- Shop 的 Search、Flash Sale、Live、Story 显式回调均已接线；Demo 路由测试验证四个真实入口可以依次打开并通过 Back 返回 Shop。

## 未阻断风险

- P2：Demo 入口测试验证了从 Shop 进入各 Promotions 页面并返回，但没有单独断言 Promotions 页面前后 Shop 的精确滚动 offset；当前由同一 Stateful Shell 分支下的 `push/pop` 保留原页面实例，属于低风险测试补强项。
- P2：独立 Feature Route 测试验证了商品回调目标，Catalog 根路由测试验证了共享 Product Route；尚未增加“从 Promotions 商品卡点击后打开根 Product Route”的单条端到端 Widget 测试。

## 已验证范围

- Data：固定排序、`00:36:58` 固定倒计时、Story 类型映射、稳定请求键、not-found、畸形 Payload、不可变集合与本地 Asset Key。
- Controller：加载/失败/重试、释放后忽略结果、Live 本地预览状态、Story 手动前进/后退、边界与结束一次。
- Widget/Route：Flash/Live/Story 页面合并、商品目标回调、Story Variant、退出回调、空错误、多视口、横屏、文字缩放和图片解码。
- 证据：[`shoppe-promotions-live-stories.log`](test-evidence/shoppe-promotions-live-stories.log)，退出码为 0；`make analyze`、Data 测试、Feature 测试、Demo 真实入口测试和 `make lint` 均通过。
- 额外门禁：`make harness-check` 与 `git diff --check` 均通过。
- 证据命令按 Package 分别设置 `TOOL_WORKDIR`，确保 `app_features` 的 Package Asset Manifest 被真实加载；此前从 `app/` 根混跑的缺资源结果属于测试执行上下文错误，已由本次成功证据替代。

## 视觉限制

执行时对节点 `0:10857`、`0:10722`、`0:10483`、`0:10403`、`0:10327`、`0:10243`、`0:10163`、`0:10069`、`0:9985` 的 `get_design_context` 均返回 Figma Desktop 未打开对应设计文件。当前仅采用已入库设计上下文和现有同源本地资源，没有猜测节点专属交互或引入远程资源；最终视觉精确度需要在本地 MCP 可读时复核。

## 安全与范围

- Live 只显示 `DEMO LIVE` 和 `Demo preview ready`，没有流媒体、在线人数、消息或连接成功声明。
- Story 没有 Timer 或自动播放，只由用户手动切换。
- 未增加相机、麦克风、后台播放或网络权限。
- 未运行 App Operator，也未生成 UI Spec/Audit。
