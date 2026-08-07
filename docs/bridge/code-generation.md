# Bridge Wire 代码生成

Bridge Wire 生成器只把结构化 Contract 中可机械复制的传输边界变成 Runtime 内部代码。Contract
仍是唯一协议事实源；生成器不拥有 Native Capability、Bridge Adapter 生命周期或平台行为。

## Media Capture 入口

Media Capture 的 manifest 位于
[`media-capture.wire.json`](./contracts/media-capture.wire.json) 的 `codeGeneration` 字段，并由
[`wire.schema.json`](./contracts/wire.schema.json) 闭合约束。三种 Runtime 分别运行：

```bash
cd app
dart run tool/generate_media_capture_wire.dart --runtime dart
dart run tool/generate_media_capture_wire.dart --runtime android
dart run tool/generate_media_capture_wire.dart --runtime ios
```

`--check` 只比较已登记输出，不启动 formatter、不创建临时文件，也不写入任何文件。`--output <path>`
只能显式选择当前 Runtime 在 manifest 登记的仓库内普通文件；`--root <path>` 仅用于测试或从其他工作
目录运行。输入、输出和父目录都拒绝符号链接逃逸。Dart 生成使用 workspace 固定版本的
`dart_style` 内存 API 校验并规范化源码；最终写入使用同目录临时文件与原子替换，失败会清理临时文件。

生成器固定当前规范化 Wire Schema 摘要，并独立固定三端精确输出路径。自定义 `--root` 中的 Schema
不能放宽 Contract 类型或授权其他 `app/**` 写入目标；Schema 漂移必须与生成器实现一同审查和更新。

每份输出都带固定 generator version、相对 Contract 来源和规范化 source digest，不包含时间戳、绝对
路径、主机或用户名。source digest 只覆盖实际生成的投影，因此 `security`、lifecycle cleanup 等手写
段落的描述调整不会伪造生成漂移；生成前后仍会核对完整 Contract 和 Schema 的 SHA-256，避免读取与写入
之间输入变化。

## 可生成边界

`codeGeneration.generated` 逐项引用 Wire version、Channel、method、event、result/failure type、error、
error detail、payload、field、envelope 和 transport constraint 的现有 ID 或 JSON Pointer。生成器要求这些
引用与当前 Contract 集合精确相等，并在三端使用同一个规范化中间模型和稳定排序。

Runtime renderer 只输出：

- 稳定标识和闭合 enum wire value；
- payload/field descriptor，包括 required、nullable、wire key、基础类型、enum、signed-64、finite、
  range、length、format 与 unknown-key policy；
- 无副作用的 exact-key 和单字段基础类型/范围 primitive。

名称映射固定为 wire `snake_case` 到标识 `lowerCamelCase`、类型 `UpperCamelCase`。生成前拒绝重复 wire
value、映射 collision、Runtime 保留字、未知 Contract ID 和无法表达的 Channel 类型。字符串由各语言
renderer 转义，不能把 Contract 文本拼成未引用的源代码。

## 必须手写的边界

`codeGeneration.manualOnly` 只用于 coverage，不生成可执行实现。以下职责始终留在对应 Runtime：

- Capability model/mapping、method dispatch 与 Native Module 调用；
- request/listener/owner generation、异步 exactly-once completion 与 late cleanup；
- UI thread、Android main thread、iOS MainActor 和平台 owner；
- Session、lease、transfer store、presentation、文件与 URI 系统调用；
- Native SDK、权限、资源 ownership、日志、诊断与 redaction；
- 复杂跨字段条件验证。

三端迁移任务分别拥有已登记生产输出及编译证据。所有 Runtime 完成迁移前，标准 `make check` 不接入
全仓 drift check；临时生成文本也不能证明 Dart、Kotlin 或 Swift 可编译。
