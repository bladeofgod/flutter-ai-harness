---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-shop-home-catalog, shoppe-product-details-reviews]
---

# 实现 Shoppe Flash Sale、Live 与 Story 内容页

## 背景与输入

- Figma：`0:10857` - `16 Flash Sale + Live`、`0:10722` - `17 Flash Sale`、`0:10483` - `18 Flash Sale Full`、`0:10403` - `19 Live`、`0:10327` - `20 Story + Dots`、`0:10243` - `21 Story Dots Tap`、`0:10163` - `22 Story + Product Style 01`、`0:10069` - `23 Story + Banner`、`0:9985` - `24 Story + Product Style 02`。
- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- Shop 首页、Catalog/Product Route 与已登记本地资源规则。

## 目标与非目标

- 实现 Shop 首页可到达的 Flash Sale、Live 展示和 Story 浏览流程。
- 所有内容使用本地确定性 Fixture；Live 是视觉 Demo，Story 由用户手动前进/后退。
- 本卡不接直播流、视频播放器、自动播放 Timer、推送、聊天或内容 CMS。

## 实现要求

1. 重新读取九个节点，确认 16–18 的页面/长页关系、19 Live 内容、20/21 Story 进度交互和 22–24 内容 Variant。
2. 复用 Catalog Product/Money；只增加 Promotion、LivePreview、StorySequence/StoryItem 当前消费字段，不复制 ProductSummary。
3. 增加窄 Promotions API、LocalDataSource、Mapper 与固定 Fixture；倒计时显示使用固定值，不读取墙钟时间或运行无限 Timer。
4. 建立 `/promotions/flash-sale`、`/live`、`/stories/:storyId` 等最小 Route。16/17/18 根据结构合并同一 Flash Sale 页面及其内容状态，不按画板建三个 Route。
5. Story Controller 管理当前 Item、进度、前进、后退和结束返回；不自动播放。22–24 由 Story Item 类型驱动复用页面，商品点击进入 Product Route。
6. Live 页面展示本地封面、商品和静态状态；任何播放/观看按钮只能产生已定义 Demo 状态，不显示连接成功、在线人数变化或真实消息。
7. 从 Shop 首页正确接入 See All、Flash Sale、Live、Story 入口；Back 返回原 Tab 并保持 Shop 滚动位置。
8. Asset 本地化、压缩和解码测试完整；Story 全屏内容适配 SafeArea、横屏和文字缩放，不用整页截图。

## 同批测试与验收

- API/Controller：固定排序、倒计时值、Story 边界、Variant、错误/重试与释放。
- Widget/Route：16–24 页面/状态合并、入口、Product 跳转、Story 手动导航、Back、全屏 Insets 和多视口。
- 无流媒体、自动 Timer、网络内容或虚构实时数据；Shop/Profile 现有 Story 与 Sale 展示回归通过。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不增加麦克风、相机、后台播放或网络权限。
- UI 自动化由人工独立安排。
