---
task: media-capture-flutter-package-registration
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/apps/demo/pubspec.yaml
  - app/packages/app_media_capture_bridge/pubspec.yaml
  - app/tool/check_package_dependencies.dart
  - app/tool/check_flutter_plugin_discovery.dart
  - scripts/lint/repository-boundaries.sh
  - scripts/lint/test-repository-boundaries.sh
  - CLAUDE.md
  - docs/architecture.md
  - docs/zh-CN/index.html
  - docs/index.html
implementationDigest: 0a854d78a51599cf0ba0d5da632d00be65801b13c61f81f84783b4bf7e475ea1
---

# Security Review: Media Capture Flutter Package 登记

## 结论

最终独立 Security Review 通过，P0 0、P1 0、P2 0。审查覆盖 Workspace 本地依赖来源、Plugin
discovery 生成输入、构建代码来源、符号链接替换、依赖方向和证据脱敏。

## 已关闭问题

首轮复审发现，若受信 Package 目录本身被符号链接替换，同时 canonicalize 期望路径与 discovery 路径
会让两者一起指向未审查代码。最终门禁改为从固定 Workspace 根逐段定位
`packages/app_media_capture_bridge`，对 `packages` 和目标 Package 使用 `followLinks: false`，只接受普通
目录，再执行 canonical containment 与 discovery identity 校验。

Fixture 分别证明目标 Package 指向 Workspace 内其他目录和 Workspace 外目录时均失败；同时保留唯一性、
production dependency、native build、预期路径和 dependency graph 的失败关闭验证。错误只输出固定诊断，
不回显生成 graph 中的绝对路径或内容。

## 已确认边界

- `resolution: workspace` 与 `publish_to: none` 没有新增远程或 Git 依赖来源。
- lockfile 随 Flutter 3.41.9 / Dart 3.11 更新 SDK 约束相关传递依赖，没有新增 Package 来源。
- 新增检查通过固定参数调用，不加入 shell 拼接、安装脚本、CI/Agent 权限或发布能力。
- `CLAUDE.md` 和两份 HTML 只同步依赖事实，没有扩大 Agent 工具或注入可执行内容。

## 验证与剩余风险

最终 evidence 中 `pub get`、正向 discovery、全部失败 Fixture、format、analyze、lint、Harness 和 diff
检查均为退出码 0。本结论不替代 Android Host 构建、真实 Plugin 注册、平台权限或 Camera 真机验证。

## 当前实现复审

独立只读复审重新检查 Workspace/Plugin 依赖、`publish_to: none`、Plugin discovery 的唯一性与生产
模式、仓库内 regular directory/symlink 防护，以及依赖矩阵没有反向放宽。当前实现未发现 P0、P1
或 P2，摘要可同步到当前文件集合。本轮未执行 `pub get`、lint 或 Host build，运行时注册仍由后续
集成验证覆盖。

## 当前文件摘要复核

独立安全复审确认本任务 implementationFiles 未被 V4 Harness 修复改写，Workspace、Plugin discovery、
regular-directory/symlink 防护和依赖方向保持不变。当前实现 `P0=0`、`P1=0`、`P2=0`；摘要按当前
文件集合重算。

## 媒体预览依赖接入后复审

独立 Security Reviewer 确认 Bridge Package 仍为 Workspace 本地、`publish_to: none` 的 production
plugin；discovery 仍要求唯一插件、预期路径、regular directory、no-symlink 和 canonical identity。
媒体预览 hosted 依赖没有放宽 Bridge plugin discovery、依赖方向或发布能力。当前结论仍为
`P0=0`、`P1=0`、`P2=0`。

## 跨 Runtime 集成影响

真实 Demo 已启用项目级 SwiftPM；根 `xml` 仅为 Harness 直接 dev dependency，不进入 Plugin Runtime。
Host 仍使用标准注册、仓库相对依赖且无远程 SPM/本机 framework，独立安全复审为 0/0/0。

## Workspace SwiftPM Bootstrap 配置复核

根 Workspace 与 Demo Host 现在都显式启用项目级 SwiftPM，保证 Workspace 根的 `flutter pub get` 与最终
Host 使用同一 Plugin 构建方式，不读取或修改全局 Flutter 配置。Bridge Package 仍为 Workspace 本地、
`publish_to: none`，依赖清单和 lockfile 均未改变，也没有新增远程 SPM、脚本或发布能力。隔离配置下的
Melos bootstrap 与完整 `make bootstrap` 已通过；独立增量安全复核确认 P0/P1/P2 维持 0/0/0，本报告
按原文件集合刷新摘要。

## 中英文详细指南原生能力同步复核

两份静态 HTML 详细指南只同步既有原生 Agent 路由、Native Module/Bridge/Host 依赖方向、已锁定平台
技术栈、Media Capture 参考链路与现有 CI 门禁事实。页面没有增加脚本、表单、远程可执行资源、依赖源、
Agent 能力或 CI 权限；新增外链只指向仓库内已存在的事实文档。Workspace Package、Plugin discovery、
SwiftPM 接线及发布边界均未改变，P0/P1/P2 仍为 0/0/0，摘要按当前 implementationFiles 重新绑定。
