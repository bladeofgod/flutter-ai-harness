---
task: media-capture-android-export-bridge-adapter
status: passed
p0: 0
p1: 0
p2: 1
implementationFiles:
  - app/packages/app_media_capture_bridge/android/build.gradle.kts
  - app/packages/app_media_capture_bridge/android/settings.gradle.kts
  - app/packages/app_media_capture_bridge/android/src/main/AndroidManifest.xml
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureBridgeController.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureBridgePlugin.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureWireCodec.kt
  - docs/bridge/media-capture-android.md
  - scripts/quality/media-capture-android.sh
implementationDigest: 295403ffaf3907098034a8e95fce5c98e4e1d4765c5191d75b72de19fbb038c9
---

# Security Review：Android Transfer Bridge Adapter

> 后续文件身份修正把 Transfer Store 改为 descriptor/device/inode/link/size 绑定、hard-link no-replace，
> 并修复 cleanup 锁顺序、foreign identity 容量收敛和首次 `fstat` 失败的 descriptor 关闭。独立 Security
> Review 最终为 P0/P1/P2 0/0/0，未改变 Wire、容量、TTL 或 source/export ownership 语义；本报告按原
> 实现文件集合刷新摘要，原结论继续成立。

独立 Security Review 最终通过，P0/P1 为 0。私有 canonical cache root、symlink 拒绝、CSPRNG handle、
容量预留、原子 commit、URI/错误脱敏和 source/export ownership 顺序均闭合。TTL/release 删除失败会保留
记录与容量并自动有界重试，只有实际删除成功后才归还容量。

P2：补 Engine detach 持续删除失败与后台重试耗尽后的直接测试，Owner 为 `android-engineer`。

## CI Gradle metadata 增量复审

Android Gate 仅通过 Gradle 官方 `--write-verification-metadata sha256` 补充 JUnit BOM 5.10.2 与 5.9.2
两个既有 `.module` artifact 的摘要，并同步 Gate 对整份 metadata 的受审 SHA-256。没有修改 Bridge
生产依赖、repository、Wire 或 transfer ownership。strict verification 仍失败关闭，独立 Security
Reviewer 未发现新的 P0/P1/P2；本报告原有的一个测试覆盖 P2 保持不变。

后续 CI 运行继续解析到 AGP 8.9.1 的 AAPT2 Linux classifier。本轮通过临时 Gradle configuration 让
Gradle 官方解析固定的 `aapt2:8.9.1-12782657:linux` artifact 并生成 SHA-256，临时 configuration 随即
移除。metadata 现同时固定 osx/linux AAPT2，Bridge 依赖和原有 P2 均未变化。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。
