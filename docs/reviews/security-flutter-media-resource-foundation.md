---
task: flutter-media-resource-foundation
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_core/lib/value/media_resource_id.dart
  - app/packages/app_core/lib/app_core.dart
  - app/packages/app_media/lib/app_media.dart
  - app/packages/app_media/lib/src/resource/default_media_resource_store.dart
  - app/packages/app_media/lib/src/resource/flutter_image_canonicalizer.dart
  - app/packages/app_media/lib/src/resource/local_media_resource_file_system.dart
  - app/packages/app_media/lib/src/resource/media_resource_factory.dart
  - app/packages/app_media/lib/src/resource/media_resource_file_system.dart
  - app/packages/app_media/lib/src/resource/media_resource_models.dart
  - app/packages/app_media/lib/src/resource/media_resource_store.dart
  - app/packages/app_media/lib/src/resource/media_resource_support.dart
  - app/packages/app_media/pubspec.yaml
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/packages/app_features/pubspec.yaml
  - app/apps/demo/pubspec.yaml
  - app/tool/check_package_dependencies.dart
  - scripts/lint/repository-boundaries.sh
  - scripts/lint/test-repository-boundaries.sh
implementationDigest: 4dd7c28583d68a06a4c82678c6db69a55088a2478a6a04beb17cec11ae951d00
---

# Security Review: Flutter 媒体资源存储基础件

## 首轮结论

独立只读 Security Review 未通过，P0 0、P1 1、P2 2。审查覆盖不可信 `file:` URI、symlink/
traversal/TOCTOU、App 私有 root、CSPRNG ID、图片解码与 metadata、视频容器验证、内存 DoS、引用/
清理竞态、错误脱敏、新依赖和 Agent 能力边界；首轮没有读取普通 Review 结论。

## P1

### Source final symlink 的检查与打开不是同一线性化点

`LocalMediaResourceFileSystem` 先用 `followLinks: false` 检查输入路径，再调用
`resolveSymbolicLinks` 并打开 canonical path。可变 source path 在两步之间替换成 symlink 时，后续
digest/mtime 复核可能验证 symlink 目标本身，弱化任务要求的“拒绝 symlink source”边界。

修复要求：从 canonical parent 构造 final child，打开前后重复确认原始 final component 与 canonical
child 都是非 symlink regular file、parent identity 未变化且解析结果一致；读写始终使用确认后的
canonical child。补 final component 在 verification hook 中替换为 symlink 的图片/视频测试。Dart V1
不把该收窄表述成操作系统级 `O_NOFOLLOW`；调用方仍只允许传用户选择或 App 自建 transfer copy。

## P2

### 图片 decoded-memory 上限偏高

40MP 图片的 RGBA 解码约占 160 MiB，叠加输入和 PNG 输出可能造成移动端内存压力。修复为明确的 decoded
byte budget，在 instantiate codec 前拒绝超过预算的 descriptor，并增加边界测试。

### ISO BMFF 校验只检查首个 ftyp 头

任意非零 major brand 都能通过当前检查。修复为 bounded box walk、MP4/MOV brand allowlist，并至少要求
`ftyp` 后存在合理的 `moov` 或 `mdat` box；仍不把容器检查表述成真实 decoder probe。

## 已确认边界

- `MediaResourceId` 为 128-bit CSPRNG 派生的闭合 ID，诊断输出脱敏。
- Store root 和目标文件名闭合，`.part` 与同目录 rename 不接受调用方目标路径。
- resolve 会复核受控根、文件类型、长度和签名。
- 公共错误、请求和资源模型不输出路径、URI、原始异常或媒体 bytes。
- `path_provider`、`crypto` 与 `path` 使用公开锁定来源；未扩大 Agent、MCP、CI 或发布能力。

## 验证缺口

首轮为只读静态审查，没有运行命令。修复后必须重跑聚焦测试、analyze、依赖门禁、Harness，并由独立
Security Reviewer 复审当前实现摘要。

## 修复后复审

独立 Security Reviewer 复审通过，当前 P0 0、P1 0、P2 0：

- `_inspectSource` 从 canonical parent 构造 final child，并在原始路径和 canonical child 上重复执行
  non-follow 类型与 resolved path 一致性检查；读完后再次复核 path、mtime、长度和 SHA-256。Dart V1
  不声称提供 OS 级 `O_NOFOLLOW` 或 fd identity，真实 Picker/Bridge source 由后续平台任务继续验证。
- 图片 descriptor 在 codec 初始化前执行 64 MiB decoded RGBA 预算；边界测试覆盖 4096x4096 与超限。
- ISO BMFF 使用 brand allowlist 和 64 KiB bounded box walk，并要求 `moov` 或 `mdat`；仍不冒充 decoder
  probe。
- pending deletion 在资源不可解析后保留 cleanup ownership，重复 release、后续操作和 dispose 可继续
  bounded retry。

修复后聚焦测试、analyze、全量测试、lint、format 与 `git diff --check` 均通过；未发现新的安全问题。

## 媒体预览接入后复审

独立 Security Reviewer 确认预览公共 API 与依赖接入没有放宽 Store 的 source symlink/TOCTOU、
decoded-byte budget、ISO BMFF bounded walk、pending-delete ownership 或 lease 幂等边界。共享入口、
pubspec、lockfile 和依赖门禁继续保留在实现文件集合中；当前结论仍为 `P0=0`、`P1=0`、`P2=0`。

## 跨 Runtime 集成影响

根 Workspace 新增的 `xml` 仅是 Harness 的直接 dev dependency，用于结构化校验 iOS plist；不进入
`app_media` Runtime。Store ownership、locator 隔离和 cleanup 语义不变，独立安全复审为 0/0/0。

## Workspace SwiftPM Bootstrap 配置影响

根 Workspace 新增项目级 SwiftPM 布尔配置，只影响 Flutter Plugin 的构建选择，不增加 Runtime 依赖、
媒体输入、文件访问、网络来源或权限。`app_media` Store、canonicalization、lease 和 cleanup 实现未改，
锁文件内容保持不变。隔离 Runner 配置下的 bootstrap 已通过，本报告 P0/P1/P2 维持 0/0/0，并按原文件
集合重新绑定摘要；独立增量安全复核未发现新的供应链或 Runtime 信任边界风险。
