---
executor: task-executor
blockedBy: [shoppe-auth-local-foundation, shoppe-profile-dashboard, shoppe-registration-flow]
---

# 实现 Shoppe 登录、错误密码与 Recovery UI

## 背景

Welcome 的 `I already have an account` 已确定为登录入口。登录是 Email 账号识别与 8 位密码输入两步流程；Figma 同时提供输入中、错误密码和 Password Recovery 页面。用户要求 Recovery 只实现可到达 UI，不发送 SMS/Email 或继续下一步。

## 输入

- [`docs/figma/shoppe-auth-flow-design-context.md`](../../figma/shoppe-auth-flow-design-context.md)
- [`docs/figma/shoppe-profile-dashboard-design-context.md`](../../figma/shoppe-profile-dashboard-design-context.md)
- [`docs/tasks/done/shoppe-auth-local-foundation.md`](shoppe-auth-local-foundation.md) 的 Fixture Auth API 与 Service
- [`docs/tasks/done/shoppe-registration-flow.md`](shoppe-registration-flow.md) 建立的 Auth 私有组件、资源和 Route 结构
- [`docs/tasks/done/shoppe-profile-dashboard.md`](shoppe-profile-dashboard.md) 的根 Redirect 与 `/profile` Route

## 实现要求

1. 使用 Figma Desktop MCP 重新读取 `0:12718`、`0:12584`、`0:12518`、`0:12449` 和对应截图。输入中/错误密码是同一密码页面的状态，不创建两个 Route。
2. 创建 Login Controller，通过构造函数只接收 `AuthApi`，不接收导航或壳工程回调。Controller 管理 Email 查询、已识别 User、8 位密码、提交中和错误状态，不读取 AuthService/UserService；登录成功以 `AuthResult` 状态/返回值交给 Route 装配层。Controller 由单一 `LoginFlowScope`（`ShellRoute` 或等价父级装配 Scope）持有，在 Login/Password/Recovery 子 Route 间复用，只在离开整个登录流程时销毁并清除 Secret、订阅和输入状态。
3. `/auth/login` 显示 Email、Next、Cancel。有效 Fixture Email 才进入密码步骤；未知账号或格式错误停留本页并显示字段错误。Next 提交中禁止重复点击。
4. `/auth/password` 使用查询返回的 UserEntity 展示头像和 `Hello, <name>!!`。密码输入使用真实不可见 `TextField`/EditableText 与 8 个视觉圆点，不能用 8 个独立文本框或绘制系统键盘。
5. 密码必须恰好 8 位；按设计上下文的 Demo 默认，输入满 8 位或键盘 `Go` 时提交。Route 装配层把正确结果交给根回调，根回调仅调用 `AuthStateCoordinator.authenticate`；Coordinator 发送一致状态通知后，由现有根 Redirect 自动进入 `/profile`，Controller、Page 和 Auth Route 不额外 `go('/profile')`。错误清除真实输入，显示 8 个 `#EC4E4E` 红点和 `Forgot your password?`，下一次输入恢复普通圆点。
6. 密码不得出现在 Semantics value、日志、异常、测试名称或证据输出；圆点使用统一的“已输入 N/8 位”无敏感 Semantics 描述。
7. 点击 `Forgot your password?` 进入 `/auth/recovery`。页面允许在 SMS/Email 间切换并保持 Figma 默认 SMS；`Next` 只消费点击并停留当前页，不调用 AuthApi、不启动计时器、不生成验证码或成功提示。
8. Recovery `Cancel` 返回密码页并保留已识别用户但不保留密码；Login `Cancel` 和从 Email 步骤系统返回都回 Welcome 并清空流程。密码页返回 Email 步骤时保留 Email 便于修改。
9. 在 `feature_auth/routes.dart` 汇总 login/password/recovery Route，并使用稳定父级 Key 保持同一 `LoginFlowScope`；子 Route 不得各自创建 Controller。根 `createDemoRouter` 把 Welcome 次操作映射到公开 `/auth/login` Route，并向 Auth Route 工厂提供认证成功/取消回调；`DemoApp` 不增加 Welcome 或 Auth 专属参数。不得从 Welcome 或 Profile import Auth 内部页面。
10. 复用 Registration 任务的 Bubble、输入、按钮、Cancel 和头像组件；Password Dot 与 Recovery Choice 仅在至少两个状态消费时形成 Feature 私有组件。
11. 页面使用 `SafeArea`、键盘 Insets 和有界滚动。375 x 812 对齐 Figma，短屏/横屏/1.3 倍文字下用户头像、圆点、错误链接和操作均可达，无布局跳动。
12. App 冷启动保持未登录；登录后直接访问 Auth Route 时由根 Redirect 转到 `/profile`。未登录且缺少已识别 User 的 direct `/auth/password` 或 `/auth/recovery` 同步回到 `/auth/login`，不能渲染空头像/用户名或创建伪状态。Redirect 纯同步且不触发 AuthApi。

## 同批测试

- Controller/Scope：Email 格式、存在/未知账号、提交去重、密码 7/8/9 位边界、正确登录、错误恢复、跨子 Route 保持状态、离开整个流程后清除 Secret/监听和释放。
- Widget：四个 Figma 状态、动态用户名/头像、8 点输入、红色错误、Recovery 单选、密码 Semantics 脱敏、键盘 Insets 与多视口无溢出。
- Route：Welcome 次操作进入 Login；Email -> Password；Forgot -> Recovery；缺少已识别 User 时 direct Password/Recovery 回 Login；各级 Cancel/Back；成功只提交 Coordinator 并由根 Redirect 替换到 Profile；已登录 Auth Redirect；验证无重复导航且 Scope 不重复创建。
- Service 协作：成功时 Coordinator 只发布一次已登录且 User/Session 匹配的状态，失败时二者均不改变；监听通知序列并证明没有可观察的不一致中间状态。
- 回归：Welcome、Registration 与 Profile 测试继续通过，Recovery Next 明确无业务副作用。

## 验收标准

- Welcome 两个入口分别形成注册和登录可执行流程；正确登录/注册都进入同一 Profile Route。
- 输入中、错误和 Recovery 状态与 Figma 一致，系统键盘由平台提供，8 位密码全链路不泄漏。
- Recovery 只实现用户批准的 UI 范围，没有伪造短信、邮件、验证码或成功结果。
- 页面/Controller 只依赖 AuthApi 与 Domain 类型；`DemoApp` 不感知 Welcome/Auth 行为，根 Router 独占 Route 装配，`AuthStateCoordinator` 独占 Session/User 更新。
- 聚焦测试、完整 Demo 测试、静态分析、边界 lint 和 Harness 检查通过。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
make harness-check
git diff --check
```

## 后续边界

- Recovery 的验证码、重置密码和发送渠道需要新的产品规则与 Figma 节点后另立任务。
- Profile 内其他导航和业务卡片不属于 Auth 流程。
- UI Spec/Audit/App Operator 仍由人工独立安排，不随本任务自动执行。

## 后续规则调整

[`demo-stateless-auth-policy`](demo-stateless-auth-policy.md) 已覆盖本卡第 3、5 条的本地 Fixture 前提：Email 步骤接受任意格式有效的 Email 并生成确定性用户；`00000000` 固定进入错误密码与 Recovery 演示，其他恰好 8 位密码成功。格式错误、异步失败和未来真实 API 的账号不存在状态仍由原 Controller 契约处理。
