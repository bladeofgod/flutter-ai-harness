---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy:
  - measure-android-catalog-wishlist-asset-baseline
---

# 合并 Catalog 与 Wishlist 重复 Asset

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 7 项已确认方向。
- `measure-android-catalog-wishlist-asset-baseline` 已记录目标文件和 Android arm64 Release AAB 基线。
- SHA-256 扫描确认三组 byte-for-byte 相同 PNG：
  - `catalog/products/shop_product_02.png` = `wishlist/recent_hat.png`，各 94,364 bytes。
  - `catalog/products/shop_product_03.png` = `wishlist/recent_pink_dress.png`，各 151,297 bytes。
  - `catalog/products/shop_product_04.png` = `wishlist/recent_red_dress.png`，各 128,262 bytes。
- `app_data` Wishlist Fixture、`app_features` Asset 声明与 Catalog/Wishlist Asset 测试是当前引用入口；
  原生 Host 没有上述六个文件的直接引用。

## 目标

- 以 Catalog 的三个 product PNG 为 canonical copy，更新 Wishlist Fixture/测试后删除三个重复文件和空的
  Wishlist asset declaration。
- 保持 Wishlist/Catalog 展示像素、尺寸、产品映射和业务行为不变。
- 为下游 Android 同参复测保留精确、单一的 Asset/Fixture 变化范围。

## 非目标

- 不重新编码、裁剪或视觉修改 PNG，不重命名其余 Asset，不做全仓未使用资源清理。
- 不删除 Android launcher、iOS AppIcon/LaunchImage 或 Native Module 资源。
- 本卡不执行 Android/iOS Size Analysis，不宣称包体收益；最终 Android 结果由依赖本卡的平台门禁生成。

## 实现顺序与要求

1. 修改前核对 baseline 报告的六个文件 SHA-256、像素、原始字节、稳定 build input digest 和所有
   Flutter/Test/Native 引用。发现 hash 不同、未审计引用、baseline 外 build input 变化或并行修改时停止。
2. 把 `recent_hat`、`recent_pink_dress`、`recent_red_dress` 的 Fixture 引用分别替换为 canonical
   `shop_product_02/03/04`。更新 Wishlist Asset 测试读取 canonical package 路径并继续断言 400x266、
   266x400、266x400；Catalog 测试继续覆盖同一文件。
3. 删除三个 Wishlist PNG。目录为空后删除 `pubspec.yaml` 的 `assets/images/wishlist/` 声明；不得删除非空
   目录或只根据文件名推断引用已消失。
4. 运行聚焦 Data/Asset/Widget 测试，重新扫描 Flutter、测试、Android、iOS 引用，确认旧路径为零且三份
   canonical PNG 仍被 bundle 和解码。
5. Review 列出精确实现文件和 373,923 bytes 源码减少量，但明确它不是包体结果；除上述 Fixture、测试、
   pubspec 声明和三个重复 PNG 外不得夹带其它 build input 变化。

## 同时编写的测试

- Wishlist Fixture 测试断言三项使用对应 canonical Catalog key，产品 ID/日期/顺序不变。
- Asset 测试加载 package 实际路径、解码并断言既有尺寸；旧 Wishlist 路径不再出现在 AssetManifest。
- Catalog/Wishlist 相关 Widget 测试保持图片可解析且无异常。

## 验收与验证

```bash
TOOL_WORKDIR=app/packages/app_data bash scripts/flutter-tool.sh test test/wishlist
TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_catalog
TOOL_WORKDIR=app/packages/app_features bash scripts/flutter-tool.sh test test/feature_wishlist
make format
make analyze
make test
make harness-check
git diff --check
```

## 环境限制

纯 Flutter Asset/Fixture 任务不需要 Android SDK 或 Xcode。baseline 失效时不得继续删除 Asset；下游 Android
门禁必须在同一环境得到 post 产物。iOS IPA 不在本优化的实际测量范围，不能外推 Android 结果。
