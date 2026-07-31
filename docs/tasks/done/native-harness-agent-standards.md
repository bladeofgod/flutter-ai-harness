---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy:
  - native-harness-architecture-foundation
securityReview: required
---

# 建立原生 Agent 与编码规范

## 背景

仓库现有 Skill 聚焦 Dart/Flutter，`testing-strategy` 还明确排除 Kotlin/Swift；现有 `bridge-engineer` 同时承担 Wire Contract、Android、iOS 和集成验证，无法为单平台模块提供足够聚焦的技术判断。需要通过兼容迁移扩展任务卡 Schema，补充 Android/iOS 专业角色和按路径加载的编码规范。

## 输入与事实来源

- `CLAUDE.md`
- `docs/native-architecture.md`
- `.claude/agents/architect.md`
- `.claude/agents/task-executor.md`
- `.claude/agents/bridge-engineer.md`
- `.claude/agents/reviewer.md`
- `.claude/agents/security-reviewer.md`
- `.claude/commands/plan-tasks.md`
- `.claude/commands/execute-tasks.md`
- `.claude/commands/fix-review-findings.md`
- `.claude/skills/dart-coding-standards/SKILL.md`
- `.claude/skills/testing-strategy/SKILL.md`
- Codex Adapter 生成约定

## 目标

- 新增聚焦 Android 与 iOS 原生工程的 Agent。
- 新增 Kotlin/Android、Swift/iOS 和原生测试 Skill。
- 让规划、执行、修复和 Review 按任务范围加载正确平台知识。
- 扩展任务卡 Schema，以 `executor`、`platforms` 和 `workKinds` 共同表达后续任务的执行者与范围。
- 生成并校验对应 Codex Adapter。

## 非目标

- 不实现任何 Native Module、Camera 或 Flutter Bridge。
- 不新增第三方 Gradle、Swift Package、formatter 或 linter 依赖。
- 不让平台 Agent 自行 commit、push、发布、读取凭据或扩大 Bash 权限。
- 不把 Android/iOS 代码规范复制进 `CLAUDE.md` 或 `docs/native-architecture.md`。

## 具体要求

1. 新增 `.claude/agents/android-engineer.md`，覆盖 Kotlin、Gradle、Android 生命周期、线程、权限、Manifest、Native UI、测试与构建；不得负责 iOS 或替代 Bridge Contract 所有者。
2. 新增 `.claude/agents/ios-engineer.md`，覆盖 Swift、Xcode/SPM、iOS 生命周期、并发、权限、Info.plist/Entitlements、Native UI、测试与构建；不得负责 Android 或替代 Bridge Contract 所有者。
3. 更新 `bridge-engineer`：负责结构化 Wire Contract、跨端语义一致性和最终集成验收；Dart Client 使用 `task-executor`，Android/iOS Bridge Adapter 与 Native Module 使用对应平台 Agent/Skill，Bridge 不拥有 Native Capability。
4. 新增以下事实源 Skill，并配置可确定校验的聚焦 `paths`：
   - `.claude/skills/kotlin-android-standards/SKILL.md` 覆盖 `app/native/android/**`、`app/apps/*/android/**` 和 `app/packages/*/android/**`，不得包含 iOS 路径。
   - `.claude/skills/swift-ios-standards/SKILL.md` 覆盖 `app/native/ios/**`、`app/apps/*/ios/**` 和 `app/packages/*/ios/**`，不得包含 Android 路径。
   - `.claude/skills/native-testing-strategy/SKILL.md` 可以同时覆盖上述两端测试路径，但不对纯 Dart 测试误触发。
5. Kotlin Skill 至少约束可见性、空安全、结构化并发、Dispatcher/Clock 可替换性、Flow 生命周期、UI 线程、资源释放、依赖注入、稳定错误和 Flutter import 隔离。
6. Swift Skill 至少约束 API Design、可见性、`Sendable`/actor、`@MainActor`、取消、Delegate 所有权、资源释放、错误映射、依赖注入、禁止强制解包和 Flutter import 隔离。
7. Native Testing Skill 区分纯单元测试、平台 Framework Fake、Host 编译、模拟器/设备测试和真机系统能力验证；不得把无法在 CI 操作的 Camera/系统权限伪装成已验证。
8. 更新 `CLAUDE.md`、`architect`、`plan-tasks`、`execute-tasks`、`fix-review-findings` 和 Harness Task Validator，新增以下结构化 frontmatter：
   - `platforms` 是无重复列表，只允许 `flutter`、`android`、`ios`；`documentation`、`planning`、`harness` 可以使用 `[]`，其他实现工作必须声明至少一个平台。
   - `workKinds` 是非空无重复列表，只允许 `documentation`、`planning`、`harness`、`flutter`、`dart-client`、`capability-contract`、`native`、`bridge-adapter`、`bridge-contract`、`integration`、`quality-gate`。
   - 本任务执行时迁移仍在 `docs/tasks/` 的活动任务；`docs/tasks/done/` 中缺少新字段的历史任务继续兼容，已声明新字段的归档任务仍必须通过值域校验。以后新建的活动任务一律要求两个字段。
