---
task: deduplicate-catalog-wishlist-assets
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：合并 Catalog 与 Wishlist 重复 Asset

## 实现结果

- 保留三份 Catalog canonical PNG，删除 byte-for-byte 相同的
  `recent_hat.png`、`recent_pink_dress.png`、`recent_red_dress.png`，空 Wishlist Asset 目录同步移除。
- 从 `app_features/pubspec.yaml` 删除空的 `assets/images/wishlist/` 声明；AssetManifest 中旧目录 key 为零。
- Wishlist Asset 测试通过 package canonical 路径加载、解码 `shop_product_02/03/04.png`，继续断言
  400x266、266x400、266x400，并加入旧目录不得回归的负向断言。
- Wishlist Fixture 测试新增 Recently Viewed 的 12 条 ID、产品 ID、日期顺序和既有 Domain 图片映射断言。

## Fixture 前提修正

执行时发现 `_recentItem` 的 `imageAssetKey` 参数从未写入 payload；Domain 产品一直由
`canonicalCatalogProductPayload` 提供 profile 图片。若在本任务让该参数首次生效，会同时改变 12 条
Recently Viewed 的真实图片，违反“业务行为不变”。因此本实现删除这个无效参数及 12 个死配置，而没有
夹带视觉行为修复；目标四项的 ID、日期、顺序和运行时图片映射均由新增测试锁定。Catalog canonical PNG
由独立 Asset 测试证明仍被 bundle 和解码。

## 变化范围

- 修改：`wishlist_fixture.dart`、`wishlist_local_data_source_test.dart`、`app_features/pubspec.yaml`、
  `wishlist_assets_test.dart`。
- 删除：三个 Wishlist 重复 PNG，合计 373,923 bytes 源码资源。
- 未修改其它 Flutter/Native build input；稳定输入摘要仍为
  `df46a579ffc763e258a994d6290832029c1715abb48db0c97adfeb37318669d6`（651 个文件），与 baseline 完全一致。
- 三份 canonical PNG SHA-256 仍分别为 `b2743d83…`、`13f31238…`、`6439bd87…`。

373,923 bytes 只是源码资源减少量，不是 Android AAB 收益；包体 delta 由后续同参平台任务实测。

## 验证

- Wishlist Data：9 tests passed。
- Feature Wishlist：14 tests passed。
- Feature Catalog：25 tests passed。
- `make format`：390 files，0 changed。
- `make analyze`：No issues found。
- `make test`：全部 Workspace Flutter 测试通过。
- 生产 Flutter/Android/iOS 旧资源引用为 0；测试仅保留 1 处 AssetManifest 负向路径断言。
- `git diff --check`：通过。

完整聚焦命令摘要见[测试证据](test-evidence/deduplicate-catalog-wishlist-assets.log)。复审未发现剩余
P0/P1/P2。
