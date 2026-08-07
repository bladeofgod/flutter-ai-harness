---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [integration]
blockedBy:
  - generate-media-capture-android-wire-codec
  - generate-media-capture-dart-wire-codec
  - generate-media-capture-ios-wire-codec
  - bound-test-evidence-retention
securityReview: required
---

# 集成 Media Capture 三端 Wire 生成链路

## 输入与事实来源

- `define-media-capture-wire-generation` 的唯一 Contract manifest和 generator。
- 已完成的 Dart、Android、iOS 生成迁移卡及各自测试/构建/Security Review 证据。
- Wire V3/Capability V4 当前共享 golden、历史 projection、双平台专项 gate和 CI。

## 目标

- 验收同一结构化 Contract 在 Dart/Kotlin/Swift 生成完全一致的协议表，并把全量 drift check 接入标准门禁。
- 用共享 golden vector 证明三端 request/result/event/error 的兼容性和现有安全拒绝语义不变。
- 汇总真实平台证据，更新 Bridge 文档为生成链路的完成状态。

## 非目标

- 不在集成卡重新实现或修正某一 Runtime；发现缺陷退回对应所有者。
- 不改变 Wire/Capability 版本、payload、错误、平台支持、Native 行为或业务 Feature。
- 不把三端编译成功误报为真机 Camera/权限验收。

## 集成要求

1. 新增统一只读 drift target，依次对 dart/android/ios 执行 generator `--check`；接入 `make check`、pre-push
   和 CI 的现有 check Job。生成 target 与 check target分离，门禁不得自动修复工作树。
2. Harness 验证 Contract generator manifest、source digest、三端输出位置/标记和无手工漂移；Fixture 覆盖
   修改生成文件、修改 Contract 未再生成、仅一端再生成、手工删除标记、输出符号链接和 renderer 缺失。
3. 建立一份共享、Runtime-neutral golden vector事实源，覆盖 17 methods、5 events、result/failure/error、
   required/unknown/nullable/type/range、signed-64、thumbnail bytes、canonical/malicious file URI、handle、
   redaction和历史 Wire projection。Dart/Kotlin/Swift 测试各自读取同一文件并验证 encode/decode结果。
4. 比较三端生成 descriptor 的规范化 digest和 coverage：标识/字段/约束必须一致；平台差异只允许现有
   main-thread/main-actor与私有 cache API，不能进入生成协议值。
5. 只读审计手写边界，确认 generator未拥有 Capability mapping、dispatch/lifecycle、presentation、transfer
   store、文件 cleanup、线程或日志；Channel callback仍由各平台 Adapter切回 UI 线程。
6. 运行 Dart Package、Android专项 gate、iOS专项 gate和双 Host Debug build，汇总实际通过/未验证平台；
   任一 Runtime drift、golden或编译失败时集成不通过。
7. 更新 `docs/bridge/README.md`、共享 Media Capture Bridge 文档及必要架构索引，记录生成命令、手写边界、
   drift门禁和三端证据，不复制 Contract 表。

## 写入所有权

- 共享 golden/vector 与跨 Runtime tests。
- `Makefile`、CI、pre-push、Harness Validator/Fixture中的最终 drift 接线。
- Bridge 共享文档/索引和本任务 Review/evidence。

不得改写 Dart/Android/iOS 生产实现来现场修复失败，也不得修改 Native Module或业务 Feature。

## 验收与验证

```bash
make media-capture-wire-check
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh test
bash scripts/quality/media-capture-android.sh
bash scripts/quality/media-capture-ios.sh
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
make harness-check
make harness-test
make check
git diff --check
```

## 环境限制

最终完成需要 Android SDK/JDK 和 macOS/Xcode；某一平台环境缺失时只能报告集成未完成，不能由另一平台或
生成文本比较替代。真机 Camera/权限不是行为保持型生成迁移的新增门禁，但现有人工缺口继续保留。
