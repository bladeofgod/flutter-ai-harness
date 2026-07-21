---
executor: task-executor
blockedBy: [shoppe-auth-local-foundation]
---

# 实现 Auth 成功后的 Shoppe Profile Dashboard

## 背景

用户指定 Figma `0:11956` 与 `0:11472` 作为注册和登录成功后的页面。两者是同一个 Profile Dashboard 的首屏与完整滚动内容。本任务实现真实 `/profile` Route、只读本地 Dashboard 数据和响应式长页面，不扩展设计稿未提供的商品详情或底部 Tab 目标流程。

## 输入

- [`docs/figma/shoppe-profile-dashboard-design-context.md`](../figma/shoppe-profile-dashboard-design-context.md)
- [`docs/figma/shoppe-auth-flow-design-context.md`](../figma/shoppe-auth-flow-design-context.md)
- [`docs/architecture.md`](../architecture.md)
- [`docs/api-contracts.md`](../api-contracts.md)
- `app_ui` 现有 Theme/字体/颜色
- `shoppe-auth-local-foundation` 提供的 ApiClient、Registry、UserEntity、AuthService、UserService 与 AuthStateCoordinator

## 实现要求

1. 使用 Figma Desktop MCP 重新读取 `0:11956` 和 `0:11472`；`0:11956` 是 375 x 812 首屏视觉基准，`0:11472` 是 375 x 2909 内容来源，不得实现为两个页面或长截图。
2. 在 `app_data` 只定义当前 Dashboard 消费的 Domain 数据：公告、最近浏览、订单摘要、Story、商品摘要、分类、Flash Sale 展示和推荐分组。不得预建购物车、订单详情、收藏或结算模型。
3. 扩展 Fixture Transport、LocalDataSource 和 Mapper，使用稳定请求键提供确定性 Dashboard Payload。所有图片使用本地资源标识，不包含 MCP URL 或在线 URL。
4. 在 `app_features/lib/api/` 定义 `ProfileDashboardApi`，在 `feature_profile/api/` 提供本地实现，并通过 `features_registry.dart` 公开装配。Page/Controller 不接触 Fixture Payload。
5. Profile Controller 通过构造函数接收 `ProfileDashboardApi` 和 `CurrentUserProvider`，订阅只读当前用户变化并在销毁时释放监听；覆盖 loading、data、empty section 与 retryable error。不得接收/查找壳工程 `UserService`，也不得 `Get.find<ProfileDashboardApi>()`。
6. 创建 `feature_profile/pages/profile_dashboard_page.dart`、Feature 私有重复 Widget 与 `routes.dart`，公开 `/profile` Route 常量/工厂。页面 Greeting 和头像只读取 Controller 暴露的当前 User 状态：Fixture 登录显示 Romina；注册用户显示 Demo 默认派生名称和所选/默认头像。
7. 使用一个 `CustomScrollView`/Sliver 组织纵向内容，并为 Stories、New Items、Most Popular、Top Products 使用有界横向列表。图片容器尺寸稳定，不能因加载或失败跳动。
8. Bottom Navigation 固定在安全区底部，Profile 保持选中。没有设计输入的 Shop、Wishlist、Categories、Cart 等目标不创建 Route、不伪造反馈，也不阻塞 Profile 页面滚动。
9. Flash Sale 倒计时使用确定性静态 Fixture 值，不启动墙钟 Timer。Announcement、订单按钮、Story 和商品卡本阶段为只读展示，不产生虚构业务结果。
10. 从 Figma 本地化实际使用的头像、Story、商品和分类图片，按显示尺寸提供压缩 Raster Asset。不得把整个页面或完整区段截图作为资源；不确定授权的单项照片使用许可明确/生成的替代图并记录偏离。
11. 复用现有 AppColors 和 Auth 任务新增的浅色 Surface Token。只在至少两个真实组件共享时增加 Feature 私有组件，不把商品业务卡片提升到 `app_ui`。
12. 壳工程将 Profile Route 纳入根 GoRouter，并把 `AuthStateCoordinator` 作为唯一 `refreshListenable`；Profile 注入的 `CurrentUserProvider` 也由同一 Coordinator 提供。未登录访问 `/profile` 时返回 Welcome；已登录访问 Welcome 或任意 Auth Route 时进入 `/profile`；登出返回 Welcome。Redirect 只能读取 Coordinator 已提交的一致快照，必须纯同步、不执行数据请求且无循环。
13. 375 x 812 首屏对齐 `0:11956`；完整 section 顺序对齐 `0:11472`。系统状态栏和 Home Indicator 由平台处理。

## 同批测试

- Mapper/DataSource/API：Fixture 确定性、分组顺序、空 section、失败与重试。
- Controller：loading/data/error、当前用户切换和释放。
- Widget：首屏结构、完整 section 顺序、横纵滚动、固定 Bottom Navigation、图片占位、窄短屏、横屏和 1.3 倍文字无溢出。
- Route：未登录 direct `/profile`、已登录 direct Welcome/Auth、登录成功、登出和未知 Route；验证双向 Redirect 不循环，并在每次 Router/Provider 通知时断言 Session 与当前用户满足一致性不变量。
- Asset：所用图片可从 Package AssetBundle 加载并解码，密度/尺寸符合声明。

## 验收标准

- Auth 成功拥有真实且可测试的 `/profile` 目标，不存在临时成功页。
- 首屏与完整滚动内容都来自布局 Widget 和本地 Domain 数据，不依赖网络或 Figma Desktop。
- 页面没有跨 Feature 内部 import、Fixture Payload 泄漏、滚动嵌套冲突或 Bottom Navigation 遮挡。
- 没有为未提供的页面创建占位 Route；未支持的卡片行为不宣称可用。
- 聚焦测试、静态分析、边界 lint、Harness 和完整 Demo 测试通过。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
make harness-check
git diff --check
```

## 后续边界

- Bottom Navigation 其余 Tab、商品详情、订单、Story、消息和设置需要各自 Figma 输入后再激活。
- UI 自动化不随本卡自动生成或执行，由人工独立安排。