9. Executor 与结构化范围只允许以下确定性组合：
   - `native`、单平台 `bridge-adapter` 或单平台 `quality-gate` 且 `platforms: [android]` 使用 `executor: android-engineer`。
   - 对应 iOS 工作且 `platforms: [ios]` 使用 `executor: ios-engineer`。
   - `dart-client`、Flutter Feature、页面、Controller、`documentation`、`planning`、`harness` 和 transport-neutral `capability-contract` 使用 `executor: task-executor`；Contract/文档类可以声明相关平台，但不得修改平台实现。
   - `bridge-contract` 和包含多个 Runtime 的最终 `integration` 使用 `executor: bridge-engineer`。
   - `task-executor` 不得承载 Android/iOS `native` 或 `bridge-adapter`；平台 Agent 不得承载另一平台、Flutter 或跨端集成。
10. `plan-tasks` 遇到同时包含 Android、iOS、Dart 或 Bridge 的需求时，必须按上述所有权拆成独立任务卡和集成卡，不得生成由一个平台 Agent 包办三端实现的大任务。
11. `execute-tasks` 只依据 frontmatter 选择 Agent 并校验声明范围，不根据文件名、正文或 diff 猜测平台；无效 Executor、字段缺失、结构化范围冲突、跨平台实现未拆卡时停止并报告。Reviewer 仍负责判断任务正文是否诚实匹配已声明范围。
12. `fix-review-findings` 优先回到原任务 Executor；修复同时跨越 Wire 或多个平台时交给 `bridge-engineer` 协调，并保持独立复审。
13. 更新 Reviewer 检查维度，覆盖声明范围与正文一致性、Native Module 公共 API、Host/Adapter 边界、平台生命周期、并发、依赖和原生测试缺口；Security Reviewer 保持只读且继续覆盖权限、文件、媒体和平台配置。
14. 修改 `.claude` 事实源后运行 `make codex-adapters`，不得手工编辑生成目录。

## 同时编写的测试

- 扩展 Codex Adapter Fixture，验证新增 Agent/Skill 的生成、缺失、过期和 description，并确保本应只读的 Reviewer/Security Agent 继续生成 `read-only` sandbox；不得要求 Adapter 复制其设计上只链接的 Skill `paths`，也不得错误地把需要写实现的平台 Engineer 设为只读。
- 扩展 Harness Fixture，验证四种 Executor、`platforms`、`workKinds`、活动任务必填、历史归档兼容、未知值、重复值和 Executor/范围冲突。
- 使用表驱动合法路由矩阵覆盖全部 11 个 `workKinds`、四种 Executor、Android/iOS 单平台门禁、Bridge Contract、Flutter/Dart Client、空平台和带相关平台的文档任务。
- 验证 Android/iOS Engineer 必须精确引用各自语言 Skill 和 `native-testing-strategy`，缺失、错平台或缺少原生测试 Skill 时失败。
- 验证 `docs/tasks/` 中指向仓库内外的符号链接和其他特殊节点都会被拒绝。
- 直接验证 Claude Skill 事实源中的 `paths` 非空、值合法且 Android/iOS 范围不交叉；该检查属于 Harness 源文件校验，不伪装成 Codex Adapter drift。
- 多平台输入是否被 `plan-tasks` 正确拆卡由 Bootstrap Gate 生成后的独立 Review 场景验收；当前没有确定性 Planner，不把 LLM 输出写成 `make harness-test` 的伪单测。
- 验证 Agent 不获得 commit、push、凭据、发布或无约束外部网络能力。

## 验收标准

- Android、iOS、Bridge 的职责不重叠且可以从任务范围确定性选择。
- 详细编码规范只存在于对应 Skill，架构文档只保留边界和原则。
- 所有新增 Claude Agent/Skill 都有同步生成的 Codex Adapter。
- 活动与归档任务继续通过门禁，后续任务可以直接声明 `android-engineer` 或 `ios-engineer`。
- Validator 可以只读结构化元数据拒绝 Executor/范围冲突；正文与声明范围的一致性由 Reviewer 检查。
- 多平台需求在规划阶段拆卡，不依赖运行时文件名、正文或 diff 猜测平台实现所有者。
- Security Review 确认 Agent、Command 和 Skill 的能力没有超出原生实现与只读审查需要。
- `make codex-adapters-check`、`make harness-check`、`make harness-test` 和 `git diff --check` 通过。

## 验证命令

```bash
make codex-adapters
make codex-adapters-check
make harness-check
make harness-test
git diff --check
```

## 平台或环境限制

本任务只建立 Agent/Skill、Task Schema 与路由规则，不需要 Android SDK、Xcode、设备或 Figma。具体 formatter/linter 版本由真实模块任务引入，不能在本任务预装空工具链。

本任务完成后继续执行被其阻塞的 Capability、Wire 和 Bootstrap Gate；不得在 Contract 尚未完成时提前生成第二阶段实现卡。第二阶段重规划由 `native-harness-bootstrap-gate` 唯一负责。

## 执行结果

- [实现 Review](../../reviews/execute-native-harness-agent-standards.md)
- [Security Review](../../reviews/security-native-harness-agent-standards.md)
- [测试证据](../../reviews/test-evidence/native-harness-agent-standards.log)
