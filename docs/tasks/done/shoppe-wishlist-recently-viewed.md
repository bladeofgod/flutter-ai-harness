---
executor: task-executor
blockedBy: [shoppe-shop-home-catalog]
---

# 实现 Shoppe Wishlist 与 Recently Viewed

## 背景与输入

- Figma：`0:7998` - `40 Wishlist`、`0:7844` - `41 Wishlist — Empty`、`0:7709` - `42 Recently Viewed`、`0:7498` - `43 Recently Viewed Date`、`0:7363` - `44 Recently Viewed Date Chosen`。
- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- `shoppe-shop-home-catalog` 提供的 Catalog Domain 与共享商品展示能力。

## 目标与非目标

- 实现 `/wishlist` Tab、有数据/空状态以及 `/wishlist/recently-viewed` 日期筛选流程。
- Wishlist 和 Recently Viewed 使用进程内可变 Demo 状态，App 重启后恢复固定 Fixture。
- 本卡不实现 Product Detail、Cart 业务或主导航 Shell；跨流程动作只通过公开 API/回调表达。

## 实现要求

1. 重新读取五个节点，确认 Wishlist 列表结构、空态推荐来源、Recently Viewed 日期控件、选中态和 Back 行为。
2. 在 `app_data` 增加 Wishlist/Recently Viewed 当前真实消费的 Domain 状态、LocalDataSource、Mapper 与稳定请求键；复用 ProductSummary，不创建 WishlistProduct 副本。
3. 在 `app_features/lib/api/` 定义窄 `WishlistApi`，本地实现负责读取和修改进程内状态；Controller 通过构造函数接收 API，管理加载、空、错误、移除、日期筛选和重复操作。
4. `40/41` 由同一 Wishlist 页面根据数据状态切换；`42/43/44` 由同一 Recently Viewed 页面和日期选择状态表达，不创建五个 Route。
5. 删除 Wishlist 项后列表和空态立即一致更新；Recently Viewed 筛选只影响当前显示，不使用系统当前日期作为随机输入，Fixture 日期固定且测试可控。
6. 创建 `/wishlist` 与 `/wishlist/recently-viewed` Route。商品、Add to Cart 等跨 Feature 动作只使用稳定 ID 和抽象边界，目标任务未完成前不得反向 import Cart/Product 内部实现。
7. 复用 Catalog 商品卡与资源；空态、日期 Sheet/Picker 和列表尺寸在窄屏、横屏、文字放大时可达。

## 同批测试与验收

- Data/API/Controller：初始数据、移除至空、状态隔离、重建恢复、日期筛选、失败/重试与重复操作。
- Widget/Route：40/41 状态切换、42/43/44 日期流程、Back/Cancel、Semantics、多视口和滚动。
- 页面不持久化、不读在线数据，不复制 Catalog Entity；所有可见操作有明确状态结果或显式延后边界。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不引入数据库、通知或系统日历。
- UI 自动化由人工独立安排。
