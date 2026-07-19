---
name: flutter-android-install
description: "适用：解析 Flutter 依赖、构建 Android APK/AAB、安装到已连接设备，或排查 SDK/Flavor/Plugin 构建失败。不适用：iOS 打包。触发词：flutter build apk、appbundle、adb install、Android device、Gradle、flavor。"
paths: ["app/.fvmrc", "app/pubspec.yaml", "app/apps/**/android/**", "app/apps/**/pubspec.yaml"]
---

# Flutter Android 构建与安装

在可运行 App 目录执行，并优先使用仓库锁定的 Flutter SDK。

```bash
fvm flutter --version
fvm flutter pub get
fvm flutter devices
fvm flutter build apk --debug
adb -s <device-id> install -r <apk-path>
```

只有 App 明确定义 Flavor 和 `--dart-define` 时才附加对应参数。

## 排障顺序

1. 确认当前目录和 `pubspec.yaml`。
2. 确认锁定的 Flutter/Dart 版本。
3. 确认依赖解析。
4. 确认 Android SDK、JDK、Gradle 兼容性。
5. 确认 Flavor、Application ID、Manifest、权限和 Plugin 注册。
6. 确认目标设备和安装产物路径。

Android 源码或配置变化后必须构建受影响 Variant。汇报命令、产物路径、设备 ID 和未验证的 Release/签名行为。禁止提交签名材料或 `local.properties`。
