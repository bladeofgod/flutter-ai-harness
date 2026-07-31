---
executor: android-engineer
platforms: [android]
workKinds: [quality-gate]
blockedBy:
  - media-capture-android-bridge-adapter
  - media-capture-android-core
  - media-capture-android-native-ui
securityReview: required
---

# 建立 Android Media Capture 单平台质量门禁

## 输入与事实来源

- 已完成 Android Core、Native UI、Bridge Adapter 及各自 Review/Security/evidence。
- 最新 Capability/Wire Contract、Kotlin/Android 与 Native Testing Skill。
- 锁定 Android 工具链和当前 CI Android Debug build 基线。

## 目标

- 建立可重复执行的 Android 专项门禁，统一运行 Core/UI/Adapter 单测、lint、依赖图和编译检查。
- 从单平台视角验证三层语义一致、无 Flutter/Core 反向依赖、无共享资源泄漏，并准确记录设备缺口。
- 为最终 Integration 提供一条可接入 Makefile/CI 的平台脚本和已脱敏证据。

## 非目标

- 不修改 Capability/Wire、Dart Client、Host/Manifest、共享 docs/Registry、root Validator、CI/Makefile。
- 不实现缺失功能或用 Fake 结果宣称真机 Camera/权限通过；发现实现缺陷应回到对应任务修复/复审。
- 不执行 iOS 或跨 Runtime 最终验收。

## 实现路径与所有权

本任务只写：

- `scripts/quality/media-capture-android.sh`
- `app/native/android/media_capture_gate/**`（仅确有必要的跨模块测试工程/fixture）
- `docs/native/media-capture-android-verification.md`
- 本任务 Review/Security/evidence

不得编辑 Core/UI/Adapter 生产代码、Host 或共享聚合入口。最终 Integration 是 Makefile、CI 和 Host 的
唯一写入者。

## 门禁要求

1. 脚本使用 `set -euo pipefail`、仓库相对路径和锁定 wrapper，依次运行 Android Core/UI/Adapter 的
   tests、lint、assemble/compile 和跨模块 contract vectors；任一步失败返回非零。
2. 验证 Gradle 图中 Core 不依赖 Flutter，UI 只依赖 Core，Adapter 依赖 Core/UI/Flutter API，模块依赖
   版本/来源可复现且没有本机绝对路径、动态版本或未使用依赖。
3. 聚焦竞态矩阵覆盖 session/lease cleanup、两类 Native Preview attachment 的 generation/single attach/
   detach/revoke/rotation/background/owner destroy、Activity/Engine lifecycle、exactly-once、固定 poster/
   thumbnail bounds、permission denial 和 UI 三终态；平台门禁不得修改共享 Contract 来迁就实现。
4. 验证 Capability V3 concrete `MediaCaptureRenderView` 的 production 接线：live 安装真实 CameraX
   SurfaceProvider，photo/video preview 使用模块私有 source；replacement、detach、background、owner
   destroy 后 provider/player/content 清空且旧 generation 不能修改 target。Robolectric 只证明接线，
   真机 Gate 另行证明实际 live frame。
5. 若有可用 emulator，运行不需要真实 Camera 的 instrumented lifecycle/UI tests；无 emulator 时明确
   记录未运行命令。Camera/Microphone/权限/硬件中断/性能只能在明确真机上验证，证据不得含设备 ID、
   用户名、主机路径或真实媒体。
6. 验证文档区分 local unit、Framework Fake、instrumented、Host（尚未接线）和真机层级，列出每项
   命令/状态/剩余风险；不能把本门禁误述为 Flutter Host build。

## 验收标准

- 专项脚本在标准 Android SDK/JDK 环境一次命令通过，失败路径可复现。
- Core/UI/Adapter 的公开语义与最新 Contract 一致，平台内部没有跨 Runtime/共享文件越权。
- Android Gate 报告可被最终 Integration 引用；Host 注册和 APK build 仍明确未验证。

## 验证命令

```bash
bash scripts/quality/media-capture-android.sh
make harness-check
git diff --check
```

## 环境限制

需要 Android SDK/JDK/Flutter SDK 与公开依赖缓存/网络。Emulator/真机不是静态 Gate 的伪前置；未提供
时必须准确记录对应未验证项，最终 Host APK 由跨 Runtime Integration 构建。

## 执行结果

专项静态 Gate、独立普通 Review 与 Security Review 已通过；无 ready emulator，因此 instrumented APK
仅完成编译，Host 与真机验证仍按原边界留给后续任务。
