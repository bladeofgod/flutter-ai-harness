---
task: remove-unused-workspace-dependencies
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - CLAUDE.md
  - app/pubspec.yaml
  - app/pubspec.lock
  - app/apps/demo/pubspec.yaml
  - app/packages/app_features/pubspec.yaml
  - app/tool/check_package_dependencies.dart
  - app/tool/check_flutter_plugin_discovery.dart
  - app/test/package_dependency_checker_test.dart
  - scripts/lint/repository-boundaries.sh
  - scripts/lint/test-repository-boundaries.sh
  - docs/architecture.md
  - docs/im-architecture.md
  - docs/figma/shoppe-main-app-design-context.md
  - docs/assets/harness-guide.css
  - docs/assets/harness-guide.js
  - docs/index.html
  - docs/zh-CN/index.html
implementationDigest: bc2ba3f83b2c2ae5be7328565e556b706978004e4e61a20d705c721bbfd222c4
---

# Security Review：移除无消费者 Workspace Package 与直接依赖

## 首轮问题

### P2：门禁没有固化 Demo 对原生敏感能力的收窄边界

- 资产：相机、麦克风、Native Media Handle 与 App 私有媒体资源。
- 路径：Demo 的权威依赖图已经只允许 `app_data`、`app_features`、`app_ui`，但结构化矩阵仍允许直接依赖
  Core、Media 和 Media Capture Bridge；真实 import 会让消费检查放行，未来可能绕过 Feature 层直接调用
  原生敏感能力。
- 修复：Demo 允许矩阵收窄为当前三条边，并增加同时包含真实 import 和合法 Plugin discovery 的负向
  Fixture。矩阵先于消费例外拒绝全部三个底层直连，production/dev dependency 使用相同边界。

## 已检查边界

- 删除的 `app_im` 只有空公共入口，没有网络、凭据、权限、存储或用户数据实现；未来首个真实消费者必须
  通过新任务重建聚焦 Package。
- lockfile 没有依赖版本、来源或 SHA-256 变化，只反映根工具依赖分类与 Workspace 清单变化。
- `app_features` 仍有真实 Bridge 源码消费者；pub graph 和 Android/iOS discovery 证明唯一传递路径为
  `demo -> app_features -> app_media_capture_bridge`。
- Android/iOS 生成注册器仍唯一注册 `MediaCaptureBridgePlugin`；两端 Debug Host 构建通过。没有修改
  Manifest、Info.plist、Entitlements、原生权限、Wire、媒体 locator 或 cleanup ownership。
- 检查器仍只解析 AST，不执行源码；结构化输入要求根内普通文件/目录，子进程参数不经 Shell 插值，错误
  诊断不回显绝对路径或原始输入。
- 未增加依赖来源、网络、凭据、CI、Agent、MCP、签名、发布、commit 或 push 能力。

## 复审结论

安全复审确认首轮 P2 已关闭，最终 P0/P1/P2 为 0/0/0。Debug 构建证明依赖与注册链完整，不替代真机
权限和拍摄验证；本任务没有修改相关运行时代码，因此该项不阻断依赖清理归档。

## Wire Formatter 工具依赖影响

根 Workspace 新增 `dart_style 3.1.7` direct dev dependency，并由 Wire generator 直接 import，因此没有
恢复无消费者依赖。版本、Hosted 来源和 SHA-256 均由 lockfile 固定，不进入 Runtime 或 Native 产物；
依赖消费与 Plugin discovery 门禁未放宽，P0/P1/P2 维持 0/0/0。

## 详细指南采用路径调整影响

中英文详细指南把真实工程采用和空目录技术选型前置，将参考 Demo 标记为可选评估路径，并用仓库内静态
脚本提供提示词复制。脚本只在用户点击后读取固定 DOM 文本并写入剪贴板；不执行提示词或命令，不读取表单、
凭据或剪贴板内容，不发起网络请求，也不使用远程脚本、`eval` 或持久存储。该页面变更不改变 Workspace
依赖、Plugin discovery、构建命令、CI、Agent 配置或权限；摘要按当前 implementationFiles 重新绑定，原
依赖清理安全结论不变。

## 首屏 Harness 执行动画影响

中英文详细指南使用仓库内 HTML 与 CSS，把首屏右侧的 Demo 运行截图替换为 Harness 执行闭环动画；Demo
截图仍只出现在后续参考实现小结。动画内容是固定展示文本，不读取用户输入，不执行命令，也没有新增脚本、
网络请求、远程资源、存储、权限或 Agent/CI 能力；`prefers-reduced-motion` 下会停止动画。样式文件已加入
implementationFiles，当前依赖清理与 Plugin discovery 安全结论不变。
