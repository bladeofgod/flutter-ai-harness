---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-profile-dashboard]
---

# 实现 Shoppe Settings、Profile 与偏好设置

## 背景与输入

- Figma：`0:1460` - `86 Settings`、`0:1358` - `87 Settings Full`、`0:1271` - `88 Settings Profile`、`0:476` - `96 Choose Your Country`、`0:394` - `97 Choose Your Language`、`0:312` - `98 Choose Your Currency`、`0:234` - `99 Sizes Types`、`0:119` - `100 Deleting Account`、`0:51` - `101 About`。
- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- CurrentUserProvider、Auth 根回调、Profile Dashboard 和主导航 Shell。

## 目标与非目标

- 实现 Settings 长页、Profile 编辑、国家/语言/货币/尺码偏好、删除确认和 About，并为后续 Payment/Address 提供 Settings 根导航。
- 所有修改只存在当前进程；删除账号清理当前内存 Auth 并返回 Welcome。
- 本卡不实现节点 89–95 的银行卡、支付历史和地址，也不接系统 Locale、持久化或远程账户。

## 实现要求

1. 重新读取九个节点，确认 86/87 同页关系、88 Profile 字段、96–99 选择方式、100 Overlay 和 101 内容结构。
2. 在 `app_data` 增加 SettingsPreferences、ProfileEditInput 和当前必要枚举；Preference 值使用稳定 ID，不把 UI label 或系统 Locale 对象泄漏到 Domain。
3. 增加 Settings Feature Handler、LocalDataSource、Mapper、稳定请求键和窄 `SettingsApi`，使用进程内 Profile/偏好数据。重建恢复固定默认，不修改系统配置。
4. Settings Controller 通过构造函数接收 `SettingsApi`、只读 CurrentUserProvider 和壳工程提供的窄用户更新/删除回调；不得 import AuthStateCoordinator、UserService 或其他 Feature 私有实现。
5. `86/87` 实现为同一 `/settings` Sliver 长页；建立 `/settings/profile`、Country、Language、Currency、Sizes、About 的最小子 Route，并为 Payment Methods/Addresses 暴露公开目标常量但不创建占位页面。
6. Profile 编辑成功通过根回调调用 `AuthStateCoordinator.updateCurrentUser`，Profile Header 立即更新；Session/User ID 不得改变或出现不一致通知。
7. `100` 是删除确认 Overlay：Cancel 保持登录，Delete 调用根回调清理 Auth 并由现有 Redirect 返回 Welcome；不显示远程删除成功或保留可返回的受认证页面。
8. Country/Language/Currency/Sizes 只更新 App 内显示状态；不切换真实 Locale、不做价格换算。About 使用已登记设计来源和 Demo 版本文本，不虚构法律条款内容。
9. Profile Settings 通过现有 Profile 设置图标局部接线，不重做 `13–14` 布局；表单、列表、Sheet、键盘 Insets、长文案和多视口可达。

## 同批测试与验收

- Data/API/Controller：Profile、偏好、重建恢复、用户更新、删除回调、失败/重试和释放。
- Widget/Route：86–88、96–101 状态合并、入口、Profile 实时更新、Delete Cancel/Confirm、Redirect、Back、键盘和多视口。
- Auth/Profile 回归通过，无系统设置、持久化、远程删除或跨 Feature 私有 import；89–95 不存在占位实现。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不打开系统设置、不切换系统语言、不接 Keychain/Keystore。
- UI 自动化由人工独立安排。
