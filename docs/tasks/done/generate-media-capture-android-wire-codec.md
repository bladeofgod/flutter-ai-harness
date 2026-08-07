---
executor: android-engineer
platforms: [android]
workKinds: [bridge-adapter]
blockedBy:
  - define-media-capture-wire-generation
securityReview: required
---

# 迁移 Android Media Capture Wire 生成代码

## 输入与事实来源

- `define-media-capture-wire-generation` 的 Contract manifest、generator 和 Kotlin renderer。
- `app/packages/app_media_capture_bridge/android/` 的 `MediaCaptureWireCodec.kt`、Bridge Controller/Plugin、
  JVM/Robolectric 测试和 Android contract vector gate。
- Android Native Module 保持手写的 Capability、生命周期、线程和资源所有权契约。

## 目标

- 生成并接入 Android Runtime 的稳定 Wire 标识、枚举、payload descriptor、字段范围和基础 codec。
- 删除 Kotlin Adapter 内重复的手工协议表，同时保持 main-thread callback、Native mapping、transfer store、
  presentation 和 lifecycle coordinator 行为不变。

## 非目标

- 不修改 Contract/generator、Dart/iOS、Android Native Module、Host/Manifest 或 Capability。
- 不生成 CameraX/Activity、coroutine scope、request/owner generation、late cleanup、文件系统或 transfer store。
- 不改变 Wire V3 shape、error details、权限或 Native UI 流程。

## 实现要求

1. 只通过 `--runtime android` 生成约定 `*.g.kt`，禁止手工修改；Gradle source set 必须从仓库相对路径编译
   该文件，不复制到 build cache 或 Host。
2. 手写 Codec/Controller 使用生成 version/channel/method/event/result/error、field descriptor和 scalar/
   envelope primitive。删除 manifest 已拥有的重复集合；Capability `FailureCode` 映射、线程调度、dispatch、
   transfer/presentation 状态机继续手写。
3. 生成到 Kotlin 标识的 escaping、signed-64、nullable/unknown key、ByteArray和闭合 enum 必须 fail-closed；
   wire 值不能来自 Kotlin enum name 或平台对象描述。
4. 保持 17 methods/5 events、全部恶意 vector、URI/handle/thumbnail、error source/redaction、Engine detach、
   Activity destroy 和 exactly-once completion 的行为证据。
5. JVM/Robolectric 测试新增生成 drift、descriptor 与 Contract coverage；现有 controller/codec/transfer 测试
   继续验证实际行为。Android contract vector gate必须消费同一 Contract/golden，而不是复制第三份表。

## 写入所有权

- `app/packages/app_media_capture_bridge/android/**`
- `docs/bridge/media-capture-android.md` 中生成边界与真实验证状态

不得修改 `app/native/android/**`、Dart/iOS、共享 Contract/generator、Host 或最终集成文档。

## 验收与验证

```bash
cd app && dart run tool/generate_media_capture_wire.dart --runtime android --check
bash scripts/quality/media-capture-android.sh
app/apps/demo/android/gradlew -p app/packages/app_media_capture_bridge/android test lint assembleDebug
make harness-check
git diff --check
```

## 环境限制

需要仓库锁定的 JDK、Android SDK、AGP/Kotlin/Gradle。JVM Fake 不替代 Host plugin registration或设备生命周期；
本卡没有 Android 设备时明确记录，不用 Dart/iOS 结果替代平台编译。
