---
task: deduplicate-catalog-wishlist-assets
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/deduplicate-catalog-wishlist-assets.md
  - app/packages/app_data/lib/src/wishlist/wishlist_fixture.dart
  - app/packages/app_data/test/wishlist/wishlist_local_data_source_test.dart
  - app/packages/app_features/pubspec.yaml
  - app/packages/app_features/test/feature_wishlist/wishlist_assets_test.dart
  - app/packages/app_features/assets/images/catalog/products/shop_product_02.png
  - app/packages/app_features/assets/images/catalog/products/shop_product_03.png
  - app/packages/app_features/assets/images/catalog/products/shop_product_04.png
implementationDigest: 080279f77559c8cdfbb00157c62f9290408b186e864e8f6eeaa8a856e9f33b0b
---

# Security Review：合并 Catalog 与 Wishlist 重复 Asset

## 已检查边界

- 删除内容仅为三份已经逐字节证明与保留 Catalog PNG 相同的静态图片；目录删除前确认没有其它文件，
  canonical 文件 SHA-256 和像素尺寸均保持不变。
- 生产 Flutter、Android 和 iOS 源码中旧文件名及 Wishlist 目录引用为零；AssetManifest 负向测试防止声明
  或旧 key 回归。没有通过动态路径、文件名拼接或 Native Host 绕过扫描的消费者。
- Fixture 的死 `imageAssetKey` 参数从未进入 payload；本任务删除无效配置并用测试锁定既有 Domain ID、日期、
  顺序和实际图片映射，没有把一个视觉行为修复混入资源删除。
- 未修改相机/麦克风权限、媒体文件、用户数据、网络、凭据、签名、Manifest、Info.plist、Entitlements、Wire
  Contract、依赖来源、CI 权限、Agent/MCP 能力或发布流程。
- PNG 来自仓库既有资源，未重新编码、下载或引入新的资产来源及许可证风险。

## 结论

未发现路径遍历、资源替换、敏感数据泄漏、权限扩大或供应链变化。P0/P1/P2 为 0/0/0。373,923 bytes 仅是
删除的仓库资源字节；安全审查不把它当作 AAB 收益，平台产物结果由独立 post 测量任务给出。
