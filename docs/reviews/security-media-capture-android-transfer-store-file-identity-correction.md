---
task: media-capture-android-transfer-store-file-identity-correction
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/native/android/media_capture_gate/gradle/verification-metadata.xml
  - app/packages/app_media_capture_bridge/android/build.gradle.kts
  - app/packages/app_media_capture_bridge/android/src/androidTest/kotlin/com/example/media_capture/MediaCaptureTransferStoreInstrumentedTest.kt
  - app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt
  - app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/MediaCaptureBridgeControllerTest.kt
  - app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/MediaCaptureTransferStoreTest.kt
  - app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/TestTransferFileSystem.kt
  - scripts/quality/media-capture-android.sh
  - docs/bridge/media-capture-android.md
  - docs/native/media-capture-android-verification.md
implementationDigest: bf3cd5244b9b3fd372a0f63af49e0ca31378b45d6bdcf53a7611ee4041c44d2a
---

# Security Review：Android Transfer Store 文件身份修正

## 结论

独立 Security Review 与修复复审通过，P0 0、P1 0、P2 0。Security Reviewer 未读取普通 Review 结论，
只读核对任务、精确实现文件和原始 evidence，没有运行命令或修改文件。

## 资产与信任边界

- 受保护资产是 App 私有 cache 中尚未导入 `app_media` 的 transfer 内容、descriptor、容量账本和返回给
  Dart 的脱敏 file locator。外部可控输入仍限于受校验的 media metadata/handle；路径和 descriptor 不
  进入公共 API 或 Channel。
- staging 使用 owner-only mode 与 `O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC`。begin/write/commit 将
  descriptor 与 pathname 的 device/inode、regular type、size 和 link count 绑定；发布使用同目录 hard
  link no-replace，不覆盖既有 final。
- cleanup 只删除属于 reservation identity 的 regular file。foreign final、symlink 或目录不会被误删，
  同时 reservation/capacity 可以收敛；identity 匹配但删除失败时仍保留账本并有界重试。
- raw descriptor 在首次 `fstat` 失败时 exactly-once close；Store/Sink 不再存在反向锁获取。多 Engine
  root lease 防止活跃 transfer 被 startup sweep 删除。

## 供应链、日志与剩余风险

新增 AndroidX test 依赖均固定版本并进入 Gradle strict dependency verification，metadata 使用 SHA-256；
未增加动态版本、本机仓库、凭据或生产依赖。evidence 已脱敏，不包含设备 ID、账号、真实媒体、handle、
文件路径或密钥。

Android 公共 `Os` 不提供 `unlinkat`，身份检查和 pathname unlink 仍是两个系统调用；能利用该窗口的代码
已经位于同 App UID 信任域。本任务没有宣称跨越该边界。生产 `Os` instrumented APK 已编译，但当前没有
ready emulator；API 23 runtime 是明确保留的设备环境验证项，不影响本次静态安全结论。

## CI Gradle metadata 增量复审

JUnit BOM 5.10.2 与 5.9.2 的版本和来源均未变化；本轮只为 CI 冷缓存实际请求的两个 `.module` 文件增加
Gradle 官方生成的精确 SHA-256，并同步 Gate 的整文件摘要。没有改变 transfer store、AndroidX test
依赖或 repository 边界，strict verification 仍失败关闭。独立 Security Reviewer 确认 P0/P1/P2 0/0/0。

Linux CI 后续请求的 AAPT2 JAR同样通过临时 Gradle configuration 与官方摘要生成流程固定；临时配置未
进入最终工程。该 artifact 属于既有 AGP 8.9.1 工具链，不改变 transfer store、instrumented test 或
生产代码依赖，metadata 仍只允许已审查 SHA-256。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。
