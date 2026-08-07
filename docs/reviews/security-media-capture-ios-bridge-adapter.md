---
task: media-capture-ios-bridge-adapter
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Package.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeController.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureBridgeModels.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureServices.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/MediaCaptureBridgeCore/MediaCaptureWireCodec.swift
  - app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Sources/app_media_capture_bridge/MediaCaptureBridgePlugin.swift
  - app/packages/app_media_capture_bridge/ios/tool/Package.core-tests.swift
  - app/packages/app_media_capture_bridge/ios/tool/copy-safe-workspace.sh
  - app/packages/app_media_capture_bridge/ios/tool/safe-rsync-copy.sh
  - app/packages/app_media_capture_bridge/ios/tool/test-safe-workspace-copy.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh
  - app/packages/app_media_capture_bridge/ios/tool/verify-host-route.sh
implementationDigest: 8450b04661de8915899e3d1f226c37e43ce5c9df8445299214d3416b688136dc
---

# Security Review: iOS Media Capture Bridge Adapter

> 后续 iOS Quality Gate 安全修正只加固本报告绑定的三个 helper：Bridge 使用结构化 `.xcresult` 精确计数，
> Host 使用隔离 HOME/cache 与白名单环境，原始成功/失败 build log 不再外显，复制夹具补齐敏感扩展和
> 多类逃逸 symlink，临时清理不跟随链接。独立 Security 复审为 P0/P1/P2 0/0/0；生产 Adapter、Wire、
> 权限和 owner 生命周期未变化，本报告按原 12 文件集合刷新摘要。

## 结论

最终独立只读 Security Review 通过，P0 0、P1 0、P2 0。审查绑定上述 12 个实现与验证文件及当前摘要，
未读取普通 Review 结论。Method/Event Channel 输入、owner/Engine 生命周期、权限与硬件、媒体 bytes、
错误脱敏、临时工作区、SwiftPM 依赖和 Agent 能力边界均未发现可利用的阻断路径。

## 已确认控制

- Wire 入站使用精确 key、类型、枚举、finite/range、request ID 和 opaque handle 校验；错误只返回固定
  code/message 与 allowlist details，不回显 payload、handle、bytes、路径或底层异常。
- Flutter completion/Event sink 在 MainActor 恰好一次完成；Session/preview 绑定精确 owner，confirmed
  lease 转为 Engine-owned。owner destroy、Scene disconnect、hierarchy loss、dismiss、detach 和迟到结果
  均 fail closed 并执行有界资源清理。
- Camera 硬件与授权始终在展示 UI 前预检；只有 video+audio 才预检 Microphone。Native Core 保留第二次
  权限检查，覆盖预检后的系统变化。
- thumbnail 只接受已接管 media handle、64...512 edge、最多 512 KiB 的 sanitized JPEG；验证 marker、
  metadata、尺寸和 orientation，失败、owner loss、detach 与迟到完成都会清空临时 bytes。
- SwiftPM 只声明仓库本地 Core/UI product；没有远程 package、binary target、本机 Flutter framework、
  CocoaPods fallback、CI/发布或全局 Flutter 配置写入能力。
- 临时目录使用 `mktemp`、`umask 077`/`chmod 700`、signal cleanup、`--safe-links` 和越界链接复核。
  当前 evidence 未发现真实设备标识、用户名、home/repo/临时路径、凭据或环境文件内容。

## 后续影响复核

Transfer Adapter 任务已关闭原两个 P2：安全复制现在大小写不敏感拒绝环境文件、签名材料和敏感
xcconfig，并增加混合大小写 fixture；Core/Host helper 将 DerivedData 置于受限临时根，自行脱敏 home、
repository、temporary path、Simulator ID 与 UUID，并对残余值 fail closed。独立 Security Reviewer
确认本报告原 12 个实现文件边界继续成立；新增 Transfer Store 由独立 export 安全报告绑定。

后续严格并发 correction 只把 Controller 私有 `ActivePresentation` 显式归入 MainActor，使 session、dismiss
flag、settlement state 与 continuation 保持既有 Controller 隔离；没有改变入站 Wire、owner identity、
dismiss-wins、late lease cleanup、Engine detach 或错误脱敏。69 个 Bridge Core XCTest 与完整严格并发
generic build 通过，本报告摘要机械更新到当前实现快照。

## 真机边界

Framework Fake、Simulator 与 no-codesign Host build 不证明真实 Camera/Microphone、系统权限弹窗、前后
摄像头、带音频录像、中断、存储压力、后台恢复、真实缩略图内存行为、最终 Runner 的 Info.plist/注册或
codesigned 安装。上述能力仍由最终 Integration/Quality Gate 和用户真机验收确认。

## iOS 综合修正后的最终复审

Bridge helper 现在复用父 Gate 选定并精确验证的 Simulator，结构化结果只输出固定分类、整数计数和最多
五个白名单测试标识；原始日志、failure text、路径、UUID 与设备标识不外显。重试只覆盖无结构化测试
失败的基础设施类失败，断言失败不重试。独立 Security Reviewer 确认 P0/P1/P2 0/0/0，69 项测试通过。

## 2026-08-04 CI 冷启动门禁增量复审

本轮只收紧已有 CI 与测试边界：Android strict verification 为既有 Guava/Kotlin POM 增加精确摘要，
未增加 repository、版本或宽松规则；iOS 固定 `macos-26`、Xcode 26.5 与 iOS 26.5 runtime，使用 Gate
自建、自启、自删的临时 Simulator，并把 0-test 失败限制为脱敏固定分类。Bridge helper 保持一次有界
基础设施重试和精确 69/69，通过测试修正消除 owner cleanup 观察竞态。跨 Runtime golden 只刷新既有
iOS loader 的 consumer digest，Capability/Wire current/history 均未变化。独立 Security Reviewer 结论为
P0/P1/P2 0/0/0；本报告原有剩余项保持不变，摘要按当前 implementationFiles 重新绑定。
