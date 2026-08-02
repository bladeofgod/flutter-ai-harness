---
task: media-capture-ios-quality-gate
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：iOS Media Capture 单平台质量门禁

## 结论

独立普通 Review 与修复复审通过，P0 0、P1 0、P2 0，可以归档。最终 Reviewer 只读核对任务、Gate、
三个直接 helper、验证文档和原始 evidence，没有修改文件。

## 已确认项

- 三个 Swift Package 在执行 manifest 前先绑定已审查摘要，随后使用结构化 `swift package dump-package`
  精确核对 tools/platform/dependency/product/target 图；生产源码 import 递归解析且未知形态失败关闭。
- Core、Rendering、UI、Bridge Core 分别在自己的 Package 目录完成 generic iOS Simulator SDK compile，
  使用完整严格并发检查；任何 build failure 或并发告警都使 Gate 非零。
- 源码测试矩阵固定为 101/51/69，多或少一项都失败。三个 Simulator runtime 层均读取 `.xcresult`，
  要求 total/passed 精确相等，failed/skipped/expected failure 全为 0；Bridge helper 和主 Gate 双重核对
  同一个 69 项 result bundle，不依赖日志正则。
- 没有可用 iPhone Simulator 时只跳过 runtime XCTest；四个 generic compile、Package/Contract 检查和
  临时 Flutter Host build 仍为强制项。
- 临时 Host 只证明 Flutter 3.35.7 SwiftPM Plugin discovery 和 no-codesign build；真实 Runner 仍由最终
  Integration 接线和构建，文档没有把临时 Host 提升成 Demo Runner 已集成。

## 验证与剩余边界

[测试证据](test-evidence/media-capture-ios-quality-gate.log) 保留了一次隔离 cache 依赖解析失败及随后的
完整成功重跑。最终 Gate 退出 0：四个 generic compile、101/51/69 Simulator XCTest、safe-copy fixture
和隔离临时 Flutter Host 全部通过；evidence lint 与 shell syntax 同样通过。

本门禁不证明真机 Camera/Microphone、系统权限 UI、真实帧、硬件中断或设备性能。真实 Demo Runner 的
SwiftPM 接线和 no-codesign build 也不属于本任务，仍由跨 Runtime Integration 提供证据。
