---
name: flutter-app-size
description: "适用：测量或降低 Android/iOS 包体，分析依赖与 Asset，检查应用商店下载限制。不适用：运行时内存或性能分析。触发词：app size、APK、AAB、IPA、analyze-size、DevTools size、资源压缩、依赖膨胀。"
paths: ["app/**/pubspec.yaml", "app/**/assets/**", "app/apps/**/android/**", "app/apps/**/ios/**"]
---

# Flutter 包体

1. 为目标平台生成 Release/Profile 产物和 Size Analysis。
2. 记录基线产物体积、架构、Flavor、Symbol 和构建参数。
3. 依次检查依赖、Asset、生成/原生二进制、Dart 代码。
4. 优先删除未使用依赖，再做代码级微优化。
5. 审计跨包重复资源，删除前检查原生引用。
6. 选择合适 Raster/Vector 格式和尺寸，保留 Icon、启动资源和来源信息。
7. Release 拆分 Debug Symbol 时必须有 Symbol 保存/上传流程。
8. 使用完全相同参数重新构建，报告实测收益。

不得比较不同构建模式或架构。删除平台二进制前必须构建并验证该平台。
