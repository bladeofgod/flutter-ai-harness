---
task: media-capture-ios-quality-gate
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - scripts/quality/media-capture-ios.sh
  - scripts/flutter-tool.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-host-route.sh
  - app/packages/app_media_capture_bridge/ios/tool/test-safe-workspace-copy.sh
  - docs/native/media-capture-ios-verification.md
implementationDigest: 76382601650c94db83293cfc797ae3425e3463fc7b1c2c5f8408b811054918a3
---

# Security Review：iOS Media Capture 单平台质量门禁

## 结论

独立 Security Review 与修复复审通过，P0 0、P1 0、P2 0。Security Reviewer 未读取普通 Review 结论，
只读核对任务、实现、辅助复制边界和原始 evidence，没有修改文件。

## 已关闭问题

- 三个可执行 `Package.swift`、Core test 临时 Package 模板和所有直接 helper 在首次 manifest/helper 执行
  前校验已审查 SHA-256；摘要漂移直接失败，不先运行未知 Swift manifest。
- 临时 Host build 通过 `env -i` 只接收已校验 Flutter executable/root、固定系统 PATH、隔离 HOME/TMP/
  Pub/XDG cache、locale 和可选 `DEVELOPER_DIR`，不继承 Token、签名变量、SSH agent 或用户 Flutter/Dart
  配置。真实 Host 与 `.flutter_settings` 仍有前后内容摘要保护。
- 所有 build/test 原始日志只留在 mode 0700 临时根内；成功和失败路径只输出固定门禁结论，不能由不可信
  build phase 把凭据、路径或设备信息带入 evidence。临时目录使用 `find -P -depth -delete`，不跟随被替换
  的链接。
- safe-copy fixture 覆盖 `.env*`、本地配置、证书、私钥、Provisioning、keychain、敏感 xcconfig 的常见
  扩展及大小写，同时验证直接、绝对、目录和链式逃逸 symlink。复制实现继续使用 `rsync --safe-links`
  并在目标树结构化复核每个 symlink 的 realpath。
- 路径不再作为未转义正则插入 `sed`；Gate 不外显原始日志，因此关闭了路径正则注入和脱敏失败风险。

## 剩余边界

临时 Host 会从公开、锁定的 Flutter/Dart/CocoaPods 来源解析隔离 cache；Gate 不注入凭据，也不增加发布、
签名、commit 或 push 能力。Simulator/临时 Host 仍不能证明真机 Camera、Microphone、权限、硬件中断和
性能；证据中没有用户名、主机路径、Simulator ID、UUID、真实媒体或凭据。

## iOS 综合修正后的最终复审

Gate 将已选 Simulator 通过受控环境变量交给 Bridge helper，并在运行前执行 result-policy fixture。输入必须
精确匹配 available iPhone；诊断仅允许固定分类、整数计数和白名单测试标识。仅无结构化测试失败时重试
一次，最终成功要求 Core/Rendering 107、UI 52、Bridge 69 项精确通过。独立 Security Reviewer 确认
P0/P1/P2 0/0/0；无新增网络、凭据、权限、依赖或 Agent 能力。

## CI Flutter 入口修正复审

iOS Gate 现在通过仓库 `scripts/flutter-tool.sh` 解析 Flutter，不再把本机 FVM 作为唯一入口。本地仍优先
使用 FVM，CI 则使用固定 Commit 的 Flutter Action 提供的 SDK；Gate 继续精确校验 Flutter 3.41.9、
绝对 SDK root 和可执行文件类型。该调整没有新增权限、凭据、动态插件来源或任意环境变量覆盖入口。

独立 Security Reviewer 确认 P0/P1/P2 0/0/0。CI 所需 ripgrep 由跨 Runtime 集成门禁固定版本和摘要安装，
不改变 iOS Gate 的测试、临时 Host 隔离或真机验收边界。

## CI Simulator 基础设施失败复审

Core 与 UI runtime test 现在为固定 Simulator destination 提供 120 秒发现等待。`xcodebuild` 非零退出后，
若结构化 `.xcresult` 明确包含真实 failed test，则立即失败且不重试；若没有 result bundle、bundle 不可读
或摘要没有 failed test，则只重试一次。第二次仍必须由 Xcode 成功退出，并满足精确测试总数以及
failed/skipped/expected failure 全为 0，永久失败不能被重试掩盖。

最终失败只输出固定类别和整数计数，不输出原始 result JSON、构建日志、路径或 Simulator 标识。独立
Security Reviewer 确认 P0/P1/P2 0/0/0；本地 iOS 18.5 Simulator 的 Core 107、UI 52、Bridge 69 项运行层
通过。Xcode 26.5 下后续临时 Host 构建失败单独保留，不被误记为本次 Simulator 修复已完整通过。
