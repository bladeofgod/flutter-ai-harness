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
implementationDigest: 78025b39156273473be99a569443f5b22dfb80ab366d07b6208d56bd56e508d6
---

# Security Review: Android Media Capture 单平台质量门禁

> 后续文件身份修正把生产 `android.system.Os` instrumented suite 纳入编译与可选 emulator Gate，并将
> Bridge 精确计数更新为 71。Gate 现在读取 emulator SDK，只有 API 23 结果才关闭最低版本运行缺口；
> 当前无 ready emulator 的证据仍明确标记未运行。新增测试依赖均固定版本并进入 strict dependency
> verification；独立 Security Review 为 P0/P1/P2 0/0/0，本报告按原文件集合刷新摘要。

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

## 跨 Runtime 集成影响

Android Contract Vector Gate 现在逐节消费完整 V4/V3 golden，验证结果仍为 Core 88、UI 42、Bridge 71；
文档明确保留无 ready emulator/API 23/真机缺口。生产模块未改，独立安全复审为 P0/P1/P2 0/0/0。

## Flutter 3.41.9 Gradle verification 复审

工具链升级后，Gradle 官方 `--write-verification-metadata sha256` 只补充了
`androidx.exifinterface:1.4.1` 的 AAR/module 和当前 Flutter Engine commit 对应 embedding
JAR/POM 的精确 SHA-256。repository 集合、strict verification 模式、依赖选择逻辑和执行权限
均未变；Gate 的已审查整文件摘要同步更新。独立 Security Reviewer 确认
P0/P1/P2 0/0/0，完整 Android Gate 和 Debug APK 构建均通过。

## CI JUnit BOM module metadata 复审

CI 冷缓存会为既有 JUnit BOM 5.10.2 和 5.9.2 请求 Gradle Module Metadata，而旧清单只有 POM 摘要。
本轮使用 Gradle 8.12 官方 `--write-verification-metadata sha256` 只增加这两个 `.module` SHA-256；没有
新增版本、artifact 类型、repository、依赖声明或宽松验证规则。Gate 对 metadata 的整文件摘要同步更新，
strict dependency verification 配置阶段重新通过。独立 Security Reviewer 确认 P0/P1/P2 0/0/0。

后续 Linux CI 进入资源编译后还会请求固定 AGP 8.9.1 对应的 AAPT2 Linux JAR。本轮使用临时 Gradle
configuration 与官方 `--write-verification-metadata sha256` 解析该精确 classifier，生成后移除临时配置；
最终工程依赖图不变。metadata 现同时固定唯一的 osx/linux 平台 artifact，未发现其他平台 classifier
缺口，repository 和 strict verification 仍失败关闭。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。
