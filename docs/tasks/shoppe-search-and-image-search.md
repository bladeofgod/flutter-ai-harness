---
executor: task-executor
blockedBy: [shoppe-main-navigation-shell, shoppe-shop-home-catalog, shoppe-product-details-reviews]
---

# 实现 Shoppe 文本搜索与图片搜索 Demo

## 背景与输入

- Figma：`0:9375` - `28 Search`、`0:9246` - `29 Search Results`、`0:9233` - `30 Image Search`、`0:9221` - `31 Recognizing Image`、`0:9191` - `32 Image Recognized`、`0:9074` - `33 Image Search Results`、`0:8870` - `34 Filter`。
- [`docs/figma/shoppe-main-app-design-context.md`](../figma/shoppe-main-app-design-context.md)
- Catalog/Product Route 与现有注册头像图库 Picker 能力。

## 目标与非目标

- 实现文本搜索、结果、筛选以及使用系统图库的确定性图片搜索状态链。
- 图片搜索只演示 Figma 交互，不接摄像头、上传、云服务或 ML 模型。
- 本卡不改变 Catalog Fixture 内容，不保存搜索历史到磁盘。对 `01–12` 的唯一允许改动是迁移图库选择的非 UI 共享能力；Auth 页面、Controller、Route、文案和行为不得重做。

## 实现要求

1. 重新读取七个节点，确认 Search 输入、结果列表、Image Search 入口、31/32 状态、34 筛选与键盘/Back 行为。
2. 在 Catalog/Search Domain 中定义规范化 SearchQuery、Filter、SearchResult 和图片查询输入；图片字节保持 Plugin/路径中立且诊断脱敏，不进入日志、Evidence 或持久化。
3. 增加窄 `SearchApi` 与本地实现：文本按固定 Fixture 字段确定性匹配；图片输入返回固定 Recognized 标签和结果。不得用随机延迟模拟识别。
4. 第二个图库消费者出现后，把注册头像 Picker 中可复用的系统图库读取、尺寸/字节限制和脱敏边界提取到 `app_features/lib/shared/media/`；Auth 和 Search 使用各自窄 Adapter，不互相 import Feature 私有实现。
5. Search Controller 管理输入、提交去重、结果、空/错误、筛选草稿/确认和图片选择/识别状态。系统取消选图保持原页面；失败显示稳定非敏感错误。
6. `/search` 承担 28/29 文本状态；30–33 使用同一 Search Flow Scope 的页面/状态，不为 Recognizing 与 Recognized 各建独立业务 Route。34 按节点结构实现可取消筛选 Overlay/子 Route。
7. 搜索结果商品点击进入公开 Product Route；筛选复用 Catalog Value Object，不复制 Product Entity。
8. 页面使用真实 TextField、键盘 Insets、SafeArea 和单一滚动所有者；识别预览图片固定尺寸且失败占位不跳动。

## 同批测试与验收

- API/Controller：文本匹配、空结果、筛选、选图取消/失败、确定性识别、重复提交、敏感诊断和释放。
- Widget/Route：28–34 状态、键盘、筛选 Cancel/Apply、Product 导航、Back、多视口与无障碍。
- iOS Photo Library 文案和 Android System Picker 配置沿用已验证宿主；若提取共享 Picker，Registration 全量回归通过。
- 搜索流程可演示但不声称真实视觉识别能力，无摄像头权限、上传或 ML 依赖。

## 验证命令

```bash
make analyze
make lint
make test
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
make harness-check
git diff --check
```

## 平台限制

- iOS Build 受本机 Xcode Platform 可用性约束；不可用时准确记录，不能用 plist 检查替代。
- UI 自动化由人工独立安排。
