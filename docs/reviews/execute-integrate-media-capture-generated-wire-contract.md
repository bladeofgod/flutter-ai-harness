---
task: integrate-media-capture-generated-wire-contract
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：集成 Media Capture 三端 Wire 生成链路

## 结论

- `make media-capture-wire-check` 依次只读检查 Dart/Kotlin/Swift，已接入 `make check`、pre-push 和 CI check
  Job；`media-capture-wire-generate` 是独立写入 target，门禁不会自动修复工作树。
- 三端共享 normalized descriptor digest
  `76e65a567971ca209e0b4f50412e79002a83eda04869149f21d136a7c6569d27`，覆盖 Wire 3、17 methods、5
  events、14 result types、1 failure type、36 errors、28 payload descriptors 和 40 fields。
- Contract implementation digest 为 `b5aeb860…`；Dart/Android/iOS 生成输出 implementation digest 分别为
  `99fc39ef…`、`b8bf9e69…`、`26592a0b…`。共享 golden 同时绑定生成元数据和六个 Runtime consumer digest。
- Harness 校验 generator 入口、renderer 三端 marker、普通文件/非 symlink 输出、source/implementation digest
  与 consumer bindings；测试覆盖手改输出、Contract 未再生成、只生成一端、删 marker、输出 symlink 和
  renderer 缺失六类 drift。
- Generator 只拥有协议标识、闭合 enum、descriptor、字段约束和基础 codec primitive；Capability mapping、
  dispatch/lifecycle、UI thread/MainActor、presentation、transfer store、文件 cleanup、日志与 Native 能力仍为
  手写边界。

## 三端证据

- Dart：drift/analyze 通过，129 tests passed。
- Android：Core 88x2、Native UI 42x2、Bridge 75x2 tests；lint、AAR、contract gate通过；无 ready emulator。
- iOS：四个 generic compile，Simulator 107+52+70 tests，safe-copy 与临时 Host discovery 通过；真机 Camera、
  权限、麦克风、中断和性能未验证。
- 真实 Demo Host：Android Debug APK `app-debug.apk` 构建通过；iOS Debug no-codesign `Runner.app` 构建通过，
  CocoaPods 继续服务其它既有插件，Media Capture 仍通过 Flutter SwiftPM discovery，不增加 fallback。
- 最终 `make check` 退出 0，覆盖 prerequisites、format/analyze、三端 drift、Harness 1172、lint/Fixture、
  evidence、proto 与全部 Workspace Flutter tests；之后独立 `make harness-check`、`make evidence-lint` 和
  `git diff --check` 继续通过。

集成命令/Host 构建见[集成证据](test-evidence/integrate-media-capture-generated-wire-contract.log)，平台完整输出见
[Dart](test-evidence/generate-media-capture-dart-wire-codec.log)、
[Android](test-evidence/generate-media-capture-android-wire-codec.log) 与
[iOS](test-evidence/generate-media-capture-ios-wire-codec.log)。复审未发现 P0/P1/P2。
