# S1-004 Review：建立 Android/iOS 中立宿主

## 结论

P0/P1/P2 均为 0，任务通过；iOS 构建保留一项明确的本机环境验证缺口。

## 审查结果

- 平台目录由锁定的 Flutter 3.35.7 生成，仅包含 Android/iOS。
- 现有 `main.dart`、Workspace pubspec 和 Widget 测试未被生成器覆盖。
- 删除了重复 Demo README、重复 analysis 配置和无效默认测试。
- 清除了生成器自动写入的本机 iOS Development Team；扫描未发现本机用户路径或签名身份。
- Android 使用 `com.example.demo_app`，iOS 使用 `com.example.demoApp`，文档明确要求发布前替换。
- Demo 增加 `version: 0.1.0+1`，消除移动端版本字段缺失。
- Marionette 能力边界明确为 Flutter Widget Tree，不冒充系统原生界面自动化。

## 验证

完整输出见 `docs/reviews/test-evidence/S1-004-mobile-hosts.log`：

- Android `flutter build apk --debug`：最终通过，产出 `app-debug.apk`。
- `make test`：2 个 Widget 测试通过。
- iOS `flutter build ios --debug --no-codesign`：宿主被识别并进入 Xcode Build；本机 Xcode destination 将 iOS 26.5 Platform 判定为未安装，因此未完成编译验证。
- `xcodebuild -version && xcodebuild -showsdks`：Xcode 26.5，命令行可列出 iOS 26.5 SDK；Platform/destination 状态仍需在 Xcode Components 中修复。
- evidence lint：通过。

## 剩余风险

- iOS 工程尚未在可用的 iOS destination 环境完成 no-codesign 构建。
- Release 签名、真实 Application ID/Bundle ID 和商店配置按任务非目标保留为空或占位。
- 尚未启动真机/模拟器连接 Marionette；该运行态验证需要可用设备和用户批准 MCP。
