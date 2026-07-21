---
task: codex-native-adapters
status: passed
p0: 0
p1: 0
---

# Review：Codex 原生资产适配

## Findings

P0：0。

P1：0。

### P2-1 `--root` 会把后续选项误当作路径

- 位置：`app/tool/sync_codex_adapters.dart:35`
- 影响：`--root --check` 没有按无效 CLI 用法以 64 退出，而是把 `--check` 解释成目录，随后以 1 报告该目录缺少 `.claude` 资产。自动化调用参数拼接错误时会得到误导性诊断。
- 证据：独立运行 `sync_codex_adapters.dart --root --check` 返回 1，并报告缺少 Claude Skill、Command 和 Agent 目录；单独缺少 `--root` 值和未知选项则正确返回 64。
- 建议：解析 `--root` 时拒绝下一个以 `--` 开头的参数，并为缺值、选项充当值、未知选项和两种合法选项顺序增加 CLI Fixture。

### P2-2 Fixture 没有独立验证生成格式和 Command/Skill 名称冲突

- 位置：`scripts/quality/test-harness.sh:159`、`app/tool/codex_adapters.dart:94`
- 影响：现有 Fixture 覆盖篡改、缺失、过期、同名手写文件、`AGENTS.md` 漂移及手写入口保护，但没有覆盖 Command/Skill 同名冲突，也没有用独立解析器断言生成 Skill 的首行 frontmatter、`name`/`description` 或 Agent TOML 语法。Harness 复用同一生成算法是正确的，但若模板算法自身退化，内容相等检查也会一起接受非法输出。
- 证据：当前 23 个生成 Skill 的首行和元数据经独立检查有效，9 个 Agent 文件经标准 TOML 解析器解析成功；带空格根路径和名称冲突行为也经临时 Fixture 验证正确。上述断言尚未进入仓库测试。
- 建议：在 Harness Fixture 中加入 Command/Skill 同名失败用例，并对生成 Skill 和 Agent 分别执行结构化 YAML/TOML 解析及必填字段断言；补一个带空格根路径用例。

### P2-3 入库任务证据尚未覆盖完整验收命令

- 位置：`docs/reviews/test-evidence/codex-native-adapters.log:1`、`docs/tasks/done/codex-native-adapters.md:79`
- 影响：现有日志只记录 `make codex-adapters-check`、`make analyze` 和 `make harness-test`，没有保存任务卡列出的 `make codex-adapters`、`make harness-check`、`make check` 与 `git diff --check` 证据。当前实现已由本次 Review 独立验证，但归档证据仍不完整。
- 建议：归档前通过证据采集器补录缺少的只读验收命令；同步命令如不希望为留证再次写入，可记录首次生成时的原始执行证据，或明确以只读 Check 作为确定性等价验证。

### P2-4 README 仍把 Codex 专用入口称为“工具无关”

- 位置：`README.md:13`、`docs/README.zh-CN.md:13`
- 影响：本任务已把 `AGENTS.md` 定义和生成为 Codex 启动适配，但中英文能力清单仍称其为 tool-neutral / 工具无关入口，与紧随其后的 Codex 原生适配说明不一致。
- 建议：改为“Codex entry point / Codex 入口”，同时保留 `CLAUDE.md` 是唯一权威契约的表述。

## 审查结论

生成器在写入前统一检查所有期望路径，只覆盖带前三行生成标记的受管文件；同名手写 Skill、Agent 或 `AGENTS.md` 会导致同步停止且内容保持不变。过期清理只扫描 `.agents/skills/**/SKILL.md` 和 `.codex/agents/*.toml` 中带标记的文件，不会读取或删除其他手写资产。

Claude Skill 与 Command 共 23 个，对应 23 个 Codex Skill；Claude Agent 与 Codex Agent 均为 9 个。Skill/Command 名称使用 kebab-case 并检查冲突，描述来自 YAML frontmatter；Agent TOML 包含 `name`、`description` 和 `developer_instructions`。`harness_check.dart` 直接调用 `CodexAdapterManager.check()`，没有维护第二套期望内容算法。

P0/P1 均为 0，任务可以通过；各项 P2 的最新状态见文末“复审”。

## 验证

- `make codex-adapters-check`：通过。
- `make harness-check`：通过。
- `make harness-test`：通过。
- `make check`：通过；格式检查 15 个 Dart 文件且 0 个变化，Analyze 无问题，全部 Harness/Spec/Lint/Hook/Evidence Fixture 和 2 个 Widget 测试通过。
- `git diff --check`：通过。
- 独立格式检查：23 个生成 Skill 均以 `---` 开始且包含合法 `name`/`description`；9 个 Agent TOML 均解析成功。
- 临时路径 Fixture：带空格根路径同步与 `--check` 通过；Command/Skill 同名时同步返回 1 且已有输出哈希不变。

