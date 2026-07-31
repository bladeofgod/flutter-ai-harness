---
task: shoppe-camera-search-media-capture
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - app/packages/app_features/lib/api/search_image_picker.dart
  - app/packages/app_features/lib/feature_search/api/native_search_camera_media_picker.dart
  - app/packages/app_features/lib/feature_search/api/shared_media_search_image_picker.dart
  - app/packages/app_features/lib/feature_search/controllers/search_controller.dart
  - app/packages/app_features/lib/feature_search/pages/search_page.dart
  - app/packages/app_features/lib/feature_search/routes.dart
  - app/packages/app_features/lib/feature_categories/pages/categories_page.dart
  - app/packages/app_features/lib/feature_categories/routes.dart
  - app/packages/app_features/lib/features_registry.dart
  - app/packages/app_features/lib/app_features.dart
  - app/packages/app_features/pubspec.yaml
  - app/apps/demo/lib/router/demo_router.dart
implementationDigest: 688b134e4c460441150fc140be6e1b0f89db004e99e10fbc3cbb856de4414b43
---

# Security Review: Search 图片来源选择

## 结论

最终 P0 0、P1 0、P2 0。独立 Security Review 首轮发现的跨用户 session 清理竞态与 Registry dispose
重试问题均已关闭。

## 已关闭问题

- Picker 使用 session generation 隔离注销前后的拍摄；`clearDrafts()` 先使旧 generation 失效，等待进行
  中的 capture 收敛，再重试全部 retained lease。清理进行中拒绝新拍摄，清理后仍有旧 lease 时也不会
  调用新的 `presentCaptureFlow()`。
- 晚到 confirmed media 只能进入 release/retain，不会作为新会话的 Search 图片返回。测试固定“pending
  capture → logout → late confirm → 首次 release 失败 → cleanup 重试”的顺序。
- Registry aggregate dispose 只缓存当前调用；失败时清空 Future，允许下层 Picker 在后续 dispose 中重试。
- reset 清理失败只上报稳定脱敏异常，同时保留原始 StackTrace 供本地诊断，不传播底层错误文本。
- Controller 替换和关闭图片时主动擦除持有的 byte copy；Native Adapter 返回防御性副本后擦除临时 bytes。

## 已确认边界

- 原生配置固定 photo-only、rear camera、`audioEnabled: false`，不主动申请视频或麦克风能力。
- Flutter Controller/Page 不接触 native handle、路径、URI、Wire Map 或 `PlatformException`。
- thumbnail 只接受 bounded JPEG，并在 release 成功后才返回 Search；失败路径使用稳定枚举和脱敏异常。
- Search 不再接受自动拍摄 query intent；只有用户在来源弹窗明确选择拍摄后才进入 photo-only 原生流程，
  未登录 `/search` 仍由全局 redirect 拦截。
- 没有上传、持久化、日志输出图片内容，也没有扩大 Agent、CI、依赖源或发布权限。

## 验证与剩余风险

最终 evidence 中相关测试、全量测试、format、analyze、lint、Harness 和 diff 检查均通过。按用户要求未做
本轮真机调试，因此平台实际权限行为、物理媒体删除和真实 thumbnail 回传仍属于运行验证范围。

## 当前实现复审

独立只读复审确认 Search 仍只在用户从来源弹窗明确选择拍摄后启动流程，只消费有 JPEG、content type、
尺寸和 byte 上限校验的缩略图，并在成功与失败路径释放 lease 和清理临时 bytes。当前实现未发现 P0、
P1 或 P2，摘要可同步到当前文件集合。真机权限弹窗、Camera UI 与系统相册仍需运行验证。

## 当前文件摘要复核

独立安全复审确认本任务 implementationFiles 未被 V4 Harness 修复改写，Search 仍只消费受限 JPEG
thumbnail copy。当前实现 `P0=0`、`P1=0`、`P2=0`；摘要按当前文件集合重算。
