---
executor: bridge-engineer
platforms: [flutter, android, ios]
workKinds: [bridge-contract]
blockedBy: []
securityReview: required
---

# 定义 Media Capture Wire 代码生成规则

## 输入与事实来源

- `docs/tasks/done/project-review-optimization-planning.md` 第 6 项已确认方向。
- `docs/bridge/contracts/media-capture.wire.json`、`wire.schema.json` 和 `docs/bridge/media-capture.md` 的 Wire V3
  事实源。
- Dart `media_capture_constants.dart`、models/codec，Android `MediaCaptureWireCodec.kt` 和 iOS
  `MediaCaptureWireCodec.swift` 当前重复维护的 channel、method/event/result/error、字段和范围表。
- `docs/native-architecture.md`：Wire Contract 不反向定义 Native Module，Bridge Adapter 不拥有 Capability。

## 目标

- 在结构化 Wire Contract 中明确哪些稳定标识、闭合枚举、payload 字段表、范围约束和基础 envelope/field
  codec 可以确定生成。
- 实现一个确定性、可按 Runtime 单独生成和 `--check` 的仓库工具，后续 Dart/Android/iOS 卡只生成并消费
  各自文件。
- 保持 Wire V3、Capability V4、Channel payload 和全部公开行为不变。

## 非目标

- 本卡不迁移 Dart Client、Android Adapter 或 iOS Adapter，不提交三端生产生成文件。
- 不生成 Native Capability API、平台生命周期、线程切换、资源 ownership、transfer store、presentation、
  日志或 Framework 调用。
- 不引入 Proto/Pigeon 作为 MethodChannel payload，不生成自由 `Map` 公共 API，不提升 Wire 版本。
- 不根据三端现有代码反向改写 Contract 以保留偶然漂移。
- 不修改根 `pubspec.yaml` 或 lockfile；生成器和自测只使用现有 Dart SDK/根工具依赖。

## 结构化生成边界

1. 在 Wire Schema/Profile 增加闭合 `codeGeneration` 描述，逐项引用现有 contract ID，而不是复制第二份值。
   至少覆盖：wire version、channel name、method/event/result/failure type、error code及属性、error detail enum、
   payload ID、required/nullable 字段、wire key、基础类型、signed-64/finite/range/length/format和 unknown-key policy。
2. 明确不可生成清单：Capability model/mapping、method dispatch、异步完成机、listener/owner generation、UI
   thread/main actor、late cleanup、lease/transfer ownership、文件/URI系统调用和 Native SDK 行为。生成 manifest
   引用这些 contract 段仅用于 coverage，不得输出可执行平台行为。
3. 基础 codec 只生成闭合 descriptor 和无副作用的 envelope/field primitive；复杂跨字段条件、Native model
   映射和生命周期编排继续由各 Runtime 手写，并必须调用生成的边界而不是复制常量表。
4. Contract 继续是唯一协议事实源；生成文件带稳定 generator/version/source digest 和“禁止手工编辑”标记。
   输出内容不得包含时间戳、绝对路径、主机信息或非确定顺序。

## 生成工具要求

1. 新增聚焦 Dart generator，使用结构化 JSON 解析和现有 Wire Schema 验证结果，支持
   `--runtime dart|android|ios`、`--output <path>`、`--check` 和测试用 `--root`；每次只允许写目标 Runtime 的
   已登记普通文件。
2. 写入前校验仓库内真实路径、非符号链接父目录、Contract/schema digest和完整输入；先在临时文件生成并
   比较，原子替换，失败不留下部分输出。`--check` 绝不写文件。
3. Runtime renderer 必须有相同的规范化中间模型和稳定排序；Dart/Kotlin/Swift 名称映射显式记录并拒绝
   collision、保留字、重复 wire 值、未知 contract ID 和无法表达的类型。
4. 单元/Golden 测试在临时输出目录生成三端结果，覆盖确定性、CRLF、路径带空格、符号链接逃逸、非法
   manifest、名称 collision、部分写入失败和无关 Contract 段变化不产生输出漂移。
5. 增加按 Runtime 的生成命令入口；全仓 drift check 只在三端迁移完成后的最终集成卡接入 `make check`，
   避免本卡要求尚不存在的生产输出。

## 写入所有权

- `docs/bridge/contracts/media-capture.wire.json`、必要的 `wire.schema.json` 和 Bridge 生成规则文档。
- `app/tool/` 下的生成器、规范化中间模型与根工具测试。
- 必要的生成命令/Fixture；不得修改 `app/packages/app_media_capture_bridge/lib/**`、`android/**`、`ios/**`
  或 Native Module。

## 验收与验证

- 当前 Contract 经新 Schema 验证，Wire V3 语义 digest 和历史 projection 不变。
- 三种临时输出可重复生成且 byte-for-byte 相同；生成内容仅包含批准边界。
- Security Review 确认外部 Contract 输入、路径写入、代码注入/escaping 和生成能力没有扩大到 Native 行为。

```bash
make format
make analyze
make harness-check
make harness-test
cd app && dart test test/media_capture_wire_generator_test.dart
git diff --check
```

## 环境限制

纯 Contract/工具任务不需要 Android SDK 或 Xcode，也不能证明生成文件可由三端编译。Runtime 卡分别拥有
真实输出和编译证据；发现 Contract 无法无损表达现有协议时必须回到本卡修订，不能在 renderer 内硬编码。
