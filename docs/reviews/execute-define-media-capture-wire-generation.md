---
task: define-media-capture-wire-generation
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：定义 Media Capture Wire 代码生成规则

## 首轮问题

- P0：生成器只检查 Schema 身份，未对实例执行完整闭合验证；若布尔、长度或数值被替换为源码文本，
  Dart/Kotlin renderer 可直接插值。
- P1：manifest 可自我授权任意 `app/**` 路径，URI percent 编码还可绕过字面点段检查。
- P1：Kotlin/Swift primitive 未完整执行 finite、range、allowed integer 与 collection length。
- P1：基础 Schema 强制所有 Wire 声明 codeGeneration，且空 event/failure 引用无法表达。
- P1：manual-only 只校验 pointer 存在，不校验每个类别的批准边界。
- P2：channel 名称映射、source digest 精确投影和已有目标原子失败 Fixture 不完整。

## 第二轮问题

- P1：Swift 未按 StandardMessageCodec 的 `NSNumber` 标签区分 Bool、整数与浮点数；闭合 enum list
  未拒绝重复值。
- P1：三端独有保留字表、重复 channel name 和重复 field wire key 未闭合。
- P1：Schema 与 Contract 可协同降级，request/handle 长度仍可能注入或生成 Kotlin Int 溢出源码。
- P2：Kotlin 非 ASCII escape 不合法，numeric list 未逐元素执行 finite/signed-64。
- P2：channel `kind` 等未渲染字段仍会造成仅 digest header 漂移。

## 修复与复审

- generator 固定规范化 Schema 摘要与三端精确输出白名单，执行完整 Schema 实例验证，并将
  error、field、envelope、request ID、signed-64 与 opaque handle 转为闭合强类型值后再渲染。
- 输出路径拒绝 percent、空段、点段、反斜杠、symlink 和非普通节点；写前重新校验输入摘要和目标，
  同目录独占临时文件失败时保留原目标及权限。
- 三端统一 scalar/list 类型、finite、range、allowed integer、length、closed enum 与 duplicate 语义；
  Swift 使用 `NSNumber`、CFBoolean/CFNumber 类型标签，Kotlin 使用 UTF-16 escape。
- 基础 Schema 的 codeGeneration 保持可选且引用集合允许空；Media Capture Profile 仍由 Harness
  强制完整 manifest。manual-only ID 与 pointer 集均精确校验。
- source digest 只覆盖实际 renderer-visible 投影；保留字、channel/field 重复值和 collision 都有负例。

## 第三轮问题与修复

- P1：Dart formatter 在 `--check` 分支前创建并写入系统临时文件，不符合严格只读语义；同时
  formatter 执行期间 Contract/Schema 变化可让 check 或 unchanged 分支基于旧快照提前返回。
- P2：外部 formatter 进程启动和临时目录清理错误没有稳定的生成器错误边界。
- 修复后使用 workspace 精确固定的 `dart_style 3.1.7` 内存 API，删除 formatter 子进程和系统临时
  文件；输入摘要在格式化之后、读取输出和任何返回之前统一复核。
- 新增 `--check` 仓库/系统临时目录零变更、check 与普通生成期间输入变化、formatter 失败不触碰输出、
  生成源码 formatter-stable 回归。专项测试共 40 项通过。

复审未发现未解决 P0/P1/P2。三端生产输出与 Runtime 迁移仍由后续任务卡拥有，本卡未写入生产生成文件。
