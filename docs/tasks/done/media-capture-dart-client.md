---
executor: task-executor
platforms: [flutter]
workKinds: [dart-client]
blockedBy:
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 实现 Media Capture Dart Client

## 输入与事实来源

- 最新 `docs/bridge/contracts/media-capture.wire.json` 与 Wire Schema/详情文档。
- `docs/native-architecture.md`、`dart-coding-standards`、`testing-strategy`。
- 当前 Flutter 3.35.7 / Dart 3.9 Workspace 约定。

## 目标

- 先建立聚焦的 `app_media_capture_bridge` Package 共享 Dart/pubspec 基础。
- 实现类型化 Dart Client、Wire models/codec、MethodChannel/EventChannel 调用、全屏 flow API、缩略图
  API、稳定错误和资源释放；所有 Native 回包按不可信输入解析。
- 为 Android/iOS Adapter 提供同一组固定 Channel 名、method/event、envelope 和 plugin metadata。

## 非目标

- 不实现 Android/iOS Adapter、Native Core/UI、Host 注册、权限或 Shoppe 页面。
- 不修改 Capability/Wire Contract，不接受未知字段、自由 Map、路径/URI 或原始媒体 bytes。
- 不修改 Host、Feature Registry、共享契约文档、root Validator、CI 或 Makefile。

## 实现路径与所有权

本任务独占：

- `app/packages/app_media_capture_bridge/pubspec.yaml`
- `app/packages/app_media_capture_bridge/lib/**`
- `app/packages/app_media_capture_bridge/test/**`（不含跨 Runtime 最终 contract tests）
- 必要的 Package 内分析配置/README

不得创建或修改该 Package 的 `android/**`、`ios/**`。为避免并行共享写入，本任务先把 Package 保持为
可独立解析/测试的聚焦 package；`app/pubspec.yaml` Workspace 登记、根依赖矩阵、Demo/Host consumer
接线由最终 Integration 单独完成。本任务的 pubspec 仍须预先固定两端 plugin metadata/entry contract，
平台任务只能实现约定入口，不能重写共享 pubspec。

## 实现要求

1. 为最新 Wire 的 request/result/event/failure、配置、terminal outcome、confirmed media、bounded
   thumbnail 和错误定义不可变类型；业务调用方不接触裸 `dynamic`/Map/PlatformException。
2. Codec 对 envelope/payload 做闭合集合校验：版本、required/unknown key、类型、nullable、enum、finite、
   signed-64、handle/requestId 长度、缩略图尺寸/byte length/content type 与跨字段条件全部验证。
3. 入站 Native 数据一律不可信；Malformed result/event/thumbnail 归一为稳定 Dart failure，并保持原
   StackTrace/诊断上下文但不回显 payload、handle、requestId、bytes 或底层异常。
4. requestId 使用安全、不可预测且符合 Wire pattern 的实现；pending/completed、exactly-once、listener
   单订阅/generation、cancel/dispose、late event 和 Engine error 行为与 Wire 一致。
5. `presentCaptureFlow` 只暴露 confirmed/cancelled/typed failure 的闭合终态；用户取消不是异常。
   `readMediaThumbnail` 只返回已验证的 bounded sanitized bytes model，不提供 path/URI/file API。
6. Dart Client 拥有 Stream/Channel subscription 生命周期并可重复 dispose/release；不在 Controller 内
   使用服务定位器，不缓存超出租约需要的敏感 thumbnail bytes。

## 测试与验收

- 使用 mock MethodChannel/EventChannel 覆盖所有 method/event、三终态、版本、错误、重复、dispose、
  listener generation、late callback、thumbnail 和 release。
- 表驱动恶意/畸形 payload 覆盖 unknown/missing/type/non-finite/overflow/超长 handle/超限 bytes、
  resultType mismatch 与错误 details redaction；测试 teardown 清空所有 Channel handler/subscription。
- 公共 API 不暴露 Map、PlatformException、path/URI 或 Native SDK 类型。
- Package 可在尚未 Host 注册时独立 analyze/test；平台运行留给 Adapter/Integration。

## 验证命令

```bash
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh pub get
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh analyze --fatal-infos
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh test
make format
make harness-check
git diff --check
```

## 环境限制

不需要 Android SDK、Xcode、设备或已注册 plugin。Mock Channel 只能证明 Dart codec/client；不能证明
平台线程、presentation、Camera 或 Host lifecycle。
