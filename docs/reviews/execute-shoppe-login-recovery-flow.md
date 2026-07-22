---
task: shoppe-login-recovery-flow
status: passed
p0: 0
p1: 0
---

# Shoppe 登录与 Recovery 流程执行审查

## P1：后续步骤 Guard 验证的是 Route marker，不是真实 Scope 状态

- 位置：[`app/packages/app_features/lib/feature_auth/routes.dart:85`](../../app/packages/app_features/lib/feature_auth/routes.dart#L85)、[`app/packages/app_features/lib/feature_auth/pages/login_password_page.dart:50`](../../app/packages/app_features/lib/feature_auth/pages/login_password_page.dart#L50)、[`app/packages/app_features/lib/feature_auth/pages/password_recovery_page.dart:35`](../../app/packages/app_features/lib/feature_auth/pages/password_recovery_page.dart#L35)
- 问题：`/auth/password` 与 `/auth/recovery` 的同步 Redirect 只判断 `state.extra is _LoginFlowAccess`。marker 中的 `userId` 从未读取，Redirect 也不验证当前 `LoginFlowScope` 的 `recognizedUser`。只要一个旧 marker 与新建或已丢失状态的 Scope 脱节，Guard 就会放行；两个页面随后发现 `recognizedUser == null`，只返回 `SizedBox.shrink()`，用户得到空白页而不是同步回到 Login。现有 direct-link 测试只覆盖“完全没有 extra”，因此无法证明任务卡要求的“缺少已识别 User”分支。
- 影响：浏览器/Router 历史恢复、Route 状态复用或后续代码误传旧 marker 时，未认证用户可以进入没有真实账号上下文的后续步骤；虽然不会调用 AuthApi，但会违反同步 Guard 和“不渲染空头像/用户名或创建伪状态”的验收标准。
- 修法：让 Redirect 依赖一个与 `LoginFlowScope` 同生命周期、离开流程即清空的同步状态持有者，并校验 `recognizedUser.id == access.userId`；或者把后续步骤建模为只能由持有已识别 User 的稳定父级状态生成的嵌套路由。页面中的 `SizedBox.shrink()` 只能作为防御兜底，不能替代 Redirect。增加测试：构造 marker 存在但 Scope 没有 User、marker userId 不匹配、Scope 离开后旧 marker 返回三种情况，均应同步落到 `/auth/login`，且 AuthApi 调用数保持 0。

## P2：密码圆点的无障碍节点不可操作

- 位置：[`app/packages/app_features/lib/feature_auth/widgets/login_flow_components.dart:192`](../../app/packages/app_features/lib/feature_auth/widgets/login_flow_components.dart#L192)、[`app/packages/app_features/lib/feature_auth/pages/login_password_page.dart:78`](../../app/packages/app_features/lib/feature_auth/pages/login_password_page.dart#L78)、[`app/packages/app_features/test/feature_auth/login_pages_test.dart:82`](../../app/packages/app_features/test/feature_auth/login_pages_test.dart#L82)
- 问题：可见圆点使用 `Semantics(textField: true, label: ...)`，内部 `InkWell` 又被 `ExcludeSemantics` 排除；父级 Semantics 没有 `onTap` 或其他输入动作。读屏能听到安全的已输入位数，但无法通过该节点请求隐藏 TextField 的焦点。测试只断言标签和隐藏输入没有 Semantics value，没有断言圆点节点包含可操作 action。
- 影响：普通触摸用户可以点击 `InkWell` 聚焦，辅助技术用户却可能无法重新聚焦密码输入；隐私脱敏正确，但交互语义不完整。
- 修法：在外层 `Semantics` 显式提供 `onTap: onPressed` 和准确 hint，继续排除隐藏 TextField 的 value；测试断言圆点节点包含 tap action，执行该 action 后 `passwordFocusNode.hasFocus` 为 true，同时明文仍不出现在语义树。

## 已确认边界

- `ShellRoute` 使用稳定父级 Key 持有单一 `LoginFlowScope`；测试确认 Email、Password、Recovery 三个 Route 共享同一 Controller，返回子步骤时 Scope 不关闭，离开整个流程后 Controller、输入与密码均释放。
- `BackButtonListener` 返回 `true` 消费 Router 平台返回，`PopScope(canPop: false)` 处理 Navigator/手势返回；现有系统返回测试没有出现 Login Cancel 重复回调。Password 返回保留 Email，Recovery Cancel 保留 User 且清空密码。
- Email 格式、账号存在性、查询去重、7/8/9 位边界、满 8 位自动提交和键盘 Go 都由同一 Controller/隐藏 TextField 路径处理；错误凭据清空真实输入并显示 8 个 `#EC4E4E` 红点，下一次输入恢复普通状态。
- 隐藏 TextField 被 `ExcludeSemantics` 包裹，圆点只暴露“已输入 N/8 位”；Controller、Domain 诊断和测试证据未输出密码。预期 `AuthFailure` 被映射，未声明的编程错误继续传播且 pending 状态由 `finally` 恢复。
- Recovery Next 是空消费方法；页面和 Route 测试共同证明点击后仍停留 Recovery，AuthApi 计数不变，没有验证码、计时器、提示或后续导航。
- 根 Router 只把成功 `AuthResult` 交给 `AuthStateCoordinator.authenticate`，没有 Auth 页面级 `go('/profile')`；Demo 回归测试确认 Coordinator 只通知一次，再由根 Redirect 进入 Profile。
- Controller 只依赖 `AuthApi`，壳工程仅通过 `app_features` 公共 Route 工厂装配；未发现 Feature 内部实现泄漏到 Demo、跨 Feature import 或 GetX 路由/Overlay 使用。

## Figma 与布局

- Email 标题、输入和 Next，Password 头像/标题/8 点，以及 Recovery 文案与单选结构均有 375 x 812 基准断言；非零键盘 Insets、320 x 568、横屏和 1.3 倍文字测试均通过，目标控件可滚动到键盘上方。
- 根据任务卡第 10 条，三个页面复用了注册任务的 `registration_bubbles.svg`。这意味着 Login 设计独有的右侧/下半部 Bubble，以及 Password/Recovery 的具体装饰构图没有逐节点本地化；当前属于任务输入明确接受的资产复用降级，不影响流程正确性，但不能宣称像素级还原四张 Figma 状态。
- Password/Recovery 的测试验证关键组件和可达性，没有对所有 Figma 坐标或截图做像素比较；后续若要求视觉一比一，应单独本地化各节点装饰资源并增加截图对比，而不是改变当前 Auth 状态边界。

## 验证与缺口

- 已读取：[`test-evidence/shoppe-login-recovery-flow.log`](test-evidence/shoppe-login-recovery-flow.log)。Auth 聚焦测试最终 17 个通过；修复两次静态分析问题后，最终 `make analyze` 退出 0；`make test`、`make lint`、`make harness-check` 和 `git diff --check` 均退出 0。
- 本任务没有原生宿主文件变化，任务卡也未要求双端 Build；本轮未运行真机返回手势或系统键盘交互，`BackButtonListener` 与 `PopScope` 的平台差异仍由 Widget 测试和静态结构覆盖。
- UI Spec、Audit 与 App Operator 未运行，符合人工独立安排边界。

## 待确认问题

- 无。P1 可在现有 Route/Scope 范围内修复，不需要新增产品规则、远程 API 或 Recovery 业务。

## 摘要

- P0：0
- P1：1
- P2：1
- 状态：需要修复后复审，当前不应归档任务卡。

## 第二轮独立复审

- P0：0
- P1：0
- P2：0
- 状态：通过，可以归档。

首轮 P1 与 P2 均已关闭：

- `buildLoginRoutes` 现在持有仅覆盖当前 Shell 生命周期的 `activeController`。`LoginFlowScope` 在 `initState` attach Controller，在 `dispose` 先按实例身份 detach 并清空引用、再 `onDelete()`；Password/Recovery 的同步 Redirect 同时要求 marker 类型正确、活动 Controller 存在、`recognizedUser` 存在且 `recognizedUser.id == marker.userId`。页面的空 Widget 只保留为不可达的防御兜底，不再承担 Guard 职责。
- Route 测试从正常流程取得真实 marker，并分别构造“marker 存在但 User 已清空”“当前 User 与 marker ID 不匹配”“Scope 已离开后复用旧 marker”三种情况；全部同步回到 `/auth/login`，前后 AuthApi 查询/登录计数不变，旧 Controller 已关闭，新 Scope 没有伪造 User。
- `PasswordDots` 的脱敏 Semantics 已增加明确 hint 和 `onTap` action。Widget 测试确认隐藏 TextField 不具有 text-field 语义且 value 为空，再通过真实 `performSemanticsAction(tap)` 触发圆点节点，验证同一 Scope 的 `passwordFocusNode` 获得焦点；明文仍由 `ExcludeSemantics` 隔离。

复审读取了追加后的 [`test-evidence/shoppe-login-recovery-flow.log`](test-evidence/shoppe-login-recovery-flow.log)：Auth 聚焦测试由 17 个增加到 18 个并全部通过；修复中一次静态分析失败已由最终 `make analyze` 退出 0 覆盖；最终 `make test`、`make lint`、`make harness-check` 与 `git diff --check` 均退出 0。未发现新的导航、生命周期、隐私、Recovery 副作用或包边界问题。

首轮记录的 Figma Bubble 复用降级和真机返回手势/系统键盘验证缺口仍然成立，但不阻断当前任务归档。
