---
task: measure-android-catalog-wishlist-asset-baseline
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/tasks/done/measure-android-catalog-wishlist-asset-baseline.md
implementationDigest: e24e592b76c8911550203dd551ddeed15896843274a12d5e0f31660f1abdca6f
---

# Security Review：测量 Catalog 与 Wishlist Asset 的 Android 包体基线

## 已检查边界

- 本任务只构建现有 Demo 并读取 AAB、Size Analysis 和目标 PNG 元数据，没有修改生产代码、依赖、Manifest、
  权限、签名、Wire Contract、媒体 locator 或 cleanup ownership。
- 构建使用现有 Android Debug keystore 的 Release 本地分析产物，不执行发布、上传、签名分发、commit 或
  push；AAB 和完整分析文件只存在于可清理临时目录。
- 报告仅记录工具版本、相对路径、字节、像素和 SHA-256，不包含用户目录、设备标识、凭据、Token、证书、
  私钥或原始用户数据。有界证据经过仓库脱敏和结构门禁。
- 为满足 Flutter AAB debug-symbol 校验，本机 Android SDK 增加官方 Command-line Tools 21.0；仓库依赖、
  lockfile 和供应链声明未改变。构建使用的 Flutter、JDK、SDK、Gradle、AGP、Kotlin 与 NDK 版本均已固定在
  Review 中。
- 稳定 build input 摘要排除 build/cache/本机生成文件，后续比较必须先验证摘要，防止把无关源码或依赖
  漂移错误归因于 Asset 去重。

## 结论

未发现新增的信任边界、敏感数据流、外部输入执行、权限扩大或供应链漂移。P0/P1/P2 为 0/0/0。该结论只
覆盖本地 Android arm64 Release 体积测量，不将产物视为可发布构建，也不替代真实发布签名与渠道审计。
