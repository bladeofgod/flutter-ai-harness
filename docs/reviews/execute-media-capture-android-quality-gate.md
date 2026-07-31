---
task: media-capture-android-quality-gate
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: Android Media Capture 单平台质量门禁

## 审查闭环

独立普通 Review 首轮为 P0 0、P1 5、P2 1。阻断项包括缺少可运行的 instrumented lifecycle/UI suite、
所谓 contract vectors 未读取 Capability/Wire JSON、Gradle 文本 allowlist 可忽略未知 DSL、最终 evidence
未绑定最新脚本、concrete renderer 没有直接验证 background 后真实 target 清理；另发现 Adapter 的
`activity-ktx` 没有生产消费者。

最终复审确认上述实现问题均已关闭：

- `app/native/android/media_capture_gate/` 提供独立的 cross-module Gradle root、受控 wrapper、严格依赖
  校验、无 Camera instrumented lifecycle/UI suite，并在每次静态 Gate 编译其 APK；本机无 ready emulator，
  因此没有宣称 instrumented runtime 通过。
- Adapter test source set 直接消费当前 Capability V3 与 Wire V2 JSON，核对 Core API/enum、UI config、14
  个 Wire method、5 个 event、failure、channel、opaque handle 和 thumbnail bounds；没有复制 Android
  私有 Contract。
- Core test source set 新增 3 个 production renderer background 用例，直接验证 CameraX provider、照片
  drawable、VideoView/player target 清空和旧 target retirement。
- Gradle wrapper launcher/jar/properties 在执行前校验 exact SHA-256；distribution 使用官方 URL 与 SHA-256；
  六个模块 Gradle 输入使用 reviewed digest，repository 使用 fail-on-project-repos，artifact 使用 strict
  dependency verification metadata。
- 模块 Debug/Release 总数和重点契约类用例数均为 exact baseline，任何 skipped/failure/error 都使 Gate
  非零退出；`rg` I/O 错误也不再被当作无匹配。
- 未使用的 Adapter `activity-ktx` 已移除，Adapter 原有 Debug/Release 各 35 个测试和 lint 已独立重跑。

最终独立普通复审没有剩余实现 P0/P1/P2。任务归档后执行仓库 `harness-check`，结果追加到本任务 evidence。

## 验证

证据：`docs/reviews/test-evidence/media-capture-android-quality-gate.log`。

- Core Debug/Release：66/66 tests，0 skipped/failure/error。
- Native UI Debug/Release：38/38 tests，0 skipped/failure/error。
- Bridge Adapter Debug/Release：37/37 tests，0 skipped/failure/error；其中 2 个为 Gate 注入的 Contract JSON
  vectors，Adapter 独立任务仍为原有 35/35。
- 三个模块 lint、Debug/Release AAR、实际 `debugRuntimeClasspath` 解析通过。
- cross-module Gate lint、Debug/Release AAR 和 `assembleDebugAndroidTest` 通过。
- concrete renderer、UI lifecycle、Bridge lifecycle、bounded transport 和 JSON Contract 重点类逐项强制
  重跑并满足 exact baseline。
- 没有 ready emulator；`connectedDebugAndroidTest` 未运行。Flutter Host、Camera/Microphone、真实出帧、
  硬件录像/中断和性能仍由 Integration/真机 Gate 验证。
- `make lint`、`make format`、`git diff --check` 通过；归档后的 `make harness-check` 见同一 evidence。
