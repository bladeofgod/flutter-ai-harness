# Review 清单

## 架构

- 跨层只使用 Domain Entity。
- Proto Message 和数据库 Row 留在 Adapter 内。
- 包依赖符合规定方向。
- Feature 不 import 其他 Feature 的内部实现。
- Controller 通过构造函数接收 API。
- 壳工程不 import Feature 实现类。

## 行为

- 验收标准完整实现，包含必要的加载、空、错误和重试状态。
- 异步错误有明确处理。
- Subscription、Controller、Worker 和 Listener 正确释放。
- 单端差异有明确 Gate，不影响原本稳定的平台。

## UI

- 复用现有 Token 和组件。
- 在窄屏、键盘弹出和大字号下布局正确。
- 响应式刷新范围足够小。
- 自动化需要的交互控件具有稳定 Key。

## 原生 Bridge

- 先改契约，再改实现。
- 各端 wire 名称、参数、错误、版本和线程规则一致。
- 不支持的平台显式失败或使用已记录的降级方案。

## 测试与证据

- 测试验证行为而非内部实现。
- 验证范围与真实影响面匹配。
- 生成文件保持同步且未被手工编辑。
- Review 报告列出已运行命令、跳过项和剩余风险。
- 归档任务的 Review frontmatter 与任务 ID 一致，并且 `status: passed`、P0/P1 为 0。
- UI 静态审计证据指向真实生产实现，`implementationDigest` 与当前文件内容一致。
- UI 运行报告覆盖 Spec 声明的全部平台，且未记录设备 ID、VM Service URI 或其他敏感环境信息。
