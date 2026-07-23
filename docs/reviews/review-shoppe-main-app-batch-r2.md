---
task: shoppe-main-app-batch-fix-review
status: passed
p0: 0
p1: 0
---

# Shoppe Main App Batch 修复复审

## 结论

**通过。** 原报告的 7 项发现已全部闭环，本轮未发现 P0 或 P1。Shop 首页所有商品
rail 均可进入 Product Detail；Top Products 也已收敛为真正的 canonical Product 摘要，
不再复用分类式 title、image 或无价格状态。

## P0/P1

无。

## 原 7 项逐项结论

1. **canonical Product ID/价格一致性：通过。** Shop 全部商品 rail（包括 Top
   Products）、Search、Cart、Wishlist 商品行、Wishlist recommendations、Promotions 和
   详情已收敛到 canonical payload；Cart 重复 upsert 保留既有商品快照与单价。
2. **Wishlist Add to Cart：通过。** 根装配把完整 `WishlistItem` 的 ProductSummary、
   color、size 转为 `CartLineInput`；根级测试验证点击后共享 Cart 的稳定行数量增加。
3. **订单评价 Done 回跳：通过。** 完成后显式回到 Order Detail，并由新 Controller 从
   共享 Orders API 重新加载；测试覆盖 `Review order` 消失和 `Your review` 出现。
4. **logout/delete account 会话重置：通过。** `DemoApp` 将
   logout 绑定到 Registry reset，Registry 重置 Cart、Checkout、Orders、Rewards、
   Settings、Payment、Support 和 Wishlist；聚焦测试验证各可变 Fixture 恢复默认值，
   Auth 测试也覆盖外部注入 reset 与 Demo session reset 的组合调用。
5. **Cart 语义与 44 x 44 触控区：通过。** IconButton 本身为 44 x 44，内部保留 30px
   视觉圆形，并提供商品相关 tooltip；测试检查真实 IconButton 尺寸。
6. **Cart 图片资源：通过。** 两张图片已缩放为 768 x 768 和 768 x 512，合计约 662 KB；
   通用图片组件按布局宽度和 DPR 设置 `cacheWidth`。
7. **iOS Photo Library 文案：通过静态检查。** 文案同时覆盖头像与本地商品图片搜索，
   `plutil -lint` 通过。

## 验证

- `make check`：通过；包含 format、analyze、Codex adapter、Harness、Spec、边界 lint、
  Harness/Hook/Evidence/Prerequisite Fixture 和全量测试。最后一次 Top Products 收敛后又
  单独执行 Dart format 只读检查，以及 Catalog、Wishlist、Shop Feed、Cart 聚焦测试，
  全部通过。
- 聚焦 app_features 测试：Shop Feed、Orders Done、Cart 可访问性、Registry reset 通过。
- 聚焦 Demo Router/Auth 测试：Product/Wishlist -> Cart、主 Router、Settings、Auth 通过。
- 聚焦 app_data 测试：Catalog、Cart、Wishlist、Search、Promotions、Profile 通过。
- `git diff --check HEAD`：通过。
- Cart PNG 尺寸/字节与 iOS plist：只读检查通过。

## 剩余风险

- 本轮未执行 App Operator；没有 Android/iOS 真机上的 Feed 点击、系统返回、触控命中与
  VoiceOver/TalkBack 证据。
- 本轮未重新执行 Android 或 iOS 原生构建。此前 iOS no-codesign Debug Build 因本机缺少
  iOS 26.5 Platform 无法运行，因此 iOS 宿主编译及图库首次授权、拒绝、受限、取消和成功
  选择仍未验证。
- 会话重置测试直接调用 `FeaturesRegistry.resetUserSession()`，尚未覆盖同一个 `DemoApp`
  进程内 mutate -> logout/delete -> login -> defaults 的完整根装配链路；当前生产默认装配
  和 reset callback 组合均可由静态代码及单元测试确认，但该完整集成路径仍建议补测。
