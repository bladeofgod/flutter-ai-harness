---
task: add-workspace-dependency-consumption-checker
status: passed
p0: 0
p1: 0
---

# Review：实现 Workspace 依赖消费检查器

## 首轮问题

### P1：未使用的 Workspace dev dependency 没有诊断

- 影响：消费模式虽然区分生产与测试/工具源码，但完全未使用的 dev 边仍可静默保留，不满足识别无消费者
  直接依赖的目标。
- 修法：dev dependency 被生产源码使用时报告放置错误；既未被生产也未被测试/工具使用时报告未消费。
  增加合法 dev import 与未使用 dev dependency Fixture。

### P1：损坏 graph 元数据可绕过统一失败输出

- 影响：`kind`/`source` 的直接类型转换会让错误类型抛出未捕获异常，CLI 可能输出实现栈与本机路径。
- 修法：所有 graph 字段改为显式类型校验；graph、discovery 和 Workspace pubspec 只接受普通文件，CLI
  将格式与文件失败映射为固定脱敏诊断。

## 修复与复审

- 默认无参数与 `--input` 模式继续只执行原允许依赖矩阵，输出和退出语义兼容。
- `--check-consumption` 显式绑定 Workspace root；Fixture graph/root/discovery 完全隔离，不读取真实
  Workspace 补充事实。
- Analyzer AST 扫描 import/export 和 conditional URI，忽略注释、字符串、生成目录与生成文件。
- 生产、test/tool/bin 与 dev dependency 语义分别校验；诊断按稳定文本排序且不包含绝对路径。
- Plugin 例外同时验证 pub graph、目标 pubspec、Android/iOS discovery、production/native/唯一条目与
  canonical package identity；存在其它生产可达路径时精确报告冗余直连。
- 无真实入边且不具备 App、工具、Plugin 或生成器结构化角色的 Package 会被报告，不使用包名 allowlist。

最终未发现新的 P0/P1/P2。任务卡全部验收命令记录在专属脱敏证据文件中。

证据保留了消费盘点在清理前预期的退出码 1，以及两次 `make format --output=none` 只读发现格式尚未
落盘的中间退出码 2；使用正确 Workspace 相对路径执行真实格式化后，同一格式门禁及 analyze、lint、
lint-test、Harness 和 diff 的最终记录均为退出码 0。
