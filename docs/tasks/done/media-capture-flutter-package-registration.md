---
executor: task-executor
platforms: [flutter]
workKinds: [integration]
blockedBy:
  - media-capture-dart-client
securityReview: required
---

# 登记 Media Capture Flutter Package 与 Demo 依赖

## 输入与事实来源

- 已归档的 `media-capture-dart-client` 及其 plugin metadata。
- `docs/architecture.md`、`docs/native-architecture.md` 和当前 Workspace 依赖矩阵。
- 用户决定先完成 Android 接入与真机验证，iOS Host 和最终跨 Runtime 汇总后置。

## 目标

- 将 `app_media_capture_bridge` 正式登记到 Dart Workspace 和依赖矩阵。
- 让 Demo App 显式依赖该 Flutter Plugin，使 Android Host 可以通过标准 Flutter plugin loader 注册
  Adapter；本任务不实现任何平台 Host 或业务页面。

## 非目标

- 不修改 Android/iOS Adapter、Native Module、Host、权限、订单评价 Feature、Wire/Capability 或 CI。
- 不实现业务 Media API，也不通过 Dart 代码手工注册平台 Plugin。

## 实现路径与所有权

本任务只写：

- `app/pubspec.yaml`
- `app/pubspec.lock`（只接受 Flutter 工具解析 Workspace 后生成的更新）
- `app/apps/demo/pubspec.yaml`
- `app/packages/app_media_capture_bridge/pubspec.yaml`（只增加 Workspace resolution 声明）
- `app/tool/check_package_dependencies.dart`、`app/tool/check_flutter_plugin_discovery.dart` 及其 Fixture
- `scripts/lint/repository-boundaries.sh`
- `CLAUDE.md`、`docs/architecture.md` 与中英文 HTML 详细指南中的真实依赖说明
- 本任务测试、Review 和 evidence

## 实现要求

1. 将 `packages/app_media_capture_bridge` 加入 Workspace；Package 继续保持不依赖其它 Workspace
   Package，并声明 `resolution: workspace`。
2. `demo_app` 显式依赖 `app_media_capture_bridge` 以触发标准 plugin discovery；不得在 Dart 壳代码中
   直接调用 Client 或手工注册 Plugin。
3. 依赖矩阵允许 `app_features` 在后置订单评价任务中依赖聚焦 Dart Client，并允许 `demo_app` 依赖该
   Plugin；不得放宽其它 Package 的依赖方向。
4. 依赖检查 Fixture 必须同时覆盖合法依赖和越权反向依赖。
5. `make lint` 必须结构化解析 Demo 的 `.flutter-plugins-dependencies`，确认 Android
   `app_media_capture_bridge` 唯一存在、属于 production native build、指向仓库内预期 Package，且进入
   dependency graph；从可信 Workspace 根到 Package 的路径组件不得是符号链接，且不得输出生成文件中的
   绝对路径。
6. 不手工编辑 lockfile；使用仓库 Flutter 工具解析 Workspace。

## 测试与验收

- Workspace `pub get` 成功且依赖图能发现 `app_media_capture_bridge`。
- 依赖矩阵检查允许既定 Consumer，仍拒绝 Core/Data/UI 等反向依赖。
- Demo App 没有新增直接 Client 调用或平台注册代码。

## 验证命令

```bash
TOOL_WORKDIR=app bash scripts/flutter-tool.sh pub get
bash scripts/dart-tool.sh run tool/check_flutter_plugin_discovery.dart \
  --input apps/demo/.flutter-plugins-dependencies \
  --workspace-root .
bash scripts/lint/test-repository-boundaries.sh
make analyze
make lint
make harness-check
git diff --check
```

## 环境限制

本任务只证明 Dart Workspace 和 plugin discovery 输入成立，不证明 Android/iOS Host 构建、Plugin 注册结果
或 Camera 行为。
