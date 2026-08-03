# iOS Media Capture 验证分层

本文说明 iOS Media Capture 的专项质量门禁证明了什么，以及哪些结论必须留给最终 Host 集成或真机。
一键入口是：

```bash
bash scripts/quality/media-capture-ios.sh
```

脚本要求 macOS、当前 Xcode、仓库锁定的 Flutter 3.41.9、Ruby 和可用的 iOS Simulator SDK。脚本使用
权限仅限当前用户的临时目录，并在退出时清理自己的 DerivedData、日志与中间文件。

## 验证层级

| 层级 | 专项门禁行为 | 可以证明 | 不能证明 |
| --- | --- | --- | --- |
| Swift unit | 检查 Core/Rendering、UI、Bridge Core 的必需 XCTest 与精确测试矩阵 | 状态机、错误、取消、exactly-once、generation、owner/Engine cleanup、transfer 边界有回归测试 | Apple Framework 或 Flutter Host 的真实接线 |
| Framework Fake | 在可用 Simulator 上运行 Package XCTest | 权限、Camera、Clock、文件、生命周期等窄边界下的确定性编排语义 | 系统权限弹窗、Camera/Microphone 硬件行为、真实中断 |
| generic iOS SDK compile | 分别在各自 Package 目录编译 `MediaCapture`、`MediaCaptureAppleRendering`、`MediaCaptureUI`、`MediaCaptureBridgeCore` | iOS 13 API 基线、Package product 解析、UIKit/AVFoundation 接线、完整并发检查下没有告警 | 运行时图像帧、真实 Engine 注册、系统权限 |
| Simulator runtime | 有可用 iPhone Simulator 时运行 Core Package、UI 和 69 个 Bridge Core XCTest | 不要求真实 Camera 的 session/lease、render attachment、UI 三终态、ViewController/Engine 与 transfer 生命周期 | 真机 Camera、Microphone、性能或系统授权 UI |
| 临时 Flutter Host | 安全复制 Workspace，只在临时 `pubspec.yaml` 开启 SwiftPM，并执行 Debug no-codesign iOS build | Flutter 3.41.9 能生成 `FlutterGeneratedPluginSwiftPackage`，发现 Plugin，并解析 Flutter API、Bridge Core、Core/UI products | 真实 Demo Runner 已迁移或已提交 Host 配置 |
| 真实 Runner | 最终跨 Runtime Integration 修改并构建 `app/apps/demo/ios/` | 真实 Runner 的 SwiftPM 配置、Plugin 注册与 no-codesign Host 构建 | 真机系统能力，除非另有设备证据 |
| 真机 | 人工在受控设备执行拍摄、录像、权限和中断验收 | live frame、Camera/Microphone、系统授权 UI、硬件中断与设备性能 | 其他未测试机型或系统版本 |

无可用 iPhone Simulator 时，仅 Simulator runtime 层可以跳过。四个 generic Simulator SDK compile 和
临时 Flutter Host build 始终是强制项；Bridge Core 独立编译不能替代 Plugin Host，临时 Host 也不能替代
真实 Runner。

## 静态约束

门禁通过 `swift package dump-package` 对三个 Package 的 JSON 图执行精确检查，并递归解析生产 Swift
源码中的 import 声明。属性、访问级别和 scoped import 都必须进入白名单；无法识别的 import 形态失败
关闭：

- 在执行任何 Swift manifest 或 Host/Core helper 前，Gate 先校验三个 `Package.swift`、临时 Package
  模板和全部直接 helper 的已审查 SHA-256；摘要漂移先失败，不执行未审查 manifest。

- Core 不声明 Package dependency，也不 import Flutter。
- UI 只通过仓库相对路径依赖 Core 的 `MediaCapture` 与 `MediaCaptureAppleRendering` products。
- Bridge Core 只依赖 Core/UI，Flutter Plugin target 只负责 Flutter API 和 Bridge Core 注册边界。
- 三个 Package 都使用 Swift tools 5.9、iOS 13，不允许远程、分支、binary target 或本机绝对路径依赖。
- Package、product、target 及 target dependency 集合必须与批准图完全相等；额外本地 Package、Registry
  dependency、product 或 target dependency 同样会使门禁失败。
