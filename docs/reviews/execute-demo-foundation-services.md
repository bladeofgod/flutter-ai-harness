---
task: demo-foundation-services
status: passed
p0: 0
p1: 0
---

# Demo 基础 Service 设计清册执行 Review

## 审查范围

- 任务卡：`docs/tasks/done/demo-foundation-services.md`
- 能力索引：`docs/infrastructure-modules.md`
- 按需详情：`docs/infrastructure/network.md`、`session.md`、`storage.md`、`app-runtime.md`
- 契约同步：`CLAUDE.md` 的基础模块索引引用，以及 `architect` 的按需加载规则
- 验证证据：`docs/reviews/test-evidence/demo-foundation-services.log`

工作树中任务生产者规则、规划 Command 和中英文 README 的既有未提交优化不属于本任务实现范围，本 Review 不把这些改动计入任务验收结论。

## 审查结论

未发现 P0、P1 或 P2 问题。

- 顶层索引仅保留能力、入口、所有者、状态、触发条件和详情链接；包职责与完整数据链路只链接权威文档，没有重复展开。
- 索引为 31 行、约 3KB；Agent 可以先完成能力发现，再只加载当前领域的子文档。
- 四份子文档均可独立读取，并逐项记录决策状态、实现状态、所有者、首个消费者、采用模式、禁止耦合和启用验证。
- `ApiClient`、`AuthService` 和 `UserService` 均为“已批准、未实现”；日志、运行环境、存储、KV、Drift、网络状态和初始化器均保持延后。
- Fixture Payload、Proto Message、数据库 Row、Domain Entity、Feature API 与壳工程 Service 的边界和 `docs/api-contracts.md`、`docs/architecture.md` 一致，且没有在子文档内复制完整链路。
- 文档没有引入 Endpoint、业务字段、凭据、本机路径、私有协议或运行时代码。

## 验证

完整输出见 `docs/reviews/test-evidence/demo-foundation-services.log`：

- `make harness-check`：通过；Codex 适配和 Harness 静态检查均通过。
- `git diff --check`：通过。
- 归档后 `make spec-check`：通过；当前没有 UI 行为 Spec，按约定跳过。
- 归档后 `make harness-check`：通过；任务卡、Review、证据与全部索引链接有效。
- 本任务仅修改文档，不需要 Flutter 测试、Android/iOS 构建、Figma MCP、Marionette 或 UI Spec。

## 剩余风险

- Session、User Entity、请求键和 Fixture Payload 仍需由首个真实 Auth、Profile 或 Catalog 消费任务确定。
- 本次只批准边界，不证明未来 Service 实现正确；运行时代码出现时必须回填索引和相关子文档，并增加对应单测、架构 lint 和消费者验证。
