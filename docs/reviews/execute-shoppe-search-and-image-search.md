---
task: shoppe-search-and-image-search
status: passed
p0: 0
p1: 0
---

# Shoppe 文本搜索与图片搜索执行 Review

## 当前结论

最终独立复审通过，未发现未解决的 P0/P1 问题。Search Domain、Fixture、Local API、Controller、共享图库 Adapter、页面与路由已组成完整链路；首轮发现的公共装配与真实入口缺失已经关闭。

## 已关闭的首轮 P1

1. `app_data` 与 `app_features` 公共 barrel 已导出 Search Domain、API 和 Route 工厂。
2. `FeaturesRegistry.local()` 已把 `SearchFixtureHandler`、`SearchLocalDataSource` 和 `LocalSearchApi` 接入共享 Fixture Transport，并只向调用方暴露窄 `SearchApi`。
3. 根 Router 已注册 `/search`，将其纳入未登录 Redirect，并把搜索商品回调映射到公共 Product Route。
4. Shop Route/Page 通过窄 `onOpenSearch` 回调接线，`shop-search` 已成为真实可点击入口；Demo Router 测试验证登录后从 Shop 打开 Search，未登录 Search Deep Link 返回 Welcome。

## 已验证范围

- Data：文本规范化、固定 Fixture 字段匹配、Typed Catalog Filter、空结果、确定性图片标签与商品、畸形 Payload 映射，以及图片字节和路径不进入 Transport Payload。
- Controller：重复提交、空/错误、筛选草稿 Cancel/Apply、选图取消/失败、识别状态链、重试复用已选字节、编程错误传播和释放后忽略异步结果。
- Widget/Route：文本结果、图片识别与结果、筛选 Overlay、Product ID 委托、系统 Back、键盘 Insets、紧凑/横屏/文字缩放和固定图片预览尺寸。
- 共享媒体：Registration 与 Search 均通过各自窄 Adapter 消费 `shared/media`，Feature 之间没有 import 私有实现；完整 Auth 回归通过。
- 公共装配：Search barrel、Registry、根 `/search`、认证 Redirect、Shop 入口和 Product 回调均已静态复核。

## 验证

- 证据：[`shoppe-search-and-image-search.log`](test-evidence/shoppe-search-and-image-search.log) 中静态分析、Search/Auth、Demo Discovery Router、lint 和 Android Debug APK 均为 Exit 0；iOS no-codesign Build 因本机未安装 Xcode iOS 26.5 Platform 为 Exit 1。
- 独立复跑：上述聚焦测试再次通过；`make harness-check` 与 `git diff --check` 通过。
- 证据命令按 `app_data`、`app_features`、`demo` 分别设置 `TOOL_WORKDIR`，保证 Package Asset Manifest 与宿主路由在正确上下文加载。

## 非阻断风险

- iOS 已保留 `NSPhotoLibraryUsageDescription`，Android Manifest 没有增加相机或媒体读取权限，继续由 `image_picker` 使用系统图库选择能力。当前 iOS 文案仍只描述“选择头像”，尚未覆盖 Search 的图片搜索用途；Demo 不受阻断，但在真实发版前应把用途文案扩展为同时覆盖头像与商品图片搜索，并在 Android/iOS 真机上各验证取消、拒绝、无效图片与成功选择。
- Android Debug APK 已实际构建通过；iOS no-codesign Build 受本机 Xcode 缺少 iOS 26.5 Platform 阻塞，不能用 plist 检查替代。平台宿主编译仍由仓库独立 CI Job 覆盖，本报告不以 Widget Test 代替真机系统 Picker 行为。
- Figma Desktop 执行时未打开包含节点 `0:9375`、`0:9246`、`0:9233`、`0:9221`、`0:9191`、`0:9074`、`0:8870` 的设计文件，无法对七个节点逐像素复核。实现依据已入库设计上下文、任务状态关系、现有 Token 和本地资源完成，不宣称视觉精度已经核对。

## 范围确认

- 图片搜索只返回固定 Demo 标签与结果，没有摄像头、上传、云服务、随机延迟或 ML 依赖。
- 图片字节只保存在当前 Search Flow 内存中，诊断输出已脱敏，不写日志、Evidence 或持久化。
- 未运行 App Operator，也未生成 UI Spec/Audit；UI 自动化继续由人工独立安排。
