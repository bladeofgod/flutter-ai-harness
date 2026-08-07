---
task: add-workspace-dependency-consumption-checker
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/tool/check_package_dependencies.dart
  - app/tool/check_flutter_plugin_discovery.dart
  - app/test/package_dependency_checker_test.dart
  - scripts/lint/repository-boundaries.sh
  - scripts/lint/test-repository-boundaries.sh
  - docs/architecture.md
implementationDigest: a1dcb294630f9fc563f718a15cce2f1adaa903ec87c187f11265c053faf040ff
---

# Security Review：实现 Workspace 依赖消费检查器

## 首轮问题

### P1：外部结构化输入必须失败关闭且不得泄露路径

- 资产：开发机路径、Workspace 依赖边界与 Plugin 注册来源。
- 入口：显式 graph、Workspace root、package pubspec 和 `.flutter-plugins-dependencies`。
- 路径：损坏 JSON 字段类型或符号链接 pubspec 若进入直接转换/读取，可能产生未捕获异常或读取
  Workspace 边界外文件。
- 修法：Workspace entry 拒绝绝对路径、反斜线、空段和 `..`；Package 目录与所有结构化输入要求普通
  文件/目录，canonical path 必须留在 root；所有格式/文件错误输出固定脱敏消息。

## 已检查边界

- Analyzer 只解析 Dart 文本的 AST，不执行被扫描源码，不加载其中的 URI，也不启动构建器或插件代码。
- 唯一子进程为固定参数的 `dart pub deps --json`；不使用 Shell 插值，不接受调用方命令或环境变量名。
- Plugin 必要性要求目标 pubspec 声明的 Android/iOS 平台都在 discovery 中有唯一 production native
  entry，路径等于普通 Workspace Package；pub graph 证明其它生产依赖不可达时才允许无源码 import。
- 诊断只含闭合 Package 名和固定分类，不输出 graph/discovery 中的绝对路径或原始错误内容。
- 新增 `analyzer 10.0.1` 直接 dev 声明；该版本、Hosted 来源和 SHA-256 已存在于 lockfile且未变化。
- 默认 `make lint` 本卡不启用已知失败的消费模式；只读盘点命令明确预期非零，后续清理卡负责接线。
- 未增加网络、凭据、CI、Agent、MCP、原生权限、构建、发布、commit 或 push 能力。

两份直接绑定依赖/Plugin 门禁以及五份共享 lockfile/架构报告已完成影响复审并更新摘要。最终
P0/P1/P2 为 0/0/0；完整验收输出记录于本任务证据文件。

## 冗余依赖清理后的影响复审

消费模式现在作为默认 `make lint` 的真实 Workspace 门禁运行；Fixture 模式仍只执行隔离依赖矩阵，专属
Dart 测试覆盖未消费边、无消费者 Package 与 Plugin 传递可达性。`app_im` 已从 Workspace、矩阵和当前
文档删除，Demo 的允许矩阵也收窄为 `app_data`、`app_features`、`app_ui`；检查器在真实图上退出 0，
负向 Fixture 证明真实 import 不能恢复底层 Runtime 直连。输入 canonicalization、普通文件要求、固定
子进程参数与脱敏诊断未放宽，未增加网络、凭据或执行能力，P0/P1/P2 维持 0/0/0。

## Wire Formatter 工具依赖影响

根工具新增精确固定的 `dart_style 3.1.7` direct dev dependency，并由 Wire generator 直接 import，符合
消费门禁。lockfile 固定 Hosted 来源与 SHA-256，既有 analyzer 依赖图已包含其余依赖；检查器的 AST
解析、路径约束、固定子进程与脱敏诊断均未改变，P0/P1/P2 维持 0/0/0。
