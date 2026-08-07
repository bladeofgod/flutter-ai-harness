---
task: verify-android-catalog-wishlist-asset-size
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：验证 Catalog 与 Wishlist Asset 去重的 Android 包体收益

## 结论

在与 baseline 同机器、同工具链、同 clean/bootstrap 步骤和逐字相同构建参数下，Android arm64 Release
AAB 实测减少 375,441 bytes（1.3159%）。`base/assets` 实测减少 374,088 bytes（4.2039%），post AAB 中
只剩三份 Catalog canonical PNG，三个 Wishlist 重复条目为零。

## 可比性

- 稳定 build input：651 个文件，摘要继续为
  `df46a579ffc763e258a994d6290832029c1715abb48db0c97adfeb37318669d6`，与 baseline 完全一致。
- 三个被删文件和 Wishlist Asset 目录均不存在；生产 Flutter/Android/iOS 旧引用为零。
- 三份 canonical PNG SHA-256 继续为 `b2743d83…`、`13f31238…`、`6439bd87…`，与 baseline 一致。
- `flutter clean` 和 `make bootstrap` 前后 Git 状态完全一致。
- 环境继续使用 macOS 26.2 arm64、Flutter 3.41.9、Dart 3.11.5、JBR 17.0.12、Android SDK
  35.0.0/Platform 36/Build Tools 35.0.0、Command-line Tools 21.0、Gradle 8.12、AGP 8.9.1、Kotlin
  2.1.0、默认 NDK 28.2.13676358。
- 无 flavor；Release；仅 `android-arm64`；默认 tree shake；无 obfuscation、无 split debug info。

两次命令仅临时分析目录不同：

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build appbundle \
  --release --target-platform android-arm64 --analyze-size \
  --code-size-directory <temporary-directory>
```

## Before / After

| 指标 | Before bytes | After bytes | Delta bytes | Delta |
| --- | ---: | ---: | ---: | ---: |
| AAB 精确文件 | 28,530,515 | 28,155,074 | -375,441 | -1.3159% |
| Size Analysis 根条目压缩值之和 | 28,429,397 | 28,054,726 | -374,671 | -1.3179% |
| `base/assets` | 8,898,633 | 8,524,545 | -374,088 | -4.2039% |
| `flutter_assets` | 8,266,966 | 7,892,923 | -374,043 | -4.5245% |
| 六/三份目标资源分析条目 | 748,086 | 374,043 | -374,043 | -50.0000% |

- Baseline AAB SHA-256：`36c5ce820626abec5cabe54e3e2419ab12f4b98a183b9aafb4eb87142ce64350`。
- Post AAB SHA-256：`61aeca7d8111b41424d8387e3f9d73529d58f140c1fbae706c97790b0f51522d`。
- Baseline Analysis SHA-256：`bf76c61ab13520d4943f954ab74b8dbd3a823290f5ddaacb6173ef89a85ef631`。
- Post Analysis SHA-256：`a07ae1a1bc201ce082005c1ceeffa7d5927ef138983363cb72b7b5fb1d9a9bc6`。

完整 AAB、Size Analysis JSON、AOT trace/snapshot 与验证输出只保留在可清理临时目录，没有入库。

## 数值解释

删除的三份 PNG 源码为 373,923 bytes。Size Analysis 的三个被删资源条目为 374,043 bytes，多出的 120
bytes 是条目结构开销；`base/assets` 还包含 AssetManifest/key 等变化，因此减少 374,088 bytes。AAB 文件
总量还受 ZIP、签名/metadata 与 Fixture 死配置移除后的 AOT 细微变化影响，最终减少 375,441 bytes。报告
分别保留这些指标，没有把源码字节冒充产物收益。

## 验证

两次 AAB 命令退出码均为 0；有界证据独立校验 AAB/JSON hash、总量、Asset 数值、三份 canonical 条目和
旧条目为零，全部通过。见[测试证据](test-evidence/verify-android-catalog-wishlist-asset-size.log)。

未发现 P0/P1/P2。该结果只适用于本次 Android arm64 Release AAB，不外推到 APK、其它 ABI 或 iOS IPA。
