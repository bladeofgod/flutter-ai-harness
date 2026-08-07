---
executor: android-engineer
platforms: [android]
workKinds: [quality-gate, documentation]
blockedBy:
  - deduplicate-catalog-wishlist-assets
---

# 验证 Catalog 与 Wishlist Asset 去重的 Android 包体收益

## 输入与事实来源

- `measure-android-catalog-wishlist-asset-baseline` 的 Review/evidence、命令参数、AAB/Asset 指标和 build input
  digest。
- `deduplicate-catalog-wishlist-assets` 的精确实现文件、测试证据和 373,923 bytes 源码减少量。
- `flutter-app-size` Skill 关于同平台、架构、模式和参数比较的要求。

## 目标

- 在与 baseline 相同的环境和逐字相同的 Android arm64 Release AAB 参数下生成 post Size Analysis。
- 报告 AAB/Asset 实测 delta 和比例，将真实产物收益与源码减少量明确区分。

## 非目标

- 不修改 Flutter Asset、Fixture、pubspec、Android Native 代码或构建配置。
- 不为获得更大数字改变压缩、ABI、flavor、tree-shake、obfuscation、debug symbol 或缓存条件。
- 不把 Android arm64 AAB 结果外推到 APK、其它 ABI 或 iOS IPA。

## 验证要求

1. 先验证 baseline 的稳定 build input digest；除 Asset 去重卡列出的文件外，任何 Flutter source、依赖、
   pubspec、lockfile、Gradle/Manifest 变化都使比较失效。失效时停止并要求重建可比 baseline，不做跨状态减法。
2. 确认三个 Wishlist 重复文件/asset 声明/旧引用为零，三个 canonical Catalog 文件 SHA-256 与 baseline
   相同，聚焦 Flutter 测试已有通过证据。
3. 使用与 baseline 相同 SDK、OS、机器、clean/bootstrap 步骤和命令，仅更换临时
   `--code-size-directory`：

   ```bash
   TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build appbundle \
     --release --target-platform android-arm64 --analyze-size \
     --code-size-directory <temporary-post-directory>
   ```

4. 在 Review 中并列表格记录 before/after/delta/比例：AAB 精确字节、Size Analysis 总量、Asset 总量、三组
   资源归属；另列源码减少 373,923 bytes。完整 JSON/AAB 不入库，只记录分析文件 digest 和必要摘要。
5. 收益为零、负值或小于源码减少量时如实解释压缩/打包观测，不添加新的资源编码或依赖优化。只要比较
   有效、重复资源确实移除且行为测试通过，本任务记录真实结果，不设虚构的最低 byte 门槛。

## 验收与验证

```bash
make harness-check
git diff --check
```

- post AAB/Size Analysis 有效且参数与 baseline 完全一致。
- 报告可复核、没有混入其它 build input 变化或把源码字节冒充产物收益。

## 环境限制

必须使用 baseline 记录的 Android SDK/JDK/Flutter 和机器条件；环境不可复现时任务保持未完成。iOS 包体
收益是明确未测量项，不得由 Android 结果替代。
