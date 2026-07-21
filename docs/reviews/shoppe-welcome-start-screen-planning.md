# Shoppe 欢迎起始页规划审查

## 结论

- P0：0
- P1：0
- P2：0
- 状态：通过；PNG、中立性、Token、测试、锁文件和按钮阶段行为均已确认。

## 问题

### P1：启用按钮的默认行为是无响应，无法形成完整用户行为或可信 Run 证据

- 位置：`docs/figma/shoppe-welcome-start-design-context.md:83`、`docs/tasks/done/shoppe-welcome-start-screen.md:53`、`docs/tasks/done/shoppe-welcome-start-screen.md:59`、`docs/tasks/done/shoppe-welcome-start-screen.md:67`、`docs/tasks/done/shoppe-welcome-start-screen.md:77`
- 影响：两个控件在视觉和 Semantics 上都是可用按钮，但 Demo 默认点击后没有导航、状态变化或其他用户可观察结果。Widget 测试可以证明注入回调被调用，App Operator 却只能证明“点击后没有崩溃且仍在原页”，不能证明导航意图真的传递。任务卡仍要求 UI Spec、Android/iOS Run 和“相同页面行为全部通过”，会产生验收结论高于实际行为的证据。
- 证据：任务明确要求默认处理器“安全消费点击并留在欢迎页”，同时把两个入口描述为可操作行为。目标 Route 又被列为后续范围，当前没有可观察的运行态后置条件。
- 修法：删除默认 no-op 回调。二选一明确任务边界：
  1. 用户提供至少一个真实目标页/Route 后，再把 Welcome 接入根路由并为点击结果生成 UI Spec；或
  2. 先将本卡拆为纯 Welcome 视图实现与视觉验收，不接入可发布根路由、不宣称两个按钮的运行行为已经闭环，后续 Route 任务再完成根路由和交互 Run。

### P1：圆形底座 SVG 含不受支持的 Filter，且任务记录的渲染尺寸会缩小主体

