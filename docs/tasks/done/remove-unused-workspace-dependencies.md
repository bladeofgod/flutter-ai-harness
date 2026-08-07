---
executor: task-executor
platforms: [flutter]
workKinds: [flutter]
blockedBy:
  - add-workspace-dependency-consumption-checker
securityReview: required
---

# 移除无消费者 Workspace Package 与直接依赖

## 输入与事实来源

- `add-workspace-dependency-consumption-checker` 的结构化消费诊断和正反 Fixture。
- 当前源码扫描：`app_im` 只有空公共入口且没有 import；Demo 生产/测试源码只直接消费 `app_data`、
  `app_features`、`app_ui`；`app_features` 不消费 `app_im`。
- 根、Demo、`app_features` 的 `pubspec.yaml`，Workspace 依赖矩阵和 `docs/im-architecture.md`。
- Media Capture 的 Flutter Plugin metadata、`.flutter-plugins-dependencies` 校验和双端 Host 构建路径。

## 目标

- 删除没有真实消费者的 `app_im` 占位 Package及其 Workspace/依赖声明。
- 删除 Demo 和 `app_features` 中由新门禁证明无源码或必要 Plugin 消费的直接 Workspace 依赖。
- 保持 Media Capture 通过 `app_features` 传递依赖仍能在 Android/iOS Host 正确发现和注册。

## 非目标

- 不实现 IM Engine；未来首个真实 IM 消费者按契约重新建包。
- 不删除被源码实际 import 的依赖，不清理第三方依赖或重构业务 imports。
- 不手工编辑 `pubspec.lock`、`.flutter-plugins-dependencies` 或其它生成文件。

## 实现要求

1. 以新门禁的真实结果为准删除 `app/packages/app_im/`、根 workspace entry、Demo/`app_features` 的
   `app_im` 边；同步移除依赖矩阵、架构图和 Fixture 中把 `app_im` 描述为当前实现的条目。
2. 从 Demo production dependencies 移除未被其源码消费且不承担必要 Plugin reachability 的
   `app_core`、`app_media`、`app_media_capture_bridge` 等实际诊断边；从 `app_features` 移除新门禁确认的
   其它冗余边。不得仅依据本卡列举而跳过执行时扫描。
3. 保留 `docs/im-architecture.md` 作为未来能力说明时，将状态改为“未实现/首个消费者再创建”，不得继续
   声称当前有 `app_im` 包边界。
4. 运行 Workspace bootstrap/pub get 生成 lockfile 和 discovery 输出；检查 Android、iOS 的
   `app_media_capture_bridge` 都是 production native plugin，路径仍指向唯一 Workspace Package，dependency
   graph 可达且无重复。
5. 更新消费检查器的真实基线，并在冗余边清零后把它接入 `repository-boundaries.sh` 的默认 `make lint`；
   扩充 lint Fixture，确保以后新增未消费边或无消费者 Package 会失败。移除前后的应用依赖装配、测试和
   路由行为不变。

## 验收与验证

```bash
make bootstrap
make format
make analyze
make test
make lint
make lint-test
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build apk --debug
make harness-check
git diff --check
```

在 macOS/Xcode 可用时追加：

```bash
TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh build ios --debug --no-codesign
```

## 环境限制

Android Host build 是最低真实 Plugin 注册证明；iOS 环境不可用时必须保留未验证项和受影响 manifest/Host
文件，不能用 Android 结果替代 iOS。删除占位 Package 是有意且可由 Git 恢复，不重写历史。
