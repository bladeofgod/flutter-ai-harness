---
task: media-capture-android-quality-gate
status: passed
p0: 0
p1: 0
implementationFiles:
  - scripts/quality/media-capture-android.sh
  - app/native/android/media_capture_gate/.gitignore
  - app/native/android/media_capture_gate/build.gradle.kts
  - app/native/android/media_capture_gate/gradle.properties
  - app/native/android/media_capture_gate/gradle/verification-metadata.xml
  - app/native/android/media_capture_gate/gradle/wrapper/gradle-wrapper.jar
  - app/native/android/media_capture_gate/gradle/wrapper/gradle-wrapper.properties
  - app/native/android/media_capture_gate/gradlew
  - app/native/android/media_capture_gate/settings.gradle.kts
  - app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt
  - app/native/android/media_capture_gate/src/androidTest/AndroidManifest.xml
  - app/native/android/media_capture_gate/src/androidTest/kotlin/com/example/mediacapture/gate/MediaCaptureGateInstrumentedTest.kt
  - app/native/android/media_capture_gate/src/coreTest/kotlin/com/example/mediacapture/MediaCaptureRenderBackgroundGateTest.kt
  - app/native/android/media_capture_gate/src/main/AndroidManifest.xml
  - docs/native/media-capture-android-verification.md
implementationDigest: f19d1ffa3d3cdb05531a0cb904a5522e1c0698d22300680a2fa7888d384fc0fd
---

# Security Review: Android Media Capture 单平台质量门禁

## 最终结论

独立 Security Review 首轮为 P0 0、P1 4、P2 2。最终复审为 P0 0、P1 0、P2 0，安全门禁通过。

已关闭问题：

- Gate 不再执行 Demo Host 中被忽略、未校验的生成 wrapper；专用 wrapper launcher、官方 Gradle 8.12
  wrapper jar、properties、distribution URL 和 distribution SHA-256 均在执行任何 Gradle 输入前校验，
  symlink 和 Git-ignored 文件被拒绝。
- 六个 Gradle build/settings/properties 使用 exact reviewed digest，projectDir 还需匹配固定仓库相对路径和
  canonical realpath；这使额外 `api`/`runtimeOnly`、buildscript/plugin、block repository、local file 或
  越界 project 不能被文本提取器静默忽略。
- 所有 artifact 在统一 Gate root 下使用 strict dependency verification SHA-256 metadata；repository mode
  禁止 subproject 自行增加来源，当前只允许 Google、Maven Central 和 Flutter 官方 Maven。
- instrumented Gate 只在恰好一个 ready emulator 且没有物理设备时运行，并通过私下设置
  `ANDROID_SERIAL` 绑定目标；命令与 evidence 不打印 serial。当前无 emulator，只编译 APK。
- 模块测试要求 exact 总数和 0 skipped/failure/error；重点契约矩阵进一步逐 class 锁定 exact 数量，删除
  bounded transport、renderer、Wire 或 JSON vector 不能由其它新增测试补平。
- `rg` 的无匹配与 I/O/权限错误显式区分；后者 fail closed。evidence 未发现用户名、主机路径、设备 ID、
  真实媒体、凭据或 Figma 信息。

Review 期间任务文件处于 execute-tasks 的未提交工作树阶段。最终 Reviewer 确认这不是可利用实现缺陷：
wrapper 不在 ignore 中且在执行前受 exact hash 约束；本报告再以 implementation digest 绑定全部实现文件。
最终提交必须包含该列表中的全部新增文件。

## 剩余边界

本门禁不扩大 Agent 权限，不接 Host，不请求 Camera/Microphone，也不读取真实媒体。没有 emulator/真机时，
Activity runtime、系统权限、CameraX 出帧、编码器、中断和性能保持未验证；跨 Runtime 共享 golden 仍由最终
Integration 创建。这些限制均在平台验证文档与 evidence 中明确记录，没有用 Fake/Robolectric 冒充设备
结果。