- 位置：`docs/figma/shoppe-welcome-start-design-context.md:21`、`docs/figma/shoppe-welcome-start-design-context.md:63`、`docs/tasks/done/shoppe-welcome-start-screen.md:50`、`docs/tasks/done/shoppe-welcome-start-screen.md:54`
- 影响：按任务卡把节点 `0:12906` 原样交给 `flutter_svg`，阴影无法可靠渲染；如果直接把整个 SVG 设为 `134 x 134`，其中直径 134 的圆位于 `150 x 150` viewBox 内，实际显示直径约 120，而不是 Figma 的 134，品牌标志会明显偏小。
- 证据：MCP 导出的 SVG 使用 `filter`、`feOffset dy="3"` 和 `feGaussianBlur stdDeviation="4"`，viewBox 为 `0 0 150 150`，圆路径直径为 134。`vector_graphics_compiler` 官方功能表明确将 [Filters 列为不支持](https://github.com/flutter/packages/blob/main/packages/vector_graphics_compiler/README.md#features)。Figma MCP 参考代码也通过负 inset 把 150 的视觉范围套在 134 的布局节点外，而不是把整个 SVG 压进 134。
- 修法：不要把底座作为运行时 SVG。用 Flutter 绘制 134 x 134 白色圆形，并根据导出参数实现 `y=3`、Gaussian sigma 4、约 16% 黑色的阴影，再用截图校准 Flutter `BoxShadow`。只保留购物袋为 SVG；入库前把 `var(--fill-0, ...)` 等 Figma 导出语法规范化为固定颜色，并用真实 AssetBundle 解析测试验证。

### P1：任务卡重新引入参考业务包标识，破坏公开模板的中立性

- 位置：`docs/tasks/done/shoppe-welcome-start-screen.md:22`
- 影响：公开 Harness 的新 Demo 任务重新出现 `zk_ui` 标识，使模板携带原工程命名和迁移痕迹；这与仓库已完成的业务去耦目标相冲突，也会诱导执行 Agent 把参考工程当作可复制事实源。
- 证据：该行把 `zk_ui/theme` 和其依赖版本列为正式输入，而 `CLAUDE.md` 要求不得从其他应用复制业务代码、私有依赖或历史任务。当前任务所需的 Theme/Token 边界已经能从本仓库 `docs/architecture.md` 与 Skills 推导，无需保留原包名。
- 修法：删除 `zk_ui` 名称和参考工程依赖来源。Theme/Token 分层只引用本仓库架构；`flutter_svg` 是否采用及版本约束应由当前 SVG 真实消费者、Flutter 3.35.7 兼容性和公开依赖解析结果决定。

### P2：把单节点文字值直接提升为全局 Token，复用语义尚未成立

- 位置：`docs/figma/shoppe-welcome-start-design-context.md:12`、`docs/figma/shoppe-welcome-start-design-context.md:72`、`docs/tasks/done/shoppe-welcome-start-screen.md:47`
- 影响：Figma 节点没有 Variables，当前也只有一个 Feature 消费者。将四个页面文字样式直接写入 `app_ui`，容易把 Welcome 专属尺寸伪装成全局设计系统，后续页面出现不同层级时需要重命名或兼容无效 Token。
- 证据：设计上下文已明确 `get_variable_defs` 返回空；`figma-to-flutter` Skill 只允许把“可复用语义决策”新增为 Token，仓库架构也要求共享代码具有至少两个当前消费者。
- 修法：`app_ui` 先承载确定为全 App 的品牌颜色、字体注册与 Theme。52/19/22/15 等单页样式先留在 Welcome Feature 私有样式中；后续节点确认复用语义后再提升。若坚持现在提升，任务卡必须逐项说明其跨页面语义，而不是仅列原始字号。

### P2：静态页面测试要求无边界 `pumpAndSettle`，会引入不必要的不稳定性

- 位置：`docs/tasks/done/shoppe-welcome-start-screen.md:65`
- 影响：页面若出现持续动画、图片解码或其他未结束调度，`pumpAndSettle` 可能超时；即使当前静态页能通过，也掩盖了测试真正等待的状态。
- 证据：`testing-strategy` Skill 要求优先使用有依据的 `pump` 或状态等待，避免无边界 `pumpAndSettle`。本页没有异步状态，布局和溢出检查不需要 settle 全部调度。
- 修法：使用一次或明确次数的 `pump`，通过 `tester.takeException()`、可滚动元素可达性和几何断言检查溢出；只有资源加载确实需要时才等待对应状态。

### P2：锁文件限制的措辞与项目安全规则不一致

- 位置：`docs/tasks/done/shoppe-welcome-start-screen.md:103`
- 影响：“不修改生成文件或 `pubspec.lock` 以外的受保护锁文件”容易被理解为允许手工编辑 `pubspec.lock`，而项目契约禁止手工编辑依赖锁文件。
- 证据：`CLAUDE.md` 的安全策略明确写明“不手工编辑依赖锁文件”；依赖变化应由 Pub/Bootstrap 确定性更新。
- 修法：改为“不得手工编辑任何锁文件；依赖声明修改后由 `make bootstrap`/Pub 工具更新 Workspace `pubspec.lock`”。

## 验证与证据

- `make harness-check`：通过。
- `git diff --check`：通过。
- Figma MCP：已复核节点 `0:12855`、`0:12906`、`8:4768` 的结构、截图和实际 SVG 内容。
- Flutter 应用测试：未运行；当前只有规划文档，没有应用实现可验证。
- UI Spec/Audit/Run：尚未生成，符合规划阶段状态；P1 修复前不应生成。

## 摘要

设计尺寸、文案、字体、系统栏边界、包职责和响应式方向总体准确。首轮主要问题不在页面视觉数据，而在任务可完成性：不能用 no-op 按钮宣称交互验收完成，也不能把含 Filter 和扩展 viewBox 的 Figma SVG 直接按 134 尺寸交给 `flutter_svg`。当前修复状态见下方复审。

## 复审（2026-07-21）

### 已修复

- 品牌圆形底座、阴影和购物袋改为从 Figma 合成导出透明 `1x/2x/3x` PNG，不再使用含 Filter 的 SVG，也不引入 `flutter_svg`。
- 任务卡已移除 `zk_ui` 等参考业务包标识，只引用当前仓库架构。
- `app_ui` 只承载全 App 品牌颜色、字体注册和 Theme；单节点字号、行高、间距与圆角留在 Welcome Feature，等待第二个消费者再提升。
- 响应式测试改为有界 `pump`、`tester.takeException()` 和几何断言。
- 锁文件规则已明确为不得手工编辑，由 Pub/Bootstrap 工具更新。
- UI 自动化已经从任务流程系统性拆除：任务卡不再声明 `uiSpec`，`execute-tasks` 不生成 Spec/Audit、不调用 App Operator、不以 Run 报告阻断归档。独立流程只在人工显式调用 `/plan-spec`、`/execute-ui-spec` 并指定平台后执行。

### 已解决的按钮边界

- 用户已明确批准先完成页面并启动查看效果，两个按钮本阶段点击后不产生页面变化。任务卡将其记录为有意的阶段边界，不把它宣称为注册/登录流程已经完成；后续拿到对应页面 Figma 节点后再接入真实 Route。

### 复审验证

- `make harness-test`：通过。
- `make spec-test`：通过；验证 ready Spec 可以独立存在、缺少未选择平台 Run 不报错、稳定任务 slug 在任务归档后仍有效、任务目录中的 Spec 和废弃 `task` 字段会被拒绝。
- `make harness-check`：通过。
- `make spec-check`：通过；当前没有真实 UI Spec，按约定跳过。
