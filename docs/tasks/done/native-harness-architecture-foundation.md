---
executor: task-executor
blockedBy: []
---

# 建立原生 Harness 架构契约

## 背景

当前仓库已经把 Android、iOS 声明为一等支持平台，并提供 Bridge 规则、宿主构建 Job 和 `bridge-engineer`，但原生治理仍主要停留在宿主存在性与 MethodChannel/EventChannel 流程约束。仓库尚未定义可被纯原生业务与 Flutter Bridge 同时复用的 Native Module 布局、依赖方向、技术栈、生命周期和测试边界。

本任务先建立通用原生架构事实源，不实现 Media Capture 或其他业务能力，也不由 Harness 判断一个模块属于业务还是基础设施。

## 输入与事实来源

- `CLAUDE.md`
- `docs/architecture.md`
- `docs/infrastructure-modules.md`
- `docs/bridge/README.md`
- `.claude/agents/bridge-engineer.md`
- `app/apps/demo/android/`
- `app/apps/demo/ios/`
- 当前讨论确认的依赖原则：Native Consumer 直接依赖 Native Module；Flutter Consumer 通过 Dart Client 和对应平台 Bridge Adapter 委托同一 Native Module；Native Module 不反向依赖 Flutter。

## 目标

- 新增可由 Claude/Codex 确定性发现的原生架构文档。
- 定义 Host、Native Module、Dart Client、Android/iOS Bridge Adapter 的职责与单向依赖。
- 定义 Android/iOS 技术栈、模块布局、公共 API、生命周期、线程、依赖和验证原则。
- 明确模块分类、粒度和业务归属由项目决定，Harness 只约束已声明边界。
- 为后续 Media Capture、平台 Agent、编码规范和原生门禁提供唯一架构依据。

## 非目标

- 不创建 Android/iOS 业务模块、空 Native Core 或 Flutter Plugin。
- 不增加 CameraX、AVFoundation Adapter、Compose、SwiftUI 或测试依赖。
- 不定义 Media Capture 的 Wire method、event、Payload 或 UI。
- 不修改现有 Flutter Package 的业务依赖。
- 不引入新的任务 Executor 值。

## 具体要求

1. 新增 `docs/native-architecture.md`，至少包含目标与非目标、术语、模块类型、依赖方向、目录约定、Host 装配、Bridge 边界、生命周期与线程、错误与取消、文件与权限、平台差异、依赖治理、测试层级和任务所有权。
2. 原生模块的通用代码根目录采用 `app/native/android/<module>/` 与 `app/native/ios/<Module>/`。跨 Runtime 代码使用聚焦的 Flutter Plugin Package，例如 `app/packages/app_<capability>_bridge/`：`lib/` 只包含 Dart Client、Wire Model 与 Channel 调用，`android/`、`ios/` 分别包含平台 Bridge Adapter 和注册入口；不得建立万能 `app_native` Package。
3. 文档必须明确以下依赖方向：
   - Android 原生消费者直接依赖 Android Native Module。
   - iOS 原生消费者直接依赖 iOS Native Module。
   - Flutter Consumer 只依赖 Dart Client；Dart Client 只拥有 Wire Model 和 Channel 调用，不直接依赖 Kotlin/Swift Module。
   - Android/iOS Bridge Adapter 分别依赖对应 Native Module，在边界完成 Wire DTO 与 Native Model 映射。
   - Native Module 不 import Flutter 类型，不通过 Channel 调用自身能力。
4. Host 只负责进程入口、平台生命周期接入、Native Module 装配和 Bridge Adapter 注册；业务状态机、资源生命周期和协议映射不得堆积在 `MainActivity`、`AppDelegate` 或 Runner 中。
5. 不使用“原生 Feature 是一等模块”等会替项目划分业务归属的措辞。改为约束模块公共 API、内部实现、依赖方向、生命周期和验证方式必须可声明、可审查。
6. Android 默认技术方向记录为 Kotlin、Gradle Kotlin DSL、结构化并发与 Flow、AndroidX；具体 UI/System API 依真实模块决定。iOS 默认技术方向记录为 Swift、Swift Concurrency、本地 Swift Package 与 Apple Framework；Flutter Plugin 依赖仍可由 CocoaPods 管理。原生架构文档必须给出 Native Module、平台 Bridge Adapter 与 Host 的构建图及依赖声明位置，首个真实模块再按锁定工具链验证具体版本和接线方式，不得把协议映射退回 Host。
7. `CLAUDE.md` 的重要参考增加 `docs/native-architecture.md`，并在架构不变量中只保留短小的全局原生边界。
8. `docs/architecture.md` 增加 Flutter Workspace 与 Native Module/Bridge Adapter 的跨运行时总览和详情链接，不复制原生文档正文。
9. `docs/infrastructure-modules.md` 顶部说明原生基础能力同样通过本索引发现，并统一遵守 `docs/native-architecture.md`；是否进入基础模块索引仍由真实复用需求决定。
10. `docs/bridge/README.md` 链接原生架构文档，并明确 Bridge 只定义跨 Runtime Adapter，不拥有被委托的 Native Capability。
11. 保持 `AGENTS.md` 为生成式薄入口；不得手工添加对新文档的重复指令。

## 同时编写的测试

- 扩展 Harness 文档链接 Fixture，验证 `CLAUDE.md`、`docs/architecture.md`、`docs/infrastructure-modules.md` 和 `docs/bridge/README.md` 的新增引用存在且不会失效。
- 验证删除 `docs/native-architecture.md` 或移除 `CLAUDE.md` 的重要参考时，`make harness-check` 失败。
- 验证文档没有把 `app/packages/app_media_capture_bridge` 或尚未创建的 Native Module 误写成已经实现。
- 验证术语和依赖图能区分 Dart Client、Android Bridge Adapter、iOS Bridge Adapter、Native Module 与 Host，不再使用含义不明的单一“Flutter Bridge Adapter”。

## 验收标准

- Claude/Codex 从项目入口可以确定性路由到原生架构文档。
- 架构图清楚表达 Native Consumer 不经过 Flutter 即可复用 Native Module。
- Dart Client、两端 Bridge Adapter 与 Host 的职责和构建关系明确，Native Module 不依赖 Flutter。
- 模块分类与业务归属保留给项目开发者决定。
- 文档区分已经存在的宿主事实与未来模块约定，不预置虚构实现历史。
- `make harness-check`、`make harness-test` 和 `git diff --check` 通过。

## 验证命令

```bash
make harness-check
make harness-test
git diff --check
```

## 平台或环境限制

本任务只修改架构契约、文档索引和确定性文档门禁，不需要 Android SDK、Xcode、设备、Figma MCP 或 Marionette。

## 待决事项

- Android/iOS 最低系统版本和 formatter/linter 具体工具版本由后续首个真实 Native Module 结合当前锁定工具链确定，本任务不得凭空锁定。
- 是否在第二个真实消费者出现后抽取跨 Native Module 的共享 Core，留给实际依赖关系决定。

## 执行结果

- [实现 Review](../../reviews/execute-native-harness-architecture-foundation.md)
- [测试证据](../../reviews/test-evidence/native-harness-architecture-foundation.log)
