---
executor: task-executor
blockedBy: [shoppe-shop-home-catalog]
---

# 实现 Shoppe Cart 主页面与空态

## 背景与输入

- Figma：`0:7209` - `45 Cart`、`0:7085` - `46 Cart Empty Shown From Wishlist`、`0:6969` - `47 Cart Empty Shown From Popular`。
- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- `shoppe-shop-home-catalog` 提供的 ProductSummary、Catalog Fixture 和共享商品组件。

## 目标与非目标

- 实现 `/cart` Tab、Cart Item 数量/规格展示、总价和两种推荐来源的空态。
- Cart 使用进程内状态，重启恢复固定 Demo Cart；金额计算必须确定且使用明确 Money Value Object 或整数最小货币单位。
- 本卡不实现 Checkout、真实库存、支付或主导航 Shell，但必须一次建立 Product 与 Checkout 已知需要的完整 Cart 公共契约。

## 实现要求

1. 重新读取三个节点，确认商品行、数量控件、规格、地址摘要、总价、Checkout、推荐区段和空态差异。
2. 在 `app_data` 增加 Cart、CartItem、ProductVariation 和行项目输入；Product 基础信息与 Money 必须复用 Catalog 第一卡已经稳定的公共类型，不得二次定义或迁移金额。
3. 增加 Cart Feature Handler、LocalDataSource、Mapper、稳定请求键和 `CartApi` 本地实现。公共契约一次覆盖不可变快照读取、`add/upsert`、数量修改、删除、按 Checkout Attempt ID 幂等原子清空，以及只读状态通知；每次成功 mutation 只发布一个一致快照。
4. Cart 的 add/upsert 必须以 Product ID + 已确认 Variation 形成稳定行标识；同一行重复添加增加数量，不同 Variation 分行。原子清空只允许成功支付调用，同一 Attempt 重复调用保持幂等，失败支付不改变 Cart。
5. Cart Controller 通过构造函数接收 `CartApi`，统一管理加载、data、empty、error、mutating 和重复操作；数量不得小于设计允许下限。Product、Checkout 和底栏角标后续只消费该稳定 API，不再扩展 Cart 契约。
6. `45/46/47` 是同一 `/cart` 页面根据 Cart 内容和进入来源展示的状态。推荐来源使用显式枚举/Route extra 或 API 状态，不能靠文案判断。
7. Checkout 按钮只通过公开回调/Route 常量边界暴露；`shoppe-checkout-payment-flow` 完成前不创建伪支付结果。商品与 Wishlist 交互不得 import 对方私有实现。
8. 地址摘要在本卡只显示 Fixture；编辑地址属于 Checkout 任务。复用 Catalog 卡片和本地资源，保持 Bottom 操作区与列表滚动边界稳定。

## 同批测试与验收

- Domain/Data/API：Money 消费、add/upsert 行身份、数量、删除、总价、原子幂等清空、单次通知、空态、重建恢复、Mapper 与失败边界。
- Controller/Widget/Route：45 有数据状态、46/47 空态来源、数量操作、删除至空、Checkout 回调、长文本和多视口。
- `/cart` 可独立使用，金额无浮点误差，无远程库存/支付假象，不提前实现 48–56。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不接支付 SDK、数据库或系统钱包。
- UI 自动化由人工独立安排。
