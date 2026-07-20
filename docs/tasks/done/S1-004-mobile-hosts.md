---
executor: task-executor
blockedBy: []
uiSpec: not-required
---

# S1-004 建立 Android/iOS 中立宿主

## 背景

Demo 已有 Flutter 入口和 Marionette Binding，但缺少 Android/iOS 平台宿主，无法运行或构建移动端 App。

## 输入与事实来源

- `docs/reviews/harness-baseline.md` P1-4
- Flutter 3.35.7 标准 App 模板
- `flutter-android-install` Skill
- `marionette-debug` Skill

## 目标

使用锁定 Flutter 版本生成中立 Android/iOS 宿主，并验证两个平台的 Debug 构建入口。

## 非目标

- 不接入签名、推送、生产权限或第三方原生 SDK。
- 不增加产品 UI。
- 不把 Marionette 当作原生系统界面自动化工具。

## 具体要求

- 只生成 Android/iOS，不加入其他平台。
- 使用 `com.example` 可替换标识，并在文档中说明发布前替换。
- 保留现有 Dart 入口、Workspace pubspec 和测试。
- 不提交 `local.properties`、Pods、签名材料或构建产物。
- 文档给出从 Demo 目录启动的准确命令。

## 同时编写的测试

- 现有 Widget 测试继续通过。
- Android Debug APK 构建。
- iOS Debug no-codesign 构建；环境限制必须准确记录。

## 验收标准

- Flutter 正确识别 Android/iOS App。
- Android/iOS 不再因“未配置平台宿主”失败。
- Marionette 仍只在项目约定的 Debug 路径初始化。

## 验证命令

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
make test
```

## 风险与待决问题

本地可能缺少 Android SDK、JDK、Xcode 或 CocoaPods；这类失败不通过修改模板绕过。
