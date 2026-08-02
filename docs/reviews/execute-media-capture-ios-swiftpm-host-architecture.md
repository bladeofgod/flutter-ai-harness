---
task: media-capture-ios-swiftpm-host-architecture
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：iOS Media Capture SwiftPM Host 架构

## 结论

独立普通 Review 通过，P0 0、P1 0、P2 0，可以归档。本轮 Reviewer 只读检查任务、架构、四张后续
任务卡、安全报告与证据，没有运行命令或修改文件。

## 已确认项

- 官方 Flutter 3.35.7 模板探针精确确认 standalone package 失败来自缺少 Host 注入的 `Flutter` 模块；
  首轮负断言误命中和修正后的成功分类均诚实保留在证据中，没有冒充产品代码构建。
- 构建证据分为 Bridge Core 独立 iOS SDK compile、临时 Flutter Host Plugin build 和最终 Integration
  真实 Demo Host 迁移三层，彼此不能替代。
- Base Adapter、Export Adapter、Quality Gate 与 Integration 的依赖和写入所有权单向且无循环；前置
  Adapter 不修改真实 Host，最终 Integration 才拥有 Demo `pubspec.yaml` 与 Runner Xcode project。
- 临时 Host 使用副本内项目级 SwiftPM 开关，禁止全局配置、本机 Flutter binary path 和 CocoaPods
  fallback，并要求敏感材料排除、用户私有目录权限、全退出路径清理和证据脱敏。
- CocoaPods 可以继续服务其它既有插件，但不属于 Media Capture 路线；生成的
  `FlutterGeneratedPluginSwiftPackage` 与 ephemeral package 不入库。
- Frontmatter、Executor、平台范围、DAG 和验证命令与任务正文一致。

## 验证与剩余边界

[测试证据](test-evidence/media-capture-ios-swiftpm-host-architecture.log) 记录最终 `make lint`、
`make harness-check` 和 `git diff --check` 均退出 0。临时 Host 脚本、Plugin target、真实 Runner 和真机
Camera 尚未实现，分别由后续 Adapter、Quality Gate、Integration 和人工真机验收负责，不阻断本架构
任务归档。
