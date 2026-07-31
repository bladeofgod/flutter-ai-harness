---
task: flutter-media-resource-architecture
status: passed
p0: 0
p1: 0
---

# Review: Flutter 媒体资源与预览基础件架构

## 结论

普通 Review 通过，P0 0、P1 0。实现只修改文档与测试证据，frontmatter 的
`platforms: []`、`workKinds: [documentation, planning]` 和 `executor: task-executor` 与实际范围一致。

## 已检查边界

- `app_media -> app_core, app_ui`，`app_features/apps/demo -> app_media`；`app_data` 不依赖
  `app_media`，Capture Bridge 继续不依赖 Workspace Package。
- `MediaResourceId` 在 `app_core` 中只承担 opaque 格式校验；Store、Resolver、metadata、lease 和预览
  API 没有继续下沉。
- 消息只保存 Resource ID 与轻量 metadata；绝对路径、URI、Native/Bridge handle 和播放器对象留在
  基础设施内部。
- `MediaResourceLease` 以 owner-scoped handle 表达引用，消息接纳前 retain、接纳成功线性化、Controller
  late/dispose、会话 reset、消息删除和 Registry dispose 的顺序闭合。
- Native confirmed lease 只在 `app_media` atomic commit 后释放；transfer/source 清理失败不会使已经
  commit 的消息资源失效。
- Gallery 图片 canonicalization、MP4/MOV 容器与 decoder probe 分层、20/50 MiB 上限、15 秒 Support
  consumer 配置、poster/player 预算和预览生命周期与任务卡一致。
- 基础模块索引声明“已批准/未实现”，没有把设计文档误写成生产实现或真机验证结果。

## 验证证据

[测试证据](test-evidence/flutter-media-resource-architecture.log) 记录：

- `make lint` 通过。
- `git diff --check` 通过。
- `make harness-check` 被 9 份既有 Security Review 的 `implementationDigest` 漂移阻断；这些报告绑定的
  共享文件在当前 dirty 工作树中已有后续改动。本任务没有修改报告或伪造通过结论。

## 门禁复核

9 份受共享文件影响的旧 Security Review 已针对当前实现完成独立只读复审，均为 P0 0、P1 0、P2 0，
并同步当前 `implementationDigest`。随后重新执行的 `make harness-check` 已通过，归档阻塞解除。

纯文档 Review 不证明未来 Store、平台 codec、Bridge transfer 或视频播放器已经实现；这些证据属于
后置任务。
