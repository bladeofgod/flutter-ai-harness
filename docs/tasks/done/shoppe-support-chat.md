---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-checkout-payment-flow, shoppe-profile-dashboard]
---

# 实现 Shoppe 本地客服 Chat 与服务评价

## 背景与输入

- Figma：`0:3542` - `68 Chat Starting Question 1`、`0:3456` - `69 Chat Starting Question 2`、`0:3341` - `70 Chat Starting Question 3`、`0:3238` - `71 Chat Connecting With an Agent`、`0:3140` - `72 Chat Agent is Typing`、`0:3036` - `73 Chat Hello`、`0:2930` - `74 Chat Response`、`0:2805` - `75 Chat Voucher`、`0:2695` - `76 Chat Messaging 1`、`0:2501` - `77 Chat Messaging 2`、`0:2598` - `78 Chat Go To The Bottom`、`0:2400` - `79 Chat Messaging 3`、`0:2280` - `80 Rate Our Service`。
- [`docs/figma/shoppe-main-app-design-context.md`](../../figma/shoppe-main-app-design-context.md)
- Profile Chat 入口与主导航 Shell。

## 目标与非目标

- 实现一条本地脚本式客服会话：问题选择、连接、Typing、消息、Voucher 卡片、滚动到底部和服务评价。
- 本卡不连接客服、网络、AI、Push、WebSocket 或真实 IM；不为了展示强行实现 `app_im` Engine。
- 十三张画板是同一会话状态机，不建立十三个 Route。

## 实现要求

1. 重新读取十三节点，确认问题选项、连接/Typing 状态、消息方向、输入栏、Voucher、自动滚动条件和评价页面关系。
2. 在 `app_data` 定义 SupportConversation、SupportMessage、Participant、MessageContent Variant、SuggestedQuestion 和 ServiceRating 当前必要字段；Voucher 内容复用公共 Voucher Domain（存在时），不复制优惠券模型。
3. 增加 Support LocalDataSource、Mapper、稳定请求键和窄 `SupportChatApi`。脚本步骤由显式用户动作推进，不使用随机或无限 Timer；可使用可注入短延迟只服务确定性 UI 转场测试。
4. 单一 Support Chat Controller 管理 starting/connecting/typing/active/rating 状态、消息列表、输入、发送去重、滚动请求和释放。输入内容不写日志或证据。
5. 建立 `/support` 会话 Route 和必要的 Rating 子状态/Route；68–79 在同一 Scope 内切换，离开会话清理草稿和待执行转场。
6. 发送用户消息后只按固定脚本产生定义好的回复；Voucher 卡片只展示/跳转已有本地 Voucher 页面，不声称真实发放。
7. 消息列表使用反向或锚定滚动的惰性列表，78 的“到底部”行为可重复且不因键盘 Insets 跳动；长消息、文字放大和旋转可达。
8. Profile Chat 图标通过公开 Route 接线；Support Feature 不 import Profile 私有 Widget/Controller。`app_im` 保持基础设施占位，未来真实 IM 另立契约任务。

## 同批测试与验收

- API/Controller：脚本顺序、问题选择、连接/Typing、发送、Voucher、评价、重复操作、取消转场和释放。
- Widget/Route：68–80 状态合并、消息方向、键盘、滚动到底部、Profile 入口、Back、多视口与 Semantics。
- 无网络、AI、WebSocket、真实客服或 app_im 伪实现；所有可见状态由确定性本地动作驱动。

## 验证命令

```bash
make analyze
make lint
make test
make harness-check
git diff --check
```

## 平台限制

- 不申请通知、麦克风、相机或后台连接权限。
- UI 自动化由人工独立安排。