## 验证缺口

- 未在 Windows 主机实际执行生成器；当前实现使用 `Directory`/`File`/`Uri` 和统一正斜杠相对引用，未发现 POSIX 符号链接依赖，macOS 带空格路径已验证。
- 未验证 Codex 是否会在具体客户端版本中自动委派项目 Agent；任务卡已将该行为准确列为运行模式约束，而非生成器保证。

## 复审

### 结论

P0：0。

P1：0。

P2：1。

任务仍为 `passed`。初审 4 项 P2 中，P2-2、P2-3、P2-4 已关闭；P2-1 的 CLI 实现已修复，但其新增“重复 `--root`”分支尚缺仓库 Fixture，因此保持 1 个低风险测试缺口。

### P2 状态

| 问题 | 状态 | 复审证据 |
| --- | --- | --- |
| P2-1 CLI 参数解析 | 部分关闭 | `app/tool/sync_codex_adapters.dart:36` 已拒绝选项充当 root 和重复 root；两种合法顺序及 `--root --check` 已有 Fixture，重复 `--root` 仅由本次复审手工验证，`scripts/quality/test-harness.sh` 中没有对应调用。 |
| P2-2 独立格式与冲突验证 | 已关闭 | `CodexAdapterManager.check()` 会独立解析期望 Skill 的 YAML frontmatter，并用受限 TOML 字段/JSON 字符串解析验证 Agent；Fixture 使用带空格根路径，覆盖 Command/Skill 名称冲突并用 `cmp` 断言已有输出不变。 |
| P2-3 入库命令证据 | 已关闭 | `docs/reviews/test-evidence/codex-native-adapters.log` 已记录 `make codex-adapters`、`make harness-check`、`git diff --check`、修改后的 `make harness-test` 和完整 `make check`，退出码均为 0。 |
| P2-4 README 入口名称 | 已关闭 | `README.md:13` 与 `docs/README.zh-CN.md:13` 已分别改为 Codex entry point / Codex 入口。 |

### 剩余 P2

#### P2-1a 重复 `--root` 缺少回归 Fixture

- 位置：`scripts/quality/test-harness.sh:166`、`app/tool/sync_codex_adapters.dart:36`
- 影响：实现已经通过 `root != null` 正确拒绝重复 `--root`，但 Fixture 只断言两种合法顺序和 `--root --check` 缺值场景；以后删除重复参数保护时，现有测试不会失败。
- 证据：仓库 Fixture 中共有 5 处 Adapter CLI `--root` 调用，没有重复 `--root` 用例；本次复审直接运行重复 root，确认当前退出码为 64。
- 建议：在现有 CLI Fixture 后增加 `--root "$FIXTURE_ROOT" --root "$FIXTURE_ROOT"`，断言退出码为 64。

### 复审验证

- `make codex-adapters-check`：通过。
- `make harness-check`：通过。
- `make harness-test`：通过，包含最新带空格路径、名称冲突、格式校验和手写文件保护 Fixture。
- 直接运行重复 `--root` 与 `--root --check`：当前均以 64 退出。
- 最新入库 `make check` 证据：退出码 0，格式、Analyze、Harness、Spec、Lint、Hook、Evidence 和 Widget 测试均通过。
- `git diff --check`：通过。

## 最终复审

### 结论

P0：0。

P1：0。

P2：0。

任务状态保持 `passed`。初审及第一次复审列出的全部 P2 均已关闭，没有新增问题。

### P2-1a：已关闭

- 位置：`scripts/quality/test-harness.sh:179`
- 修复：Fixture 现在显式执行 `--root "$FIXTURE_ROOT" --root "$FIXTURE_ROOT"`，捕获退出码并要求为 64；与缺失 root 值及两种合法选项顺序共同覆盖 CLI 分支。
- 复审证据：新增断言位于 `scripts/quality/test-harness.sh:179-187`；更新后的 `make harness-test` 已通过，并记录在 `docs/reviews/test-evidence/codex-native-adapters.log`。

### 最终验证

- `make harness-test`：更新后的 CLI Fixture 通过。
- `make codex-adapters-check`、`make harness-check`：最新实现通过，见入库证据及前次复审。
- `make check`：最新完整门禁证据退出码为 0。
- `git diff --check`：通过。

最终结论：Codex 原生适配的生成安全、过期清理、Skill/Agent 格式、跨平台路径策略、CLI、Harness 算法复用、任务证据和双语文档均满足本任务验收；P0/P1/P2 全部清零。

