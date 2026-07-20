# Flutter AI Harness 项目契约

本文件是仓库的权威工程契约。修改代码或文档前必须先读。其他工具入口可以摘要本文件，但不得覆盖本文件的规则。

## 项目目标

本仓库是一套 AI 原生工程 Harness，也是一套有明确架构取向的 Flutter 混合应用工作区。AI Agent 和开发者共同使用相同的架构规则、任务产物、执行命令与质量门禁。

仓库分两个阶段建设：

1. 建立中立的 Harness 和仓库边界。
2. 通过 Harness 设计并实现全新 Demo，让任务卡、Review、App 文档和项目 Memory 从真实工作中自然产生。

不得从其他应用复制业务代码、凭据、历史任务或私有依赖到本仓库。

## 技术栈

### Flutter

- Flutter 3.35.7 / Dart 3.9
- 状态管理与轻量 DI：GetX（公开可复现依赖）
- 路由：`go_router ^15.1.2`
- 网络：`dio ^5.7.0` + Protocol Buffers `^6.0.0`
- 本地存储：`drift ^2.20.0` + `flutter_secure_storage ^9.2.2`
- 不可变数据：Freezed `^3.0.0`
- JSON 序列化：`json_serializable ^6.9.0`
- 测试：`flutter_test` + `mocktail ^1.0.4` + `integration_test`
- Monorepo 编排：Melos

### 原生平台

- Android：Kotlin / Gradle
- iOS：Swift / Xcode / CocoaPods

Demo 固定采用本节技术栈，不在产品设计或任务拆解阶段重新选型。依赖在首个真实消费者出现时加入所属 Package 并锁定兼容版本，不为填充清单引入未使用依赖。

## 仓库结构

```text
app/
├── apps/demo/
└── packages/
    ├── app_core/
    ├── app_data/
    ├── app_ui/
    ├── app_im/
    ├── app_rtc/
    └── app_features/
```

工作区随 Demo 实施逐步形成。不得为了填充目录而预先创建没有真实需求的业务抽象。

## 架构不变量

1. Domain Entity 是唯一允许跨架构层传递的数据类型。
2. Proto Message 和数据库 Row 必须留在各自的数据适配层。
3. 每个包只定义自己需要的接口，不建立中央万能契约包。
4. 依赖方向保持单向。下图中 `A -> B` 表示 Package A 可以 import Package B：

   ```text
   apps/demo -> app_features, app_data, app_im, app_rtc, app_core, app_ui
   app_features -> app_data, app_im, app_rtc, app_core, app_ui
   app_data / app_im / app_rtc -> app_core
   app_core / app_ui -> 不依赖其他 Workspace Package
   ```

5. Feature 不得 import 其他 Feature 的内部实现。
6. 跨 Feature 交互通过 `app_features/lib/api/` 下的抽象接口和统一注册机制完成。
7. 壳工程只负责模块与回调装配，不得 import Feature 实现类。
8. Controller 通过构造函数接收必需 API。服务定位器只允许出现在装配点或显式全局服务中。
9. 只有在确实降低复杂度或保护真实边界时才新增抽象。

详细规则见 `docs/architecture.md` 和当前任务相关的 Skill。

## Flutter 默认约定

- 路由统一使用 `go_router`，根应用使用 `MaterialApp.router`。
- GetX 只用于状态管理和轻量 DI，不负责路由和 UI Overlay。
- 只使用公开且可复现的依赖；开源模板不得依赖私有 fork。
- 即使存在服务定位器，也优先使用构造函数注入。
- 响应式刷新必须包裹读取状态的最小子树。
- `*.g.dart`、`*.freezed.dart` 和 Protobuf 生成文件只能由生成器修改。

依赖写入真实消费者所属的 Package `pubspec.yaml`；只有 Workspace 工具依赖写入根 `app/pubspec.yaml`。

## 混合工程 Bridge 契约

Android、iOS 都是长期维护的一等平台。

MethodChannel 和 EventChannel 必须遵守：

- 实现改动前先更新 `docs/bridge/` 下的契约。
- 使用可替换的反向域名命名空间，例如 `com.example.<module>.<feature>`。
- method、event type、error code 和枚举 wire 值使用小写 `snake_case`。
- payload key 可以使用 `lowerCamelCase`，但同一契约必须保持一致。
- 只传输 `String`、`num`、`bool`、`List`、`Map<String, dynamic>` 和 `Uint8List`。
- 禁止通过平台通道传递 Proto 对象。
- 错误使用 `PlatformException(code, message, details)`，`code` 必须是稳定字符串。
- Native 回调 Flutter 时必须切回平台 UI 线程。
- 所有声明支持的平台必须保持一致；有意差异必须写入契约。

详见 `docs/bridge/README.md` 和 `bridge-engineer` Agent。

## AI 工程资产

项目 Skill 的路径触发依赖 Claude Code 2.1.198 或更高版本。

只按当前任务加载必要文件：

- 工作流：`.claude/commands/*.md`
- 角色：`.claude/agents/*.md`
- 技能：`.claude/skills/*/SKILL.md`
- 低频工程经验：`.claude/memories/*.md`

命名约定：

- Agent 用主体名词，例如 `architect`、`reviewer`、`task-executor`。
- Command 使用动宾结构，例如 `plan-tasks`、`review-changes`。
- Skill 使用聚焦领域名，例如 `go-router`、`testing-strategy`。

新增 Skill 必须包含 `name`、面向触发场景的 `description` 和相关 `paths`。`paths` 使用 glob 模式限定 Skill 适用的仓库路径；`description` 必须说明适用场景、不适用场景和触发关键词。

