---
task: media-capture-ios-quality-gate
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - scripts/quality/media-capture-ios.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-host-route.sh
  - app/packages/app_media_capture_bridge/ios/tool/test-safe-workspace-copy.sh
  - docs/native/media-capture-ios-verification.md
implementationDigest: eaee514d0f9916ad753634d1211125abf8f956b9f36b7e58957c923db66c0349
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
