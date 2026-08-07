---
executor: android-engineer
platforms: [android]
workKinds: [quality-gate, documentation]
blockedBy:
  - add-session-reset-registration-disposal
  - integrate-media-capture-generated-wire-contract
  - remove-unused-workspace-dependencies
---

# 测量 Catalog 与 Wishlist Asset 的 Android 包体基线

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 7 项和 `flutter-app-size` Skill。
- 三组已确认 byte-for-byte 相同的 Catalog/Wishlist PNG，共有 373,923 bytes 重复源码。
- `remove-unused-workspace-dependencies` 完成后的稳定 Workspace 依赖图；包体基线必须在依赖清理后采集，
  避免把无关依赖变化计入 Asset 收益。
- Flutter 3.41.9 `build appbundle --analyze-size` 要求 Android 单一 ABI。

## 目标

- 在修改任何目标 Asset/Fixture 前，生成 Android arm64 Release AAB 和 Size Analysis 基线。
- 记录可由下游同参复测独立校验的工具链、构建参数、产物指标和稳定 build input digest。

## 非目标

- 不修改、移动或删除 Asset、Fixture、pubspec、生产代码或原生工程。
- 不测 Debug/Profile、其它 ABI、APK 或 iOS IPA，不把源码字节当 AAB 收益。
- 不提交完整 Size Analysis JSON、AAB、Gradle cache 或其它构建产物。

## 测量要求

1. 确认 `deduplicate-catalog-wishlist-assets` 尚未执行，六个 PNG 都存在且三组 SHA-256 相等；记录各文件
   hash、字节和像素尺寸。发现目标已变化时停止，不能用 post 状态伪造 baseline。
2. 记录 Flutter/Dart/Java/Gradle/AGP/Kotlin 版本、OS、无 flavor、Release、单一 `android-arm64`、默认
   tree-shake、无 obfuscation、无 split-debug-info 和完整命令。先清理构建输出并 bootstrap，确认没有意外
   修改受版本控制文件。
3. 执行：

   ```bash
   TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build appbundle \
     --release --target-platform android-arm64 --analyze-size \
     --code-size-directory <temporary-baseline-directory>
   ```

4. 在标准实现 Review 中记录：AAB 精确字节、Size Analysis 总量/Asset 量、六个文件的打包归属、分析文件
   SHA-256 和命令退出码。完整分析文件只留在可清理临时目录。
5. 为下游隔离比较计算两个稳定摘要：
   - 排除本次计划修改的三个重复 Asset、`app_features/pubspec.yaml`、Wishlist Fixture/Asset 测试后的其余
     Flutter build input digest。
   - 计划修改输入的独立 digest 和文件清单。
   摘要必须按仓库相对路径排序，排除 build/cache/本机生成文件，且不含绝对路径。

## 验收与验证

- AAB 和 Size Analysis 均为有效 Release/arm64 产物，报告字段足以由 post 卡逐项比较。
- 测量没有修改应用、脚本、Asset、lockfile 或原生文件；只产生任务标准 Review/evidence/归档产物。

```bash
make harness-check
git diff --check
```

## 环境限制

需要锁定 Flutter、JDK 和 Android SDK。该基线只适用于记录的 Android arm64 AAB 参数；后续若有任何不在
Asset 去重文件清单内的 build input 变化，基线失效，必须停止而不能跨状态比较。
