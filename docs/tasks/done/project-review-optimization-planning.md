---
executor: task-executor
platforms: []
workKinds: [planning]
blockedBy: []
---

# 收敛项目审查优化项并拆分实施任务

## 背景

项目级只读审查确认当前架构边界、双端 Native Module、Bridge 契约和测试体系已经形成闭环，
现阶段的主要优化空间集中在本地质量门禁效率、生命周期、依赖治理、证据规模、跨 Runtime
协议维护和 Asset 复用。

本任务卡记录审查提出的七项优化及当前决策状态。七项优化方向均已获确认。本卡只负责决策
收敛与后续拆卡，不直接修改实现。

## 输入与事实来源

- `CLAUDE.md` 的架构不变量、任务所有权、文档生命周期和验证要求。
- `Makefile` 的 `make check` 完整质量门禁。
- `scripts/git-hooks/test-pre-commit.sh` 的临时 Git 仓库清理逻辑。
- `scripts/quality/test-harness.sh` 的 Harness 失败 Fixture。
- `app/tool/harness_check.dart` 的 Harness Validator 实现。
- `app/apps/demo/lib/auth/auth_state.dart` 与 `app/apps/demo/lib/demo_app.dart` 的 Session Reset 生命周期。
- Workspace 各 Package 的 `pubspec.yaml` 和 `app/packages/app_im/`。
- `scripts/quality/capture-evidence.sh` 与 `docs/reviews/test-evidence/`。
- `docs/bridge/contracts/` 和 Media Capture 的 Dart、Android、iOS Wire Codec。
- `app/packages/app_features/assets/` 中内容相同的 Catalog 与 Wishlist 图片。
- 本次审查实测：`make check` 的 Hook Fixture 在交互式终端进入只读 Git object 删除确认；
  Harness 自测包含约 312 次独立 Validator 进程调用，单项运行超过 8 分钟。

## 优化项与决策状态

| 序号 | 优化项 | 当前状态 |
| --- | --- | --- |
| 1 | 修复交互式 `make check` 的临时 Git 仓库清理挂起 | 方案已确认 |
| 2 | 缩短 Harness Validator 与失败 Fixture 的反馈周期 | 方案已确认 |
| 3 | 为 Session Reset 注册增加解除机制 | 方向已确认 |
| 4 | 清理无消费者 Package 和多余 Workspace 直接依赖 | 方向已确认 |
| 5 | 控制入库测试证据的长期体积增长 | 方向已确认 |
| 6 | 降低 Media Capture Wire Contract 三端手工同步成本 | 方向已确认 |
| 7 | 合并重复 Asset 并测量实际包体收益 | 方向已确认 |

## 第 1、2 项决策

### 1. 交互式质量门禁的临时目录清理

#### 具体问题

`scripts/git-hooks/test-pre-commit.sh` 会创建临时 Git 仓库，并在退出时执行：

```bash
rm -r -- "$FIXTURE_ROOT"
```

Git object 通常是只读文件。在带 TTY 的终端里，macOS `rm` 删除这类文件时会逐个询问是否
覆盖只读权限。本次审查中的 `make check` 因此停在多条 `override r--r--r-- ...?` 提示上，
需要人工输入后才继续。CI 通常没有交互式 TTY，所以这个问题主要影响开发者本地执行；它不
表示测试断言失败，也不涉及删除真实仓库文件。

#### 已确认方案

- 采用仓库已有的安全清理模式，对经过校验、由当前脚本创建的临时目录执行
  `find -P "$FIXTURE_ROOT" -depth -delete`。
- 保留临时目录真实路径和预期前缀校验，确保删除范围只能是本次 Fixture 创建的目录。
- 使用 `-P`，不跟随符号链接；不使用项目安全策略禁止的 `rm -rf`。
- 后续实现卡可以只读审计其他 Fixture 脚本的临时目录清理，但只修改能够复现同类问题的脚本，
  不做无证据的批量改写。

#### 决策

