---
task: measure-android-catalog-wishlist-asset-baseline
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：测量 Catalog 与 Wishlist Asset 的 Android 包体基线

## 结论

- 在六个目标 PNG、Wishlist Fixture、Asset 声明和测试均未修改时完成 Android arm64 Release AAB
  基线；构建命令退出码为 0。
- AAB 为 28,530,515 bytes，SHA-256 为
  `36c5ce820626abec5cabe54e3e2419ab12f4b98a183b9aafb4eb87142ce64350`。
- Size Analysis JSON 为 9,358,872 bytes，SHA-256 为
  `bf76c61ab13520d4943f954ab74b8dbd3a823290f5ddaacb6173ef89a85ef631`。根条目压缩值之和为
  28,429,397 bytes，`base/assets` 为 8,898,633 bytes，`flutter_assets` 为 8,266,966 bytes。
- 完整 AAB、Size Analysis JSON、AOT trace/snapshot 和完整验证输出只保留在可清理临时目录，没有入库。

## 目标资源基线

| Canonical Catalog | Wishlist duplicate | SHA-256 | 单文件源码 bytes | 像素 | 单个分析条目 bytes |
| --- | --- | --- | ---: | --- | ---: |
| `shop_product_02.png` | `recent_hat.png` | `b2743d8386cdb54b10005968f512f4f19d570b2abf93462a129f430823398251` | 94,364 | 400x266 | 94,394 |
| `shop_product_03.png` | `recent_pink_dress.png` | `13f312380775702d4a73cde53201ab6d50cf55043e706f14db44c42c3d28725d` | 151,297 | 266x400 | 151,347 |
| `shop_product_04.png` | `recent_red_dress.png` | `6439bd8738a4b952a29248415ce4e39778d122daeb012d2acb3f3064951bef45` | 128,262 | 266x400 | 128,302 |

六个文件都位于 `base/assets/flutter_assets/packages/app_features/assets/images/` 下的独立 AAB 条目，分析条目
合计 748,086 bytes。三份 Wishlist 重复源码合计 373,923 bytes；该数值只是后续计划删除的源码字节，不是
本卡宣称的包体收益。

## 可比输入摘要

摘要使用仓库相对路径排序，并按 `path + NUL + raw bytes + NUL` 计算 SHA-256。输入来自 Demo、Workspace
Packages、Native 工程及 Workspace Flutter 配置；只包含 Git 已追踪或未忽略文件，因此排除了 build、cache、
`.dart_tool` 和 `.flutter-plugins-dependencies` 等本机生成文件。

- 稳定 build input：651 个文件，
  `df46a579ffc763e258a994d6290832029c1715abb48db0c97adfeb37318669d6`。
- 计划修改输入：7 个文件，
  `d2099bc729f9711f8773c9439141193ca100fe574955e3e0ab52b6cb7c5ec4bc`。
- 计划清单：Wishlist Fixture、Wishlist local data source 测试、Wishlist Asset 测试、`app_features/pubspec.yaml`
  和三个 Wishlist 重复 PNG。

## 构建环境与参数

- macOS 26.2（25C56，arm64）。
- Flutter 3.41.9（framework `00b0c91f06`）、Dart 3.11.5、DevTools 2.54.2。
- JBR 17.0.12、Gradle 8.12、AGP 8.9.1、Kotlin 2.1.0、默认 NDK 28.2.13676358。
- Android SDK 35.0.0、Platform android-36、Build Tools 35.0.0、Command-line Tools 21.0。
- 无 flavor；Release；仅 `android-arm64`；默认 icon tree shake；无 obfuscation、无 split debug info。

执行 `flutter clean` 和 `make bootstrap` 前后，`git status --porcelain=v1` 完全一致。正式命令为：

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build appbundle \
  --release --target-platform android-arm64 --analyze-size \
  --code-size-directory <temporary-baseline-directory>
```

## 验证

有界证据再次校验了 AAB/JSON 字节和 SHA-256、`base/assets` 数值、六个 AAB 条目、三组 byte-for-byte
SHA-256 以及 canonical PNG 像素尺寸，全部通过。完整摘要见
[测试证据](test-evidence/measure-android-catalog-wishlist-asset-baseline.log)。

未发现 P0/P1/P2。该基线只用于同机器、同工具链、同命令且稳定 build input 摘要一致的后续 Android arm64
Release AAB 比较，不能外推到 APK、其它 ABI 或 iOS IPA。
