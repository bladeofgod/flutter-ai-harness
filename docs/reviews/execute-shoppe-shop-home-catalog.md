---
task: shoppe-shop-home-catalog
status: passed
p0: 0
p1: 0
---

# Shoppe Shop 首页与 Catalog 执行审查

## 首轮 P1：Profile 分类卡被错误共享为 Shop 四图拼贴

- 位置：[`app/packages/app_features/lib/feature_profile/pages/profile_dashboard_page.dart`](../../app/packages/app_features/lib/feature_profile/pages/profile_dashboard_page.dart)、[`app/packages/app_features/lib/shared/catalog/catalog_components.dart`](../../app/packages/app_features/lib/shared/catalog/catalog_components.dart)
- 问题：首轮实现把 Profile 原有单图渐变分类卡替换成 Shop 的四图拼贴卡。Profile Fixture 只提供一张分类图，因此会出现图片区域空白并造成视觉回归。
- 修复：恢复 Feature 私有 `ProfileCategoryCard`，只复用 `CatalogAssetImage`；新增 Profile 单图渐变卡 Widget 回归测试。Shop 继续使用四图拼贴，不再把页面视觉差异强制合并。

## 已确认边界

- `FixtureApiTransport` 只索引和分发组合注入的 Handler，重复请求键在构造期拒绝，未知请求由 `ApiClient` 归一化；Auth、Profile、Catalog 分别拥有请求键与 Payload，没有全局静态注册。
- `Money` 使用最小货币单位保存金额，`ProductSummary.displayPrice` 只由类型化金额派生；`ProductSummary`、`CategorySummary`、`FlashSale` 已迁入 Catalog Domain，Profile 没有保留副本。
- Catalog 数据经过 Mapper、LocalDataSource、窄 `CatalogApi`、Controller 和 Registry 注入到 `/shop`；Page/Controller 不接触 Fixture Payload，也没有服务定位或跨 Feature 私有 import。
- Shop 使用单一纵向 `CustomScrollView`，横轨有界、双列网格响应式；页面未复制主 App Shell，未创建尚不存在的目标 Route 或虚假交互结果。
- Big Sale、Categories 和商品缺失资源均已本地化并压缩；AssetBundle 加载和解码测试通过。运行时代码扫描未发现 MCP localhost 或在线图片地址。
- Profile 共享组件默认参数保持原有圆角、图片尺寸、标签和无心形图标行为；Shop 的白框、内缩、计时块和尺寸通过显式参数配置。

## 验证

- 完整证据：[`test-evidence/shoppe-shop-home-catalog.log`](test-evidence/shoppe-shop-home-catalog.log)，`make check` 退出码为 0。
- 独立复跑：`app_data` Catalog/Profile 测试、`app_features` Catalog/Profile 测试和 Demo Router 测试均通过。
- 独立复跑：`make format`、`make analyze`、`make lint`、`make lint-test`、`make harness-check` 与 `git diff --check` 均通过。
- 资源验证覆盖 Big Sale、15 张新增分类图、6 张新增 Shop 商品图及复用的 Profile 商品资源。

## 最终复审

- P0：0
- P1：0
- P2：0
- 状态：通过，可以归档。

首轮 Profile 分类卡 P1 已关闭。复审确认 Profile 默认展示参数与旧实现一致，Shop 专属视觉参数不会反向污染 Profile；Controller 页面卸载释放、多个视口无溢出、认证 Route 守卫、重复 Handler 请求键和本地资源解码均有测试覆盖。

## 剩余风险

- 本轮未自动执行 App Operator 或真机截图对比；按仓库约定，这类自动化由人工独立安排。375 x 812 结构、长页顺序和多视口布局由 Widget 测试覆盖。
- Figma Banner 的装饰 Bubble 未单独导出；主照片、文案、尺寸与内容层级已实现，不影响当前 Demo 流程，后续人工视觉核对可决定是否补充。