## 提交后独立审查（2026-07-21）

前述“最终复审”已被本节取代。任务已重新打开，当前状态为 `failed`。

### P1-1 受管输出路径可通过符号链接逃逸仓库

- 影响：`.agents` 或 `.codex` 的祖先路径被替换为符号链接时，同步可能在仓库外写入生成文件。
- 修复要求：检查和同步必须拒绝受管路径中的符号链接或仓库外解析结果，并以结构化错误退出。

### P1-2 CRLF checkout 会被误判为全部适配漂移

- 影响：Git 在 CRLF 工作区检出生成文件时，逐字节字符串比较会产生无业务意义的失败。
- 修复要求：比较时统一换行，并通过 `.gitattributes` 固定生成资产的 LF 入库规则。

### P2-1 同步缺少事务边界

- 影响：当前实现先删除过期文件、再逐个直写期望文件；中途异常会留下部分同步状态。
- 修复要求：全量预检，先准备所有新内容，最后应用；任一步失败时恢复同步前内容，过期文件最后处理。

### P2-2 Command 参数契约不完整

- 影响：生成 Skill 没有保留 Command 的 `argument-hint`，也没有区分显式 `$skill-name` token 与实际 `$ARGUMENTS`。
- 修复要求：在生成正文中写入参数提示，并明确显式调用时移除选择 Skill 的 token、语义触发时使用完整任务输入。

### P2-3 Git Hook 未覆盖适配漂移

- 影响：开发者可在本地 push 前遗漏 `make codex-adapters`，只能依赖 CI 较晚发现。
- 修复要求：在 `pre-push` 增加轻量 `make codex-adapters-check`，不扩大为完整 Harness 门禁。

## 修复后独立复审（2026-07-21）

### 结论

P0：0。

P1：0。

P2：0。

任务恢复为 `passed`，提交后独立审查列出的两项 P1 和三项 P2 全部关闭。

### 修复状态

| 问题 | 状态 | 复审证据 |
| --- | --- | --- |
| P1-1 符号链接逃逸 | 已关闭 | 受管路径逐级拒绝符号链接和仓库外解析结果，写入与 stale 删除前再次校验；Fixture 覆盖 `.agents`、`.codex/agents` 和 `AGENTS.md`，并断言仓库外内容未变化。 |
| P1-2 CRLF 漂移 | 已关闭 | 比较和生成标记识别统一换行，`.gitattributes` 固定受管资产为 LF；Fixture 验证 CRLF 只读检查通过且同步恢复 LF。 |
| P2-1 同步事务 | 已关闭 | 同步先预检并暂存全部期望文件，逐文件原子替换，最后删除 stale；失败时恢复全部原始字节并清理临时目录。Fixture 注入真实中途权限失败，比较所有受管输出与 stale 状态。 |
| P2-2 Command 参数 | 已关闭 | 生成 Skill 保留 `argument-hint`，区分显式 `$skill-name` token 与语义触发输入，并声明缺参停止规则；Fixture 覆盖多目标提示和两种触发说明。 |
| P2-3 pre-push 覆盖 | 已关闭 | `pre-push` 增加轻量 `make codex-adapters-check`，Hook Fixture 断言适配、Analyze 和 Lint 三项均执行，安装提示同步更新。 |

修复期间额外关闭了五项复审缺口：文件系统错误诊断会把仓库路径替换为 `<repo>`，不会泄漏本机绝对路径；事务 Fixture 确实进入部分替换后的回滚分支；后续 Command 失败 Fixture 保留 `argument-hint`，避免由适配漂移造成假通过；证据采集会规范化终端 CR 和行尾空格；命令 argv 与终端输出使用独立管线，尾随空格及多行参数通过可重放 quoting 保持原始语义。

### 独立验证

- `make harness-test`：通过，覆盖符号链接逃逸、CRLF、Command 参数、事务中途失败回滚和路径脱敏。
- `make check`：通过，包含格式、Analyze、Harness、Spec、Lint、Hook、Evidence、Proto 和 Flutter 测试。
- `make codex-adapters-check`：通过。
- `git diff --check` 与 Shell 语法检查：通过。
- `git check-attr`：`AGENTS.md`、生成 Skill 和 Agent 均固定为 LF。

### 剩余风险

- 未在 Windows 主机实际执行；CRLF 和路径分隔行为已由跨平台 Dart API、`.gitattributes` 和本地 Fixture 覆盖。
- 未验证具体 Codex 客户端版本的项目 Agent 自动委派行为；该行为继续属于运行模式约束，不是生成器保证。
