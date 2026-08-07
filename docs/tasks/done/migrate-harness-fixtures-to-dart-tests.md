---
executor: task-executor
platforms: []
workKinds: [harness]
blockedBy:
  - extract-harness-validator-library
securityReview: required
---

# 将 Harness Fixture 迁移为参数化 Dart 测试

## 输入与事实来源

- `extract-harness-validator-library` 提供的可导入 Validator、CLI 兼容测试和原始耗时基线。
- `scripts/quality/test-harness.sh` 的全部成功基线、失败 mutation、诊断断言和约 312 次 Validator 调用。
- `Makefile` 与根 `app/pubspec.yaml` 的 `harness-test` 入口。

## 目标

- 在同一 Dart VM 内参数化执行 Harness 成功与失败 Fixture，消除大量进程启动和重复工具初始化。
- 保留全部现有行为证明、CLI 端到端烟测和精确诊断，不用减少场景换取速度。
- 用与前置卡相同的环境复测并报告耗时、调用模型和实测改善。

## 非目标

- 不降低 Schema、Capability、Wire、任务、安全、文档、Host 或依赖来源校验强度。
- 不把只适合 Shell/进程边界的 CLI 测试伪装成纯 library 测试。
- 不按行数拆 Validator，不为测试增加生产绕过参数。

## 实现要求

1. 先为现有 Shell 场景生成稳定 inventory：每个成功/失败标签映射到唯一 Dart case ID、mutation 和预期
   诊断。迁移完成前后自动比较 inventory，任何遗漏、重复或未分类场景都失败。
2. 用 Dart fixture builder 创建最小合法仓库和隔离的每 case 工作副本；复用内存中的静态模板、Schema
   与不可变输入，避免为每个 mutation 重新启动 Dart 或重复编译。每个 case 仍调用与 CLI 相同的完整
   Validator API，不能直接调用私有子校验制造假通过。
3. 使用表驱动 mutation 覆盖当前全部成功/失败语义，并断言成功无诊断、失败为非空且包含原精确诊断。
   mutation 必须使用结构化 JSON/YAML 解析或明确的文件变换，不能用脆弱的全局字符串替换掩盖目标。
4. 仅保留少量 Shell CLI 端到端矩阵，覆盖默认 root、`--root`、路径带空格、usage 64、校验失败 1 和成功
   0；删除 Shell case 前必须已有 inventory 对应 Dart case。
5. `make harness-test` 继续是稳定公共入口，直接运行新的参数化测试和 CLI 烟测。测试失败要显示 case ID、
   mutation 和实际诊断，不能只返回聚合非零。
6. 在首轮迁移实测后记录一个基于同机基线的性能目标，再以至少三次同条件运行的中位数验收；报告总耗时、
   改善比例和剩余慢项。不得在规划阶段虚构固定分钟数，也不得把热缓存与冷基线混比。

## 验收与验证

- 迁移 inventory 与原场景一一对应，合法/非法语义、CLI 退出码和诊断文案无漂移。
- 参数化测试主要路径在一个 Dart VM 中执行，实测达到首轮迁移后记录的目标。
- `make check` 仍执行完整 Harness 自测，没有 skip、focus 或环境变量逃生口。

```bash
make format
make analyze
make harness-check
make harness-test
make check
git diff --check
```

## 环境限制

耗时结论只对记录的 SDK、OS 和机器配置有效。macOS/Linux 都必须通过功能门禁；只有一个平台可测性能时，
明确标注其范围，不外推为 CI 的绝对分钟数。
