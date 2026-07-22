---
executor: task-executor
blockedBy: [shoppe-auth-local-foundation, shoppe-profile-dashboard]
---

# 实现 Shoppe 注册流程与 Welcome 接线

## 背景

Welcome 的 `Let's get started` 已确定为注册入口。Figma `0:12779` 提供头像、Email、8 位 Password、Phone、Done 和 Cancel；用户批准系统图片选择和少量主要国家区号。注册成功必须更新内存 Session/User 并替换导航到 `/profile`。

## 输入

- [`docs/figma/shoppe-auth-flow-design-context.md`](../../figma/shoppe-auth-flow-design-context.md)
- [`docs/figma/shoppe-profile-dashboard-design-context.md`](../../figma/shoppe-profile-dashboard-design-context.md)
- [`docs/tasks/done/shoppe-welcome-start-screen.md`](shoppe-welcome-start-screen.md)
- [`docs/tasks/done/shoppe-auth-local-foundation.md`](shoppe-auth-local-foundation.md) 的 AuthApi、Registry 与 AuthStateCoordinator
- [`docs/tasks/done/shoppe-profile-dashboard.md`](shoppe-profile-dashboard.md) 的根 Redirect 与 `/profile` Route

## 实现要求

1. 使用 Figma Desktop MCP 重新读取 `0:12779` 和截图；在 `feature_auth/` 建立可供后续登录复用的 Auth Bubble 背景、胶囊输入、主按钮、Cancel、头像底座等私有组件，不把 Auth 业务组件放入 `app_ui`。
2. 将 Figma Variables `#F8F8F8`、`#D2D2D2`、`#1F1F1F` 按表单背景、placeholder、strong text 的语义加入 `app_ui`；复用现有主色，不创建近似重复 Token。注册表单字段按 Figma 使用 Poppins Medium 约 13.8：从 Google Fonts 官方仓库或其他可追溯官方来源加入 Poppins `w500` 本地字体、OFL 许可、`AppFonts` 声明和 AssetBundle 测试。
3. 从 Figma 本地化 Bubble、默认头像/相机等必要资源，清除 `var(--fill)` 与 MCP URL。标准眼睛、箭头和相机图标优先使用现有 Icon；资源必须有 AssetBundle 测试。
4. 创建无平台数据依赖的 Registration Controller，通过构造函数接收 `AuthApi` 和窄头像选择抽象，不接收导航或壳工程回调。Controller 管理字段、校验、选中头像、国家、提交中和稳定错误状态，并正确释放输入/Worker；注册成功以 `AuthResult` 状态/返回值交给 Route 装配层处理。
5. 按设计上下文的 Demo 默认执行注册校验：Email、Password、Phone 必填；Email 基本格式有效；Password 恰好 8 位；Phone 为 6 至 15 位数字；头像可选。无姓名字段时从 Email 派生 displayName。这些默认不得写成 Figma 原生校验事实。
6. 国家选择器默认 United Kingdom `+44`，使用底部单选列表提供 United Kingdom、United States、Canada、China、Japan、South Korea、India、Australia、Germany、France。列表使用本地常量、国旗/名称/区号和准确 Semantics，不请求远程数据。
7. 使用 Flutter 官方维护的系统图片选择插件选择图库图片，只读取当前内存预览；Picker 参数限制为 `maxWidth=1024`、`maxHeight=1024`、`imageQuality=85`，读取后最多接受 2 MiB。超限或解码失败显示非敏感字段错误且不替换原头像，用户取消不改变状态。不得把 `XFile`、绝对路径或平台 URI 传入 Domain/API。不支持拍照、裁剪、上传或跨重启持久化。补齐 iOS 必需的 Photo Library 用途说明；Android 采用系统 Picker，不申请宽泛存储权限。
8. `Done` 在提交中禁止重复触发；Route 装配层把成功的 `AuthResult` 交给根回调，根回调仅调用 `AuthStateCoordinator.authenticate`。Coordinator 原子提交匹配的 User/Session 并只发送一次共享通知，由现有 GoRouter Redirect 自动替换到 `/profile`；Controller、Page 和 Auth Route 不再额外 `go('/profile')`。重复 Email 或校验失败保持当前页并呈现字段级错误，不使用随机 Snackbar。
9. `Cancel` 返回 Welcome 并清空表单、图片字节和错误。系统返回键行为与 Cancel 一致，不残留 Controller 或选图状态。
10. 在 `feature_auth/routes.dart` 增加公开 `/auth/register` 常量和 Route 工厂，由根 `createDemoRouter` 装配 `AuthApi`、认证成功与取消回调。`WelcomePage` 继续只接收自身按钮回调；`buildWelcomeRoutes` 把带 `BuildContext` 的 Route 事件交给根 Router，根 Router 将 `onGetStarted` 映射到注册 Route。Feature 之间不得 import 对方 Page/Controller。
11. 从 `DemoApp` 删除 `onGetStarted`、`onSignIn` 及转发 handler；`DemoApp` 只拥有 Registry、`AuthStateCoordinator`、GoRouter、Theme 和生命周期。登录入口在后续阻塞任务接入前可以保持根 Router 内部的明确未实现状态，但不得再通过 `DemoApp` 公共 API 注入 Welcome 行为。
12. 使用 `SafeArea`、单一滚动所有者和键盘 Insets。375 x 812 对齐 Figma；320 x 568、横屏、1.3 倍文字和键盘弹出时 Done/Cancel 可达且无溢出。
13. 不实现登录、密码错误或 Recovery 页面；这些由后续 `shoppe-login-recovery-flow` 复用本卡组件完成。

