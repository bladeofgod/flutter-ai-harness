---
task: media-capture-native-ui-flow-wire-evolution
status: passed
p0: 0
p1: 0
p2: 1
---

# Review: Media Capture Native UI Flow Wire V2

## 首轮结论

首轮独立 Review 未通过，P0 0、P1 3、P2 1。Wire V2 已建立 direct operation/presentation 分型、
三终态、exactly-once completion、缩略图安全映射和双平台矩阵，但 Native Preview 的资源 coverage、
并发 presentation slot 和 rotation/background 后的新 generation 语义仍未闭合。

## P1

### 1. Native Preview 的资源与 ownership scope 没有进入 Wire coverage

当前 Schema/Profile/Validator 只覆盖 Capability 的 operations/results/events/failures，无法证明
`live_preview_attachment`、`unconfirmed_preview_render_attachment`、`live_preview_render_scope` 和
`unconfirmed_preview_render_scope` 始终保持 `native_consumer_only`。现有负例也只验证 operation。

修复要求：为通用 coverage 增加 resource 与 ownership/resource-scope 类别；Profile 为四项逐项声明
`native_consumer_only`、`wireId: null` 和稳定原因；Validator 对照 Capability `resourcePolicy` 校验，
并增加遗漏、暴露资源或 scope 的负例。

### 2. 并发 presentation 没有原子占用 owner flow slot

`maxConcurrentPerOwner: 1` 和 `presentation_conflict` 已声明，但 `presentOrder` 没有在共同 coordinator
中检查并占用 active presentation slot。两个不同 requestId 仍可能同时通过检查并 present 全屏 UI。

修复要求：在 `bridge_lifecycle_coordinator` 内原子执行 owner-generation open recheck 与 active slot
reservation；冲突时以 `presentation_conflict` 完成一次且不创建 Session。所有终态、present 失败和
boundary 必须释放 slot，并增加并发占用缺失和顺序漂移负例。

### 3. rotation/background 后的 fresh owner generation 语义未闭合

Capability 在 revoke/detach 后退休旧 generation，恢复必须使用严格更大的 generation。当前 foreground
仍写成重新绑定 current generation；rotation 只覆盖 owner destroy + failure，没有覆盖 owner 未销毁、
但 attachment 已因 rotation revoke 的路径。

修复要求：background/rotation 均先 revoke；owner 存活时分配严格递增 generation 并显式 reattach；
只有 rotation 实际销毁 owner 时才 cleanup + failure 且禁止 reattach。两条路径必须结构化并增加负例。

## P2

### 1. Wire V2 Validator 诊断仍称为 V1

部分错误文案仍使用 V1，会在包含 presentation/resource 的 V2 校验失败时误导定位。

修复要求：改为 Wire V2 或不绑定版本的准确描述。

## 证据缺口

首轮审查时 evidence 仅记录 `make format` 成功；主线程正在重新采集 `make harness-test`。完成修复后仍需
追加 `make harness-check`、`make harness-test` 和 `git diff --check` 的最终结果。

## 第 1 轮复审

资源/ownership scope coverage、owner-alive fresh generation、owner-destroyed no-reattach 和 V2 诊断文案
均已关闭；Schema 通用性未发现回归。复审仍有两个 P1，slot reservation 的完整语义尚未闭合。

### 1. slot scope 绑定到会变化的 ui_owner_generation

owner-alive background/rotation 会分配更高 generation，但没有迁移或保留原 flow slot。旧 flow 在新
generation 恢复后，另一个 request 可能在新 generation 看到空 slot 并再次 present。

修复要求：slot 绑定 generation 变化期间稳定的 attached UI owner identity，或在发布 fresh generation
前由同一 coordinator 原子迁移 slot；增加换 generation 后第二 request 仍冲突的负例。

### 2. boundary 与普通终态的 slot release 顺序矛盾

slotPolicy 统一顺序要求 cleanup 后 release、最后 completion；lifecycle boundary 却在 revoke/dismiss 后
立即 release，再完成 request 和清理 Session/Preview/lease。Adapter 无法同时满足两套机器契约。

修复要求：统一 normal、presentation-failed 与 boundary 的 cleanup/release/completion 顺序，或拆成
结构化且互不冲突的策略并说明边界线性化；增加交叉一致性负例。

## 第 2 轮复审

slot 已绑定稳定 attached UI owner identity，并能跨 fresh generation 保持；boundary 的 Session/Preview
cleanup、lease settlement、slot release、completion 顺序也已关闭。当前只剩一个 P1。

### 1. callback/terminal 共同线性顺序缺少 lease settlement

`slotPolicy.releaseOrder` 已包含 delivered/undelivered lease settlement，但共同
`linearizationPolicy.callbackWinOrder` 和 capture-flow completion policy 仍只包含 cleanup、confirmed
resource adoption、slot release、completion。failure/presentation-failed 的未交付 lease 释放没有进入
同一机器顺序。

修复要求：共同 callback/terminal machine order 显式加入
`presentation_lease_settlement_if_owned`，位于 cleanup/adoption 之后、slot release 之前；completion policy
引用同一完整顺序，并增加删除 settlement 或把 slot release 移到 settlement 前的交叉负例。

## 第 3 轮最终复审

最终独立复审通过，P0 0、P1 0、P2 1。共同 presentation callback/terminal machine 已被 confirmed、
cancelled、failure、presentation-failed、slot policy 和 capture-flow completion policy 统一引用；顺序固定为
cleanup、confirmed adoption（如需）、delivered/undelivered lease settlement、stable-owner slot release、
exactly-once completion。四个交叉负例能够拒绝遗漏 settlement、提前释放 slot、completion 脱离 machine
以及 failure 遗漏未交付 lease。

唯一非阻断 P2 是最终 action ID 仍命名为 `exactly_once_success_completion`，而 failure/error 终态也引用
同一 machine。结构化 delivery/resultType 已保持错误语义正确，但后续 Adapter 实现应将其理解为“按已
声明终态完成 exactly-once gate”，不应把 failure 当作 success。已达到三轮自动修复上限，本任务不再
为该命名启动第 4 轮扩改。

当前快照的 `make format` 与 `make harness-test` 已重新采证通过。`make harness-check` 仍等待本任务独立
Security Review 及既有安全摘要同步，最终 `git diff --check` 也需在归档前追加。