- 用户已确认采用上述方案；本规划卡不直接实施，后续为第 1 项创建独立实现任务卡。

### 2. Harness 自测反馈周期

#### 具体问题

`app/tool/harness_check.dart` 当前约 13,000 行，主要逻辑集中在一个 Validator 类中；
`scripts/quality/test-harness.sh` 约 5,100 行。Shell 测试每修改一次 Fixture，都会重新启动一个
Dart 进程并让 Validator 重新读取、解析和校验整个 Fixture 仓库。当前大约有 312 次这类调用，
所以单次 Validator 本身即使不慢，累计进程启动和重复解析也会让 Harness 自测超过 8 分钟。

这里不是建议删除失败 Fixture、降低校验强度或跳过 `make check`，而是希望保持相同行为证明，
减少重复启动与重复解析。

#### “失败 Fixture”的含义

Fixture 是测试为了复现某个场景而专门构造的最小输入或样例仓库。“失败 Fixture”是故意构造
成不合法的样例，并预期 Validator 拒绝它；这里的“失败”描述的是样例应该触发校验失败，
不表示项目测试发生了意外失败。

例如，先准备一张能够通过校验的合法任务卡，再删除必填的 `executor` 字段。对应测试应确认：

1. 合法任务卡返回成功。
2. 缺少 `executor` 的任务卡返回非零退出码。
3. 诊断信息明确指出缺少 `executor`，而不是其他无关错误。

成功 Fixture 证明合法状态能够通过，失败 Fixture 证明非法状态确实会被门禁拦截。前述约 312 次
指 Validator 调用总数，其中包含大量失败 Fixture 校验和合法基线复查，并不是 312 个当前失败的测试。

#### 已确认方案

- 把 Validator 拆成可导入的 Dart library 和很薄的 CLI，CLI 继续保持现有调用方式。
- 将成功和失败 Fixture 迁移为参数化 Dart 测试，在同一 Dart VM 中直接调用 Validator，减少
  重复进程启动与不必要的重复解析。
- 保留全部现有成功/失败场景、CLI 退出码、诊断文案和拒绝语义；不得用删除用例、降低校验
  强度或跳过 `make check` 换取耗时下降。
- 修改前先在固定环境记录 `make harness-test` 耗时基线，修改后在相同条件下复测。性能目标根据
  基线和首轮迁移实测确定，不在规划阶段指定没有证据的分钟数。
- 代码拆分以形成可测试边界和降低维护成本为目标，不因文件行数进行无行为收益的机械拆分。

#### 决策

- 用户已确认采用上述方案；本规划卡不直接实施，后续为第 2 项创建独立实现任务卡。

## 已确认方向

### 3. Session Reset 生命周期

- 让注册操作返回可解除的句柄，或提供等价的显式移除 API。
- `DemoApp` 销毁时解除自己注册的回调，避免外部复用 `AuthStateCoordinator` 时继续持有旧的
  `FeaturesRegistry`。
- 增加 Widget/单元测试，覆盖挂载、卸载、重新挂载和外部所有权组合。

### 4. Workspace 依赖治理

- 核对 `app_im` 是否存在真实消费者；没有消费者时移除占位 Package 及其 Workspace 声明，
  后续真实 IM 任务再按契约创建。
- 删除 Demo 和 `app_features` 中未被源码直接 import、也不承担必要 Plugin 发现职责的直接依赖。
- 扩展依赖门禁，除禁止越界依赖外，也能发现无真实消费者的 Workspace 直接依赖。
- 修改依赖图后必须验证 Flutter Plugin discovery，不能因清理直接依赖破坏 Media Capture 注册。

### 5. 测试证据体积

- 保留任务要求的命令、版本、退出码、测试摘要、必要失败片段和实现摘要。
- 评估把完整成功日志转为有保留期的 CI Artifact；失败证据仍按可复现和脱敏要求保存。
- 不重写既有 Git 历史，不在未确认保留策略前删除现有证据。
- 更新证据采集、脱敏、Harness 校验和工作流文档时保持同一事实来源。