## 同批测试

- Controller：每项 Demo 默认校验、8 位边界、国家切换、选图取消/成功/超限/解码失败、重复账号、提交去重、成功/失败与释放。
- Widget：Figma 基准尺寸、Poppins 表单文字、表单和 Semantics、密码可见性、国家底部列表、头像预览、键盘 Insets 和多视口无溢出。
- Route：Welcome 开始按钮进入注册；Cancel/系统返回回 Welcome；成功只提交 Coordinator，并由根 Redirect 替换到 `/profile`；断言没有重复 `go`、Redirect loop 或已登录但用户为空/不匹配的中间状态。
- 壳工程：`DemoApp` 构造器不再出现 Welcome 专属回调；根 Router 是 Welcome 目标导航和认证状态提交的唯一装配点。
- Plugin/宿主：图片选择通道使用可替换 Adapter 测试；Android Debug 与 iOS no-codesign Debug Build 验证宿主配置。

## 验收标准

- Welcome 主按钮不再 no-op，注册全流程可使用确定性本地 Auth 完成并进入 Profile。
- 国家与图片选择是可操作控件，未引入摄像头、远程国家接口或持久化。
- 密码和图片数据不写日志、证据或 Semantics；退出流程后状态释放。
- 注册页面与后续 Auth 复用组件内聚在 `feature_auth`；`DemoApp` 不感知 Welcome，根 Router 只做公开 Route、Registry、Coordinator 和导航回调装配。
- 测试、双端 Debug Build、静态分析、lint 和 Harness 检查通过。

## 验证命令

```bash
make bootstrap
make analyze
make lint
make test
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
make harness-check
git diff --check
```

## 平台限制

- iOS 构建需要本机 Xcode 安装目标 iOS Platform；不可用时必须准确记录，不得把 plist 校验等同于完整构建。
- 正式 Release 权限文案、签名和商店隐私声明不属于 Demo 任务，但不得提交签名材料。

## 后续规则调整

[`demo-stateless-auth-policy`](demo-stateless-auth-policy.md) 已将当前本地注册改为无状态：Fixture 不再产生重复 Email 失败，但 Controller 对 `duplicateAccount` 的稳定映射仍保留给未来真实 API。注册选择的头像必须随当次 `AuthResult` 进入 `AuthStateCoordinator`，并在当前会话的 Profile 展示；重启后不保存。
