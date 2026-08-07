---
task: remove-unused-workspace-dependencies
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：移除无消费者 Workspace Package 与直接依赖

## 首轮问题

### P1：Demo 允许依赖矩阵没有随权威架构收窄

- 影响：`CLAUDE.md` 已规定 Demo 只直连 `app_data`、`app_features`、`app_ui`，但检查器和架构矩阵仍允许
  `app_core`、`app_media`、`app_media_capture_bridge`。只要未来代码真实 import，这些直连就可能重新通过
  默认 lint，绕过 Feature 装配边界。
- 修复：将 checker 与 `docs/architecture.md` 的 Demo 允许集合收窄为三条当前边；合法 Fixture 删除
  `demo_app -> app_core` dev 边；负向测试同时声明并 import 三个底层 Package，仍由矩阵精确拒绝。

## 复审结论

- `app_im` 空占位 Package、Workspace entry、Demo/Feature 依赖和当前架构声明均已删除；历史任务与 Review
  保留当时事实，不重写历史。
- Demo 当前只直连 `app_data`、`app_features`、`app_ui`；`app_features` 继续直连并真实消费 Media 与
  Media Capture Bridge。
- 默认 `make lint` 已启用 AST 消费检查；`PACKAGE_DEPS_JSON` 的隔离矩阵 Fixture 兼容路径保留。
- Plugin discovery 中 Android/iOS 各有唯一 production native Bridge entry；两端生成注册器仍注册
  `MediaCaptureBridgePlugin`。Android Debug APK 与 iOS 无签名 Debug App 均构建通过。
- 子进程型依赖 Fixture 使用显式两分钟测试预算，避免冷启动超过 `package:test` 默认 30 秒造成偶发失败；
  生产检查器行为未因此改变。

复审未发现剩余 P0/P1/P2。完整命令输出见
[测试证据](test-evidence/remove-unused-workspace-dependencies.log)。
