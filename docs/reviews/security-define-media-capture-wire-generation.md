---
task: define-media-capture-wire-generation
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/bridge/contracts/wire.schema.json
  - docs/bridge/contracts/media-capture.wire.json
  - docs/bridge/code-generation.md
  - docs/bridge/media-capture.md
  - docs/bridge/README.md
  - app/tool/generate_media_capture_wire.dart
  - app/tool/src/media_capture_wire_generation.dart
  - app/test/media_capture_wire_generator_test.dart
  - app/lib/src/harness_validator.dart
  - app/pubspec.yaml
  - app/pubspec.lock
  - scripts/quality/test-harness.sh
implementationDigest: 5d785e3fb74c8425b9dc47e635a1c1d50c6c130feb159b84851cbaa25727e1e8
---

# Security Review：Media Capture Wire 代码生成规则

## 首轮问题

### P1：不可信 Contract 值可进入源码 token

生成器未执行完整实例验证，error boolean、field validation 和 request/handle 长度可被替换为非类型化
文本。renderer 的直接 token 插值会把输入提升为构建期源码能力。

### P1：manifest 路径可重定向写入

manifest 与 CLI 输出路径互相比对不构成独立授权；编码点段、任意 `app/**` 路径和 symlink 组合可能覆盖
非目标文件。

### P1：三端边界校验不一致

Android/iOS 未完整执行 Contract range、allowed integer 与 list length，未来 Adapter 消费后会放大越界输入。

## 第二轮问题

- Schema 与 Contract 可同时投毒，放宽实例类型后重新形成源码注入；Schema 合法的大整数也可生成
  Kotlin Int 不可表达源码。
- Kotlin 对非 ASCII 使用了不合法 escape；numeric list 未逐元素执行 finite/signed-64。
- Swift 未按 Foundation boxed number 类型标签区分 Bool、整数与浮点，closed enum list 未拒绝重复值。

## 第三轮问题

- `--check` 在比较前通过系统临时文件运行 Dart formatter，违反严格只读边界；formatter 执行窗口内的
  Contract/Schema 变化还可让 check 或 unchanged 基于旧输入错误通过。
- formatter 子进程启动失败和递归清理失败缺少稳定错误边界，可能暴露未处理异常或掩盖原始失败。

## 修复与安全复审

- generator 固定当前规范化 Schema SHA-256，并独立执行完整实例验证和闭合强类型规范化；协同
  Schema/Contract 投毒、错误布尔/数值、超出 Kotlin Int 和源码文本 mutation 均在写入前失败。
- 三端输出路径是代码内固定 allowlist。percent、点段、空段、绝对路径、反斜杠、symlink、特殊节点和
  非目标文件均被拒绝；写前复核完整输入摘要并重新检查普通目标，原子失败保留旧文件与权限。
- renderer 对字符串分别做 Dart/Kotlin/Swift 转义；Kotlin 非 ASCII 使用 UTF-16 surrogate，Swift 用
  CFBoolean/CFNumber 类型标签。三端 primitive 对 scalar/list 的 finite、signed-64、range、length、enum
  和 duplicate 语义一致。
- 输出只包含 descriptor 和无副作用 primitive；manual-only 精确覆盖 Capability mapping、dispatch、
  lifecycle、thread、ownership、文件/URI、Native SDK、跨字段、日志与 redaction，未生成可执行平台行为。
- Dart formatter 改为 `dart_style 3.1.7` 内存 API，删除系统临时目录和子进程能力；`--check` 不创建、
  写入或删除任何文件。formatter 完成后、所有比较和返回前统一复核 Contract/Schema 摘要。
- `dart_style` 是唯一新增依赖，精确固定为 workspace direct dev dependency，lockfile 固定 pub.dev
  SHA-256；其现有依赖已由 analyzer 工具链提供，不进入 Runtime package 或 Native 产物。无新增网络、
  凭据、Agent、MCP、发布或 Native 权限能力。

复审确认已关闭全部已知攻击路径，最终 P0/P1/P2 为 0/0/0。Kotlin/Android 真实编译由后续 Runtime 卡
拥有；本卡已对临时 Swift 输出执行 typecheck，但不以此代替后续三端生产编译证据。

## 2026-08-07 提交门禁工具链窄复核

生成器新增的单终止换行规范化只影响生成文本尾部 LF，不改变 Wire 字段、校验、错误、权限或外部输入解释
路径。Makefile 的 `media-capture-wire-generate` 与 `media-capture-wire-check` 改为调用仓库既有
`scripts/dart-tool.sh` 和固定生成器参数，消除了对 PATH 中旧 Dart 的依赖，没有扩大命令、网络、发布或任意
文件写入能力。

生成目标仍受生成器注册路径限制，`--check` 保持只读；golden digest 继续绑定生成文件的精确字节内容。
独立 Security Reviewer 窄复核结论为 P0/P1/P2 0/0/0，并确认不影响 Android Transfer Store 安全审查结论。
