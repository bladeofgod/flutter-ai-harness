---
executor: android-engineer
platforms: [android]
workKinds: [bridge-adapter]
blockedBy:
  - media-capture-android-export-bridge-adapter
securityReview: required
---

# 加固 Android Transfer Store 文件身份

## 输入与事实来源

- 最终 Cross-runtime Integration 安全复核发现，现有 Store 虽校验 canonical root 与 symlink，但
  `verifyRoot()`、`FileOutputStream`、`renameTo()` 之间仍是多次路径解析。
- Wire V3 transfer store、Capability V4 typed sink、`kotlin-android-standards` 与
  `native-testing-strategy`。

## 目标

- staging 创建和整个写入事务绑定同一 regular-file identity，不跟随被替换的链接。
- final 发布不覆盖已存在目标，且发布后的 final identity 必须与已写 descriptor 一致。
- 保持容量、TTL、release、Engine detach、错误脱敏和 source lease 语义不变。

## 非目标

- 不修改 Capability、Wire、Dart、Flutter、iOS、Host、业务或共享 golden 语义。
- 不把路径、FileDescriptor 或 Android SDK 文件对象暴露到公共 API/Channel。

## 实现路径与验收

本任务只写 Android Transfer Store 生产实现、对应测试及本任务 Review/Security/evidence：

- staging 使用 `O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC` 和 owner-only mode 创建。
- begin/write/commit 每个阶段校验同一 device/inode、regular file、单 link 和精确 size；descriptor 由
  reservation/sink 线性拥有并 exactly-once close。
- final 使用 no-replace 语义发布，已存在目标或身份漂移必须失败并清理自身 staging，不能覆盖外部条目。
- 增加 staging/final 替换、symlink、length drift、重复 abort/delete 和 root replacement 回归测试。
- Android Bridge tests、专项 Gate、Debug APK、`git diff --check` 与 Harness 通过；独立普通与安全
  Review 清零 P0/P1 后归档。

## 环境限制

同 App UID 内任意代码仍属于同一进程信任域；本任务加固文件系统竞态，不把 App 私有目录描述为跨进程
安全沙箱。Android 公共 `Os` API 不提供 descriptor-relative `unlinkat`，因此身份检查与 pathname unlink
之间仍存在同 UID 信任域内的残余竞态；文档与 Review 必须准确保留该边界。真机 Camera/权限与媒体内容
不属于本修正，API 23 的生产 Store instrumented runtime 需要对应 emulator/device。

## 执行结果

- [实现 Review](../../reviews/execute-media-capture-android-transfer-store-file-identity-correction.md)
- [Security Review](../../reviews/security-media-capture-android-transfer-store-file-identity-correction.md)
- [测试证据](../../reviews/test-evidence/media-capture-android-transfer-store-file-identity-correction.log)