- 四个 generic compile 使用 `SWIFT_STRICT_CONCURRENCY=complete`；日志中若出现 Sendable、actor
  isolation、MainActor、data-race 等并发告警，门禁失败。SwiftPM 会对本地 dependency target 使用
  `-suppress-warnings`，因此 Gate 不全局注入与其冲突的 `SWIFT_TREAT_WARNINGS_AS_ERRORS`；每个 product
  仍在自己的 Package 目录单独编译，确保其自身诊断不会被依赖构建设置掩盖。

共享 Wire Contract 由 JSON 结构化读取。门禁验证 Wire V3 精确兼容 Capability V4、50 MiB 单文件、4 个
并发 transfer、100 MiB 聚合容量、300 秒 TTL、4096 项 tombstone，以及 18 个 URI 内容向量和 2 个 URI
长度向量与 Swift XCTest 完全一致。脚本不修改 Contract，也不允许用平台差异覆盖共享事实。

源码矩阵固定为 Core/Rendering 107、UI 52、Bridge Core 69，多或少一项都失败。Simulator runtime 使用
每次 `xcodebuild test` 生成的 `.xcresult` 结构化摘要，把源码矩阵与实际执行结果绑定：三个层级均要求
passed 等于精确 total，failed、skipped 和 expected failure 都为 0；Bridge Core helper 与主 Gate 会对
同一个 69 项 result bundle 分别执行结构化校验，不依赖日志正则。父 Gate 把已选定的 iPhone Simulator
传给 Bridge helper；若没有可解析的测试失败，helper 只重试一次，并在最终失败时输出脱敏的结果计数和
合法测试标识，不输出 Simulator ID、构建日志或本机路径。

## 临时 Host 安全边界

临时 Host 路线在执行前先运行复制策略夹具，验证 `.env*`、签名证书、私钥、Provisioning Profile、
钥匙串导出、本地配置、敏感 xcconfig，以及直接、绝对、目录和链式越界符号链接不会进入复制集。Host
build 使用权限 0700 的隔离 HOME、TMP、Pub/XDG cache 和 `env -i` 白名单环境，不继承 Token、签名变量
或用户 Flutter/Dart 配置；只接收已校验的 Flutter executable/root、系统 PATH、locale 和可选
`DEVELOPER_DIR`。脚本还会对真实 Demo iOS Host、Demo `pubspec.yaml` 和用户 `.flutter_settings` 做前后
内容摘要，任何变化都失败。成功和失败路径只输出固定门禁结论，不外显不可信 build log；入库证据继续
通过 evidence lint，不记录用户名、主机路径、Simulator ID、UUID、凭据或真实媒体。

Media Capture 的临时 Host 路线固定为 SwiftPM。若该路线失败，应回到已批准的 iOS Host 架构复审，不能
在门禁现场添加 CocoaPods fallback。

## 真机验收项

最终 Integration 完成真实 Runner SwiftPM 接线和 no-codesign build 后，以下项目由人工在真机确认；当前
专项 Gate 只证明临时 Host 路线，不把真实 Runner 标记为已集成：

1. Camera 首次/再次授权、拒绝、受限和设置变化的产品行为。
2. live preview 确实显示真实帧，前后摄像头切换与旋转后没有旧 generation 回写。
3. 照片、静音录像和带音频录像；仅带音频录像请求 Microphone 权限。
4. Home/前后台、来电或系统中断、Scene/页面销毁后的 session、layer、player、content 和临时文件释放。
5. 长按录制上限、固定 poster/thumbnail、预览确认/重拍/取消，以及连续多轮拍摄。
6. 目标设备上的启动延迟、录制稳定性、内存、温度和磁盘占用。

真机证据只记录系统版本、设备类型和结论，不记录设备 ID、账号、真实媒体、文件路径或其他敏感信息。
