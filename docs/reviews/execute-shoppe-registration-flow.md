---
task: shoppe-registration-flow
status: passed
p0: 0
p1: 0
---

# Shoppe 注册流程执行审查

## P1：Route 重建会构造并遗弃额外的 RegistrationController

- 位置：[`app/packages/app_features/lib/feature_auth/routes.dart:19`](../../app/packages/app_features/lib/feature_auth/routes.dart#L19)、[`app/packages/app_features/lib/feature_auth/pages/registration_page.dart:54`](../../app/packages/app_features/lib/feature_auth/pages/registration_page.dart#L54)
- 问题：`GoRoute.builder` 每次执行都会先构造一个新的 `RegistrationController` 并传给 `RegistrationPage`。但页面中的本地 `GetBuilder/Binder` 元素在普通 Widget 重建时继续持有首次启动的 Controller；它的更新条件不包含新的 `init` 实例。后续 builder 产生的 Controller 因而既不会 `onStart()`，也不会进入当前 `dispose` 回调，内部三个 `TextEditingController` 无法释放。
- 影响：MediaQuery、Theme、Router refresh 等父级重建都可能积累未释放的页面状态；这违反任务卡“Controller 随 Route 创建和销毁”及 GetX fork“每个 Route 只创建一次”的生命周期约束。现有测试只验证首次渲染和离开，没有触发同 Route 重建并统计创建/释放次数，因此无法发现该泄漏。
- 修法：让 Route 返回一个稳定的 Route scope，由该 scope 的 `State.initState/dispose` 创建并删除 Controller；或直接在 Route 使用 fork 的本地 `Binder.create`，把构造延迟到 Binder 元素首次取值，并由同一元素负责 `onDelete()`。不要在每次 `GoRoute.builder` 调用时直接 `new RegistrationController`。增加测试：同 Route 父级重建后 Controller 身份不变、只创建一次，离开/系统返回/认证 Redirect 后恰好关闭一次且输入与头像字节不可再保留。

## P1：Controller 的宽 `on Object` 会把编程错误伪装成可恢复失败

- 位置：[`app/packages/app_features/lib/feature_auth/controllers/registration_controller.dart:101`](../../app/packages/app_features/lib/feature_auth/controllers/registration_controller.dart#L101)、[`app/packages/app_features/lib/feature_auth/controllers/registration_controller.dart:153`](../../app/packages/app_features/lib/feature_auth/controllers/registration_controller.dart#L153)
- 问题：头像 Adapter 已经把预期的平台、权限、读取和解码故障收敛为 `RegistrationAvatarPickFailed`，但 Controller 又捕获任意 `Object` 并映射为 `pickerUnavailable`；注册提交同样在处理声明的 `AuthFailure` 后捕获任意 `Object` 并显示通用失败。`StateError`、`AssertionError`、`NoSuchMethodError` 等实现缺陷都会被静默吞掉。头像 Adapter 自身已有“programming Errors 不应被捕获”的测试，这个契约却在上一层被抵消。
- 影响：开发阶段的真实缺陷会表现为普通字段错误，测试和日志失去原始异常及调用栈；这与仓库已有 ApiClient/Mapper 的窄异常边界不一致，也会让注册问题难以定位。
- 修法：`pickAvatar` 只消费 Adapter 返回的 sealed result，不再宽捕获；如接口需要声明额外可恢复异常，应增加窄、稳定的异常类型并只捕获该类型。`submit` 只处理 `AuthFailure` 等 AuthApi 明确声明的业务失败，未声明的编程错误继续抛出。增加 Controller 测试，证明预期失败仍映射为稳定 UI 状态，而裸 `StateError`/`Error` 不会被隐藏。

## P1：关键验收测试没有覆盖真实键盘、头像预览和 Route 释放

- 位置：[`app/packages/app_features/test/feature_auth/registration_page_test.dart:13`](../../app/packages/app_features/test/feature_auth/registration_page_test.dart#L13)、[`app/packages/app_features/test/feature_auth/registration_page_test.dart:142`](../../app/packages/app_features/test/feature_auth/registration_page_test.dart#L142)、[`app/packages/app_features/test/feature_auth/registration_controller_test.dart:150`](../../app/packages/app_features/test/feature_auth/registration_controller_test.dart#L150)、[`docs/tasks/done/shoppe-registration-flow.md:58`](../tasks/done/shoppe-registration-flow.md#L58)
- 问题：多视口测试只改变窗口尺寸和文字倍率，没有设置非零 `viewInsets.bottom`，因此没有验证键盘弹出后 Done/Cancel 可滚动到达；Widget 测试没有用内存图片驱动头像预览，也没有断言错误选择保持原头像；路由测试没有验证 Controller 在 Cancel、系统返回和认证 Redirect 后释放。Auth 图片资源也只被页面间接消费，没有任务卡明确要求的直接 AssetBundle/解码断言。
- 影响：当前全绿测试不能证明任务卡要求的键盘 Insets、头像交互和生命周期释放。尤其 Controller 的真实 Route 泄漏已经说明现有测试会漏过关键回归。
- 修法：为页面提供可测试的 Controller/Picker 依赖入口；用有效内存图片覆盖成功预览、取消及失败保留；设置真实 `viewInsets.bottom` 并分别在 320 x 568、横屏和 1.3 倍文字下滚动到主操作；补充 Route scope 的创建/关闭计数；直接加载并解码 `registration_bubbles.svg`、默认头像和 UK 国旗，检查资源无 MCP URL/路径泄漏。

## 已确认边界

- Welcome 主按钮由根 Router 映射到 `/auth/register`；成功回调只调用 `AuthStateCoordinator.authenticate`，现有 GoRouter refresh/Redirect 进入 `/profile`，未发现 Controller、Page 或 Auth Route 的第二次 `go('/profile')`。
- `AuthResult` 在 Domain 构造时保证 User/Session ID 匹配；路由测试断言认证只通知一次并最终进入 Profile。
- Picker 固定使用 Gallery、1024 x 1024、质量 85、`requestFullMetadata: false` 和 2 MiB 上限；结果只暴露防御性复制的内存字节，诊断字符串不包含文件名、路径或字节。
- Android Manifest 没有 Camera 或宽泛存储权限；iOS `Info.plist` 已提供 `NSPhotoLibraryUsageDescription`。
- Demo 壳只通过 `app_features` 公共入口使用 Registry 和 Route 工厂；未发现壳工程 import Feature 内部实现、跨 Feature 内部 import 或平台类型泄漏到 Domain/API。
- Figma Bubble、默认头像、UK 国旗和 Poppins/OFL 已本地化；静态扫描未发现 `localhost`、远程 URL、绝对路径或 `var(--fill)`。

## 验证与缺口

- 已读取：[`test-evidence/shoppe-registration-flow.log`](test-evidence/shoppe-registration-flow.log)。最终 `make analyze`、`make test`、`make lint`、Android Debug Build、`make harness-check` 和 `git diff --check` 均退出 0；证据中早期测试失败已由后续同命令全量通过覆盖，并未作为当前失败计数。
- iOS no-codesign Debug Build 未完成：本机 Xcode 缺少 iOS 26.5 Platform，目标设备和 generic iOS destination 均不可用。这是平台验证缺口，不是当前代码构建失败；安装对应 Platform 后仍需重跑完整 iOS Build。
- 本轮未运行 App Operator 或 UI Spec；它们不属于普通任务执行和审查门禁。

## 待确认问题

- 无。三个 P1 均可在现有任务范围内修复，不需要扩大产品或平台权限范围。

## 摘要

- P0：0
- P1：3
- 状态：需要修复后复审，当前不应归档任务卡。

## 第二轮独立复审

- P0：0
- P1：0
- P2：0
- 状态：通过，可以归档。

首轮三个 P1 均已关闭：

- `RegistrationPage` 现在接收惰性的 `createController`，仅在 Route scope 的 `State.initState` 创建一次 Controller，并在同一 State 的 `dispose` 中调用一次 `onDelete()`。Route builder 或父级重建只替换工厂闭包，不再提前创建并遗弃实例。新增生命周期测试真实触发同 Route 父级重建，并分别验证普通离开、Cancel、系统返回和认证转换后只关闭一次；关闭后输入被清空、头像字节释放且 `TextEditingController` 已不可重新监听。
- `pickAvatar` 已移除宽捕获，只在 `finally` 恢复 picking 状态；`submit` 只映射声明的 `AuthFailure`，同样在 `finally` 恢复 submitting 状态。新增测试分别注入 Picker `StateError` 与 AuthApi `AssertionError`，确认原异常对象继续传播、加载状态恢复且没有伪造字段或表单错误。
- 页面测试现在向三个受限布局写入非零 `viewInsets.bottom`，断言真实 Insets 生效，并验证 Cancel 可滚动到键盘上方；独立头像 Widget 测试验证内存图片使用 `MemoryImage`、语义切换和 loading 禁用态，Controller 测试继续覆盖取消/超限/无效图片保持原头像；资源测试直接加载、解析 SVG 并解码两张 PNG，同时检查 MCP URL、绝对路径和 `var(--fill)` 不存在。

复审读取了追加后的 [`test-evidence/shoppe-registration-flow.log`](test-evidence/shoppe-registration-flow.log)：Auth 聚焦测试、`make analyze`、最终 `make test`、`make lint`、Android Debug Build、`make harness-check` 和 `git diff --check` 均退出 0。成功路径仍只向 `AuthStateCoordinator.authenticate` 提交一次，由 GoRouter Redirect 进入 `/profile`，未发现新的生命周期、包边界、隐私或导航问题。

iOS no-codesign Debug Build 仍未完成，因为本机 Xcode 缺少 iOS 26.5 Platform；这是保留的平台验证缺口，不是代码失败。安装对应 Platform 后仍需重跑完整 iOS Build。
