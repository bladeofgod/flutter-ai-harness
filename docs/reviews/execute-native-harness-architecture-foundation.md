---
task: native-harness-architecture-foundation
status: passed
p0: 0
p1: 0
---

# Review：原生 Harness 架构基础

## P0

无。

## P1

### 1. iOS Bridge Adapter 到本地 Native Module 的两种接线位置均不可按当前文档直接执行

- 文件行号：[`docs/native-architecture.md:150`](../native-architecture.md#L150)
- 影响：首个 iOS Bridge 任务按文档实现时，Swift Package Manager 路线不会被锁定的 Flutter 3.35.7 识别，CocoaPods 路线也无法仅在 Plugin `.podspec` 中声明版本库内的本地 Package 路径；因此文档虽然画出了依赖图，却没有满足任务要求的可执行依赖声明位置，后续实现者只能临时猜测或把接线补回 Host。
- 证据：文档把 Swift Package Plugin 的 `Package.swift` 写成 `app/packages/app_<capability>_bridge/ios/` 目录下的文件，但 Flutter 3.35.7 的插件发现逻辑要求路径为 `ios/<plugin-name>/Package.swift`。同一段又称 CocoaPods 路线把“版本库内可复现的本地依赖”写入 Plugin `.podspec`；对当前 CocoaPods DSL 的只读探测 `spec.dependency("NativeModule", :path => "../NativeModule")` 明确失败并提示 Podspec 不支持 `:path`，本地来源只能在 Podfile 中覆盖。当前 Host 确实使用 [`app/apps/demo/ios/Podfile:30`](../../app/apps/demo/ios/Podfile#L30)，其中没有文档所需的本地 Pod 接线约定。
- 修法：明确记录至少一条当前工具链可执行的完整路径。SwiftPM 路线应写明 Flutter Plugin manifest 位于 `ios/app_<capability>_bridge/Package.swift`，由该 manifest 声明本地 Native Package；CocoaPods 路线应写明 Native Module 需要可解析的 podspec、Plugin podspec 只声明名称依赖，并由最终 Host Podfile 用仓库相对 `:path` 提供本地来源。仍可把最终选型留给首个真实模块，但不能把无效的声明位置当作候选方案。

### 2. Native 文档门禁用全局字符串和路径存在性近似语义，导致误报、漏报且缺少任务要求的入口回归覆盖

- 文件行号：[`app/tool/harness_check.dart:704`](../../app/tool/harness_check.dart#L704)、[`scripts/quality/test-harness.sh:246`](../../scripts/quality/test-harness.sh#L246)
- 影响：Harness 不能保证“当前只有 Host、Native Module/Bridge Package 尚未实现”这一核心事实；同时，合法的未来路径示例、迁移说明或对禁用术语的引用会被错误阻断。四个入口中的三个也没有缺失链接负向 Fixture，后续误删对应 checker 条目时 `make harness-test` 仍会通过。
- 证据：checker 要求的 marker 列表没有包含 fixture 第 107 行或生产文档第 5-8 行的当前状态声明，删除该声明仍满足全部检查；相反，第 731-739 行只要发现反引号中的不存在具体路径就报错，不判断上下文是否明确写着“计划、尚未实现”，且不带路径的虚构实现声明会漏过。第 724 行对 `Flutter Bridge Adapter` 的全局禁用也会拒绝解释该旧术语为何被弃用的合法文本。链接方面，checker 虽遍历四个源文件，但 fixture 仅在第 253-258 行删除 `CLAUDE.md` 链接，没有分别删除 `docs/architecture.md`、`docs/infrastructure-modules.md` 和 `docs/bridge/README.md` 验证失败；它也只验证 CLAUDE 任意位置存在链接，没有验证任务指定的“重要参考”入口。
- 修法：不要从任意 prose 推断实现状态。为当前 Host、已实现 Native Module 和 Bridge Package 定义小型结构化状态块或稳定字段，checker 只解析该结构；依赖关系也应检查结构化图/表字段或宽松、行级的关系解析，允许说明性文本。为四个入口分别增加删除链接的负向 Fixture，并对 `CLAUDE.md` 的“重要参考”区段做定向检查；保留现有通用 Markdown 失效链接回归用例。

## P2

无。

## 已确认项

- [`docs/native-architecture.md:3`](../native-architecture.md#L3) 准确区分现有 Android/iOS Host 与未来 Native Module/Bridge Package；现有 `MainActivity` 为空壳 `FlutterActivity`，`AppDelegate` 只调用生成插件注册入口。
- Dart Client、Android/iOS Bridge Adapter、Host、Native Module 和 Native Consumer 的职责与单向依赖符合任务卡，未替项目预先划分模块业务归属。
- Android 技术方向、生命周期、线程、错误、取消、权限、文件、平台差异、依赖治理和测试层级均在任务范围内，未创建业务模块或引入依赖。
- Markdown 链接提取重构保持了原有 inline-link 行为；本轮未发现该重构对现有链接校验的直接回归。

## 验证

读取的既有证据 [`native-harness-architecture-foundation.log`](test-evidence/native-harness-architecture-foundation.log) 记录以下命令均为退出码 0，且与当前 diff 不矛盾，因此未重复运行：

- `make harness-check`
- `make harness-test`
- `git diff --check`

额外只读核对了当前 Android/iOS Host 源码、Gradle/CocoaPods 配置、Flutter 3.35.7 插件发现逻辑，并对 CocoaPods Podspec 本地 path 依赖 DSL 做了无文件写入探测。

## 结论

当前 Review 不通过。需修复以上 2 个 P1 后复审；没有 P0 或可延后的 P2。

## 修复复审

### 结论

原 P1-1 已解决。原 P1-2 中实现状态误报/漏报、脆弱 prose 绑定、四入口负例和
`CLAUDE.md`“重要参考”区段检查均已解决，但结构化依赖图仍存在 1 个阻断漏报。
当前结论为 `failed`、P0 0、P1 1。

### 已解决问题

- **原 P1-1 iOS 构建接线：已解决。** [`docs/native-architecture.md:202`](../native-architecture.md#L202)
  现在准确声明 Flutter 3.35.7 要求的
  `ios/app_<capability>_bridge/Package.swift`，且相对 Native Package 路径可从该目录解析到
  `app/native/ios/<Module>`。CocoaPods 路线把本地来源放在最终 Host Podfile 的仓库相对
  `:path`，Plugin podspec 只保留 `s.dependency` 名称依赖，符合当前 CocoaPods DSL。
- **原 P1-2 状态、prose 与入口检查：部分已解决。** [`docs/native-architecture.md:10`](../native-architecture.md#L10)
  将 JSON 块定义为 Harness 的唯一状态输入后，正文可以合法说明未来路径或弃用术语；
  `nativeModules`、`bridgePackages` 与真实目录绑定，消除了原不存在路径启发式的误报。
  [`scripts/quality/test-harness.sh:292`](../../scripts/quality/test-harness.sh#L292) 已分别覆盖
  `CLAUDE.md` 重要参考和其余三个入口的缺失负例。

### 当前未解决 P1

#### 1. `dependencyEdges` 只检查必需边存在，仍会接受与架构正文冲突的反向依赖

- 文件行号：[`app/tool/harness_check.dart:750`](../../app/tool/harness_check.dart#L750)、
  [`app/tool/harness_check.dart:985`](../../app/tool/harness_check.dart#L985)
- 影响：结构化块被声明为依赖边的唯一 Harness 输入，但加入
  `dart_client -> android_native_module`、`native_module -> android_bridge_adapter` 等反向边后
  `make harness-check` 仍可通过；这会让机器门禁接受 Dart Client 直连原生 Module 或 Native
  Module 反向依赖 Bridge Adapter，与本任务最核心的单向依赖契约冲突。
- 证据：第 750-766 行仅遍历 `requiredDependencies` 查缺失项，第 775-780 行只拒绝
  `native_module->flutter` 这一条精确边；`_nativeDependencyEdges` 对任意非空 `from`/`to`
  都加入集合且不验证节点或额外边。Fixture 只删除一条必需边和一条禁止边，没有追加反向边
  并断言失败。
- 修法：把 `dependencyEdges` 与当前允许边集合做精确比较，至少拒绝
  `dependencies.difference(requiredDependencies)`；同样限定禁止边集合或定义显式可扩展节点与
  allowed-edge schema。增加追加 `dart_client -> android_native_module`（或等价反向边）的失败
  Fixture，证明结构化契约不能同时表达互相矛盾的依赖方向。

### 复审验证

- 更新后的证据记录修复后 `make harness-check`、`make harness-test`、`git diff --check` 均为
  退出码 0；输出与当前 diff 一致。
- 本轮重新完整读取 `docs/native-architecture.md`、`app/tool/harness_check.dart`、
  `scripts/quality/test-harness.sh`、当前完整 diff 和测试证据，并额外执行
  `git diff --check`，退出码为 0。
- 未发现新的 P0、P2、范围扩张或链接解析回归。

## 第二轮修复复审

### 结论

上一轮剩余 P1 已解决。当前 Review 通过，P0 0、P1 0；未发现新问题。

### 已解决问题

- **依赖边额外项漏报：已解决。** [`app/tool/harness_check.dart:750`](../../app/tool/harness_check.dart#L750)
  在检查必需边后，checker 现在拒绝
  `dependencies.difference(requiredDependencies)` 中的每一条额外边；
  `forbiddenDependencyEdges` 同样与唯一声明的禁止边集合做缺失和额外项双向检查。因此
  `dart_client -> android_native_module`、`native_module -> android_bridge_adapter` 或其他未声明
  方向均不能与有效关系同时混入结构化契约。
- [`scripts/quality/test-harness.sh:374`](../../scripts/quality/test-harness.sh#L374) 新增额外
  Dart Client 到 Native Module 边的失败 Fixture；第 394 行新增额外禁止边的失败 Fixture。
  两个用例都在恢复基线契约后继续执行，未污染后续 Harness 用例。

### 复审验证

- 更新证据记录本轮修复后的 `make harness-check`、`make harness-test`、`git diff --check`
  均为退出码 0。
- 本轮重新读取依赖边精确集合校验、两个新增负向 Fixture、相关完整 diff 与更新证据；证据与
  当前实现一致，无需重复运行。
- 精确集合校验仍保留缺失边、重复边、非法 JSON 与禁止边出现在允许集合中的既有诊断；未发现
  新的严重问题或范围扩张。
