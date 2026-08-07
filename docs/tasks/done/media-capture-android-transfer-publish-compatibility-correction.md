---
executor: android-engineer
platforms: [android]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-android-transfer-store-file-identity-correction
securityReview: required
---

# 修复 Android Transfer 发布兼容性

## 输入与事实来源

- Android 16 真机在客服服务页完成拍摄并进入结果预览后，点击发送返回
  `mediaExportSinkRejected`；原生日志将失败阶段定位到 `publish_link`。
- 同一流程在引入 hard-link no-replace 发布前可用；当前设备的 App cache 文件系统拒绝
  `Os.link()`，导致安全发布策略成为设备兼容性故障点。
- `kotlin-android-standards`、`native-testing-strategy` 与现有 Transfer Store 文件身份不变量。

## 目标

- 不依赖 hard link 或 rename，在最终扩展名路径上以 no-follow、exclusive-create 语义预留并写入文件。
- descriptor、pathname、device/inode、regular-file type、size 与单 link 身份校验覆盖 begin/write/commit。
- 保持不覆盖外部条目、身份漂移失败关闭、容量账本、清理和脱敏错误语义。
- 恢复 Android 真机拍摄结果从预览页发送到 Flutter 的客服服务流程。

## 非目标

- 不修改 Capability、Wire、Dart、Flutter、iOS、Host 或业务页面语义。
- 不放宽 App 私有 cache 根目录、symlink、hard-link drift、size drift 或 owner-only mode 校验。
- 不把路径、FileDescriptor 或 Android SDK 文件对象暴露到公共 API/Channel。

## 实现路径与所有权

本任务只写 Android Transfer Store、对应测试、Android Gate/说明文档及本任务自己的 Review/evidence：

- `app/packages/app_media_capture_bridge/android/src/main/kotlin/com/example/media_capture/MediaCaptureTransferStore.kt`
- `app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/MediaCaptureTransferStoreTest.kt`
- `app/packages/app_media_capture_bridge/android/src/test/kotlin/com/example/media_capture/TestTransferFileSystem.kt`
- `app/packages/app_media_capture_bridge/android/src/androidTest/kotlin/com/example/media_capture/MediaCaptureTransferStoreInstrumentedTest.kt`
- `scripts/quality/media-capture-android.sh`
- `docs/bridge/media-capture-android.md`
- `docs/native/media-capture-android-verification.md`

## 实现与验收要求

1. begin 在最终扩展名路径使用 `O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC` 预留文件，并通过同一
   descriptor 写入；不得使用生产 hard link 或 rename 发布。
2. write/commit/abort 必须保留 identity、regular type、size、link count 和 exactly-once close 不变量；
   close 失败不得提交，abort 必须能够重试关闭。
3. 单元测试覆盖写入、length drift、pathname replacement、symlink/hard-link drift、abort 和 cleanup；
   instrumented APK 必须可编译。
4. Android Quality Gate、Harness、diff check 与独立普通/Security Review 通过。
5. Android 16 真机客服服务拍摄、结果预览、发送流程由用户手动验收通过。

## 环境限制

自动门禁不替代真机 Camera、权限和厂商文件系统行为。真机验收只证明本次连接设备上的用户路径；其他
Android 版本仍由单元测试、instrumented APK 编译和后续设备矩阵覆盖。

## 执行结果

- 实现改为在最终扩展名路径上以 `O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC` 预留文件，并通过同一
  descriptor 写入、校验和关闭；生产代码不再使用 hard link 或 rename 发布。
- 补充 close 失败不提交、abort 可重试关闭、路径替换、symlink/hard-link drift、length drift 和 cleanup
  相关覆盖；Android gate 增加 Transfer Store hard-link/rename 静态拦截。
- [实现 Review](../../reviews/execute-media-capture-android-transfer-publish-compatibility-correction.md) 通过，
  P0/P1/P2 均为 0。
- [Security Review](../../reviews/security-media-capture-android-transfer-publish-compatibility-correction.md) 通过，
  P0/P1/P2 均为 0，implementationDigest 绑定当前实现。
- [测试证据](../../reviews/test-evidence/media-capture-android-transfer-publish-compatibility-correction.log)：Android
  media capture gate exit code 0；instrumented APK suite 编译通过；没有 ready emulator，因此
  `connectedDebugAndroidTest` 未运行。
- Android 16 真机客服服务页拍照、结果预览、发送闭环由用户手动验收通过。