## 支持的工作流

- `/plan-tasks`：把产品或技术输入拆成任务卡。
- `/plan-figma`：结合 Figma 和代码上下文生成 UI 任务卡，不做实现。
- `/plan-spec`：根据已批准任务或原型输入生成 UI 行为 Spec，不做实现或 App 操作。
- `/execute-tasks`：执行已有任务卡并完成验证与 Review。
- `/review-changes`：只读审查当前改动并输出问题报告，不修改实现。
- `/review-sprint`：从批次整体视角只读审查跨任务影响。
- `/fix-review-findings`：在用户明确要求后，修复已有 Review 报告中的问题并复审。
- `/check-release`：执行发版前就绪检查。

## Marionette

Demo 使用 `marionette_flutter` 暴露 Debug VM Service 扩展，仓库根目录的 `.mcp.json` 为 Claude Code 配置 `marionette_mcp`。Marionette Binding 只能在 Debug 模式初始化，不得进入 Profile 或 Release。

首次 Clone 后运行 `make marionette-install` 安装 MCP Server。启动 Demo 后，将 `flutter run` 输出中的 `ws://.../ws` VM Service URI 提供给 Agent，再按 `marionette-debug` Skill 或 `app-operator` Agent 操作。

自定义设计系统组件必须在 Demo 实装时补充 `MarionetteConfiguration`、稳定 Key/Semantics 和日志收集；不得把“已连接 MCP”误认为自定义组件已经可操作。

## Figma MCP

仓库根目录的 `.mcp.json` 将 `figma` 指向 Figma Desktop 本地 MCP `http://127.0.0.1:3845/mcp`。使用前必须在 Figma Desktop 打开设计文件、进入 Dev Mode，并启用 Desktop MCP Server；Claude Code 首次发现该项目级 Server 时由用户批准。

Figma 规划和实现必须通过本地 MCP 读取当前节点，不依赖截图猜测结构。连接不可用时准确报告前置条件，不退化为编造设计上下文。

## 文档生命周期

- `docs/tasks/sprint-N/` 保存同一 Sprint 的 Overview、任务卡和可选输入快照；根目录不直接存放规划产物。
- `docs/tasks/done/` 保存已完成的任务卡，任务 ID 保留所属 Sprint 编号。
- `docs/reviews/` 保存执行过程产生的 Review 报告和测试证据。
- `app/docs/` 保存随 Demo 形成的应用架构和决策文档。
- `.claude/memories/` 保存低频且长期有效的经验，不保存任务历史或重复规范。

不得预置虚构的过程历史。首次产生真实文档时再创建对应目录。

## 验证

根据改动影响面执行验证。Flutter 工作区建立后使用：

```bash
make format
make analyze
make test
make spec-check
make integration-test INTEGRATION_DEVICE=<device-id>
make lint
make harness-check
make check
```

Dart 改动：

1. 注解源或 Proto 变化时运行代码生成。
2. 静态分析必须将 warning 视为失败。
3. 使用 `dart format --output=none --set-exit-if-changed` 做只读格式检查。
4. 先运行覆盖改动行为的测试；共享契约变化时扩大验证范围。

原生改动必须构建受影响的平台。环境不可用时，应明确列出未验证平台和文件，不得宣称已经验证。

## 安全策略

- 不读取或提交 `.env*`。
- 不手工编辑依赖锁文件。
- 不手工编辑生成代码。
- 不输出凭据、签名值或本机私有路径。
- 不执行 `rm -rf` 等破坏性命令。
- 保护用户已有改动，不做无关重写。
- 用户未明确要求时，不 commit、不 push。
- 正常流程中禁止使用 `--no-verify` 绕过 hooks。
- 优先使用官方公开 API。若生产方案必须依赖私有 API、反射、修改三方依赖或未文档化行为，必须先说明风险并取得用户同意。

## Git 约定

使用 Conventional Commits：

```text
<type>(<scope>): <description>
```

常用类型：`feat`、`fix`、`docs`、`refactor`、`test`、`chore`。每个提交只包含一个清晰作用域，不混入无关改动。

## 重要参考

- **架构设计**：[`docs/architecture.md`](./docs/architecture.md)（包职责、类型边界、Feature 边界、装配与路由）。
- **IM 架构**：[`docs/im-architecture.md`](./docs/im-architecture.md)（占位；随 Demo 的首个 IM 任务补充 Engine、事件和生命周期设计）。
- **RTC 架构**：[`docs/rtc-architecture.md`](./docs/rtc-architecture.md)（占位；随 Demo 的首个 RTC 任务补充 Bridge、会话和生命周期设计）。
- **基础模块清册**：[`docs/infrastructure-modules.md`](./docs/infrastructure-modules.md)（占位；用于避免重复实现已有公共能力）。
- **API 契约**：[`docs/api-contracts.md`](./docs/api-contracts.md)（占位；首个真实 API/Proto 任务建立权威来源和生成链路）。
- **设计稿输入**：[`docs/figma-links.md`](./docs/figma-links.md)（占位；记录 Demo 使用的 Figma 来源、授权和读取规则）。
- **UI 行为 Spec**：[`docs/app-operator/README.md`](./docs/app-operator/README.md)（Version 1 Schema、生成、静态审计与运行规则）。
- **Marionette UI 调试**：[`docs/development-workflow.md`](./docs/development-workflow.md#marionette-mcp) 与 `marionette-debug` Skill。