### 6. Wire Contract 三端同步

- 先识别可以从结构化 Contract 确定生成的稳定常量、枚举、字段表和基础 Codec，平台生命周期、
  线程、资源所有权与 Native 行为继续手写。
- 不引入 Proto 作为 MethodChannel Payload，也不让生成代码拥有 Native Capability。
- 该方向必须按所有权拆成 Wire Contract/生成规则、Dart Client、Android Adapter、iOS Adapter
  和最终跨 Runtime 集成任务；不能由单个平台 Executor 包办。
- 生成产物必须由生成器修改，并增加 drift check、Golden Vector 和三端兼容验证。

### 7. Asset 复用与包体

- 合并内容完全相同的 Catalog/Wishlist PNG，更新 Fixture 和 Asset 测试引用。
- 删除前检查 Flutter、测试和原生侧引用，不根据文件名推断未使用。
- 使用相同平台、架构、构建模式和参数生成前后 Size Analysis，报告实际收益；源码字节减少量
  不能替代 APK/AAB/IPA 实测结果。

## 非目标

- 本卡不实施上述七项代码、脚本、依赖、协议或 Asset 修改。
- 不删除现有失败 Fixture、Review、测试证据或历史任务。
- 不降低 Harness、Bridge、安全审查或平台构建门禁。
- 不把 Android、iOS、Dart 和跨 Runtime 集成合并给同一个执行者。
- 不因文件较大而进行无行为收益的机械拆分。

## 后续拆卡要求

1. 第 1、2 项按已确认方案拆卡，并在实现任务中明确行为兼容边界和非目标。
2. 七项分别创建可独立执行和验证的任务卡；第 6 项继续按 Runtime 与最终集成拆分。
3. 每张任务卡重新核对 `executor`、`platforms`、`workKinds`、依赖顺序和是否触发
   `securityReview: required`。
4. 各项先建立行为或体积基线，再实施修改并用相同条件复测。

## 拆卡结果

1. Hook Fixture 清理：`fix-hook-fixture-safe-cleanup`。
2. Harness 反馈周期：先执行 `extract-harness-validator-library`，再执行
   `migrate-harness-fixtures-to-dart-tests`。
3. Session Reset 生命周期：`add-session-reset-registration-disposal`。
4. Workspace 依赖治理：先执行 `add-workspace-dependency-consumption-checker`，再执行
   `remove-unused-workspace-dependencies`。
5. 测试证据体积：`bound-test-evidence-retention`。
6. Wire Contract 生成：先执行 `define-media-capture-wire-generation`；随后可分别执行
   `generate-media-capture-dart-wire-codec`、`generate-media-capture-android-wire-codec` 和
   `generate-media-capture-ios-wire-codec`；三端完成后执行
   `integrate-media-capture-generated-wire-contract`。
7. Asset 复用与包体：在依赖清理后先执行 `measure-android-catalog-wishlist-asset-baseline`，再执行
   `deduplicate-catalog-wishlist-assets`，最后执行 `verify-android-catalog-wishlist-asset-size`。

上述任务均已重新声明 Executor、平台、工作类型、依赖和 Security Review 要求；跨 Runtime 工作没有
合并给单个平台执行者。

## 本规划任务验收标准

- 七项优化均有事实来源、当前决策状态、目标、限制和后续所有权说明。
- 第 1、2 项均采用已确认方案，但尚未进入实现。
- 第 3 至第 7 项不再讨论方向，但仍需通过独立任务卡确认精确范围和验证方法。
- 后续任务拆分满足仓库 Executor 路由和跨 Runtime 所有权要求。

## 验证命令

```bash
make harness-check
git diff --check
```

## 平台与环境限制

本规划任务只修改文档，不需要 Flutter Device、Android SDK、Xcode、Figma 或 Marionette。
后续第 6、7 项的实际收益必须分别在对应 Runtime 和目标 Release 构建中验证。
