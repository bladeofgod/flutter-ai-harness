---
task: add-session-reset-registration-disposal
status: passed
p0: 0
p1: 0
---

# Review：为 Session Reset 注册增加解除生命周期

## 首轮问题

### P1：Widget 测试只等待首个子资源完成销毁

- 影响：等待 `OrderReviewMediaApi.dispose()` 不能证明 Registry 后续的 Search、Support 和
  MediaResourceStore 已完成释放，测试可能在异步清理仍进行时提前通过。
- 修法：卸载 Widget 后显式 `await registry.dispose()`，复用 App 已发起的同一个幂等 Future，等待完整
  Registry 释放后再断言。

## 修复与复审

- 两处内部 Registry 用例已改为等待 Registry 自身的 dispose Future。
- `attachSessionReset` 使用独立注册对象，因此同一 callback 可多次注册并分别解除；解除和 dispose 均幂等。
- logout 对注册快照按稳定顺序分发，自解除不跳过既有回调，分发中新注册从下一次有效 logout 生效。
- `DemoApp` 的销毁调用顺序为 Router、解除注册、内部 Registry、内部 Coordinator；外部对象保持有效。
- 外部 Registry 在卸载期间错过 logout 后，以已登出 Coordinator 重挂载时会先清理旧会话状态。

独立复审未发现新的 P0/P1/P2。聚焦认证、Widget、Router 测试及仓库格式、分析、边界、Harness 和差异
校验均记录于本任务证据文件。
