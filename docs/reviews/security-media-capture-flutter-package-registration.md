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
implementationDigest: 3daa5a1f998bcdb7084339f6a779234a6f451d3dcbf19471a948856b0c5f8cd0
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
- lockfile 只把 Flutter SDK 下限对齐到仓库锁定的 3.35.7，没有改变 Package 版本、来源或校验值。
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
