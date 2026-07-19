# 开发工作流

## 首次 Clone

中立 Harness 先于 Demo 工作区建立。`app/pubspec.yaml` 创建后执行：

```bash
make bootstrap
make check
```

`make bootstrap` 解析工作区依赖并安装仓库内 Git hooks。

## AI 辅助交付闭环

```text
需求或设计稿
      ↓
architect / plan command
      ↓
docs/tasks 中的任务卡
      ↓
task-executor 或 bridge-engineer
      ↓
聚焦验证证据
      ↓
reviewer
      ↓
修复与复审
      ↓
归档任务与决策
```

规划命令只写任务产物，不做实现。执行命令必须基于已有任务卡。独立 Review 默认只读；需要修改实现时，由用户显式调用 `/fix-review-findings`。`/execute-tasks` 自身已经包含实现授权，因此会在单卡范围内执行 Review、修复和复审闭环。

## 验证命令

```bash
make format       # 只读格式检查
make analyze      # 静态分析
make test         # 包测试
make lint         # 仓库架构门禁
make lint-test    # 仓库架构门禁 Fixture
make hook-test    # pre-commit 暂存区回归测试
make check        # format + analyze + lint + 门禁自测 + test
```

开发过程中优先运行聚焦测试。修改共享 Entity、公共包 API、DI 注册、路由、协议生成或平台 Bridge 时扩大验证范围。

`docs/reviews/test-evidence/` 中的命令日志属于可追溯交付证据，需要随对应任务提交。日志不得包含 Token、环境变量值、签名信息或用户数据。

## 任务生命周期

- 规划产生 `docs/tasks/<task>.md`。
- 执行产生代码与测试证据。
- Review 产生 `docs/reviews/<task>.md`。
- 完成任务移入 `docs/tasks/done/`。
- 长期有效经验可以写入 `.claude/memories/`，任务历史不得写入 Memory。

这些目录由首次使用它们的工作流创建，不预置虚构历史。

## Git Hooks

每个 clone 单独安装：

```bash
make hooks-install
```

pre-commit 检查 staged Dart 文件格式和 Proto 生成同步；pre-push 运行静态分析与仓库 lint。正常开发不得使用 `--no-verify`。

## Marionette MCP

仓库的 `.mcp.json` 通过 `${CLAUDE_PROJECT_DIR}` 定位 `scripts/marionette-server.sh`，启动项目级 Marionette MCP。MCP Server 与 App Binding 都固定为 `0.6.0`，升级时必须同步修改并验证。首次 Clone 后安装：

```bash
make marionette-install
```

Claude Code 首次发现项目级 MCP Server 时需要用户批准。Demo 的 `main.dart` 只在 Debug 模式初始化 `MarionetteBinding` 并收集 `debugPrint` 日志；Profile 和 Release 使用标准 Flutter Binding。

平台壳工程建立后，用 `flutter run` 启动 Demo，并把控制台中的 `ws://.../ws` VM Service URI 提供给 Agent。连接顺序必须是 `connect`、检查或交互、`disconnect`。自定义 UI 组件出现后，再按 Marionette 官方配置补充可交互组件识别、文本提取、Semantics 和日志收集。

## Commit

使用 Conventional Commits，并保持单一作用域：

```text
feat(app_features): 新增个人资料路由
fix(app_core): 修复 token 刷新竞态
docs: 补充 Bridge 版本规则
```
