---
task: media-capture-thumbnail-capability-evolution
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: Media Capture Native Preview 与缩略图 Capability 演进

## 首轮结论

首轮独立 Review 未通过，P0 0、P1 5、P2 1。Schema、Media Profile、Validator 与负例已经形成
Capability V2 初版，但通用模型、generation replay、竞态仲裁、copy 所有权和最终门禁仍需修复。

## P1

### 1. Base bounded copy 被媒体字段绑死

`boundedCopyPolicy` 强制所有 bounded copy 声明 pixel width/height、orientation、sample time、
max pixel edge 和 poster selection。非图像 copy 只能伪造媒体字段，违反 Base Schema 传输中立和
领域无关的要求。

修复要求：Base Schema 使用通用 field role binding、bound、transform、resource、ownership 和
race 结构；像素、方向、JPEG 与 poster 角色只在 Media Capture Profile 固定，并增加非媒体
bounded-copy Schema 正例。

### 2. 旧 owner generation 可以重新抢占 attachment

当前策略只区分 same/different generation；延迟到达的旧 generation 会被当作普通 different
generation，可能先撤销新 owner 再绑定旧 owner。Mismatched detach 也没有明确禁止撤销当前 binding。

修复要求：对每个 Session/Media scope 维护 generation high-watermark；新 attach 只能使用更大
generation，retired generation 永不重新接受；same generation 只允许同一 target 幂等复用，不同
target 稳定拒绝；旧或不匹配 generation 的 detach 必须 no-op，不能影响当前 binding。补乱序 attach、
same-generation 换 target 和旧 generation detach 负例。

### 3. 多个缩略图竞态没有唯一 winner

Cancel、release、TTL 和 restart 都声明在 result commit 前获胜并返回不同 Failure，但没有共同
linearization point、first-winner 或 priority 规则；多个 trigger 同时到达时平台仍需自行决定结果。

修复要求：增加通用原子 commit/竞态仲裁策略，固定 first terminal trigger wins、exactly-once outcome
与 cleanup once；成功 result commit 先获胜时，后续 source state 变化不得撤回结果。补成对竞态负例。

### 4. 缩略图提交后的所有权声明互相冲突

`thumbnail_copy` 同时被声明为 Native Module physical owner、依赖 source `leased` state 的 ownership
phase，以及 commit 后 caller-owned result。实现无法确定 release/expiry 是否撤销已提交 copy。

修复要求：分离 module-owned generation buffer 与 commit 后独立 caller-owned copy，明确 ownership
transfer at atomic result commit；提交后的 copy 不再受 source lease/release/expiry 影响。

### 5. 最终 Harness 门禁尚未通过

证据中的 `make harness-check` 只因三份既有 Security Review implementation digest 失配而失败。
必须在相关安全复审确认共享 Harness 没有回归后更新摘要，并把成功命令追加到同一证据日志。

## P2

### 1. V2 Validator 诊断仍称为 V1 Profile

完整 V2 快照错误应称为 `V2 Profile`；保护旧 operation/handle/lease 不变量的位置应称为
`V1-preserved semantics`，避免后续排障误判。

## 已确认部分

- V1 operation/state/failure 语义保留。
- Wire V1 到 Capability V2 只使用窄化 V1 projection，未泛化到任意版本。
- 负例在断言拒绝前确认 mutation，避免无效 Fixture 假绿。

## 第 1 轮复审

Base bounded copy 通用化、非媒体正例、generation high-watermark、atomic first-winner、caller copy
所有权和资源预算方向已关闭首轮问题，P2 也已关闭。复审仍保留以下 P1：

1. Detach request 缺少 `render_target_adapter` 或 binding token，无法执行 generation + target identity
   双重匹配。
2. Fresh generation replacement 缺少机器化顺序，尚未固定
   `compare-and-advance -> revoke callbacks -> detach old -> attach new -> result`。
3. 成功 result commit 没有关闭 source/decoder、注销 managed job 和擦除 module generation buffer；
   只能保留已原子转移的 caller copy。
4. 三份旧 Security Review 摘要尚未复审更新，最终 `make harness-check` 仍未通过。

## 第 2 轮复审

Detach identity、fresh replacement 顺序和 success finalization 已通过复审。当前仍有两个 P1：

1. 非成功 winner 的 cleanup 没有擦除 generation buffer 并注销 managed job，会遗留 registry 与
   每 Media/Module 并发槽。
2. 最终 `make harness-check` 仍等待安全复审与三份旧摘要更新。

Failure cleanup 必须把 `wipe_generation_buffer` 和 `unregister_managed_job` 加入有序序列；成功与
失败路径都必须在 decoded pixels 和 generation buffer 清理完成后，最后注销 job 并释放预算。

## 第 3 轮最终复审

最终独立 Review 通过，P0 0、P1 0、P2 0。失败与成功路径均先清理敏感 buffer，最后注销
managed job；Caller copy 保持独立。Base Schema 通用性、generation replay、detach identity、
replacement ordering、atomic first-winner、ownership transfer、完整 cleanup、工作预算、隐私策略
和 staged Wire V1 projection 均已闭合且有确定性 Fixture。

Security Review 已通过并授权同步三份旧摘要；随后证据中的最终 `make harness-check` 退出码为 0，
归档所需普通 Review、Security Review、实现摘要与测试证据全部满足。
