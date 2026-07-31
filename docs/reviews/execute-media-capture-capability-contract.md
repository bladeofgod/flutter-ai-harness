---
task: media-capture-capability-contract
status: passed
p0: 0
p1: 0
p2: 0
---

# Review：Media Capture 能力契约

## 结论

最终 Review 通过，P0 0、P1 0、P2 0。通用 Capability Schema、Media Capture Profile、
共享能力说明、Harness Validator 与失败 Fixture 已形成一致且可确定验证的能力契约。

## 首轮问题与修复

### 1. Base Schema 被媒体领域模型锁死

首轮 Schema 强制每个能力使用 `session`、`media` 状态机及媒体资源策略，无法复用于定位、
认证等原生能力。修复后 Base Schema 使用任意稳定 ID 的状态机和通用资源模型；Media Capture
专属 scope、租约、句柄和清理策略只存在于 Profile 与对应 Harness 快照。

### 2. 生命周期缺少可观察交付语义

首轮 operation 与 transition 无法完整表达异步 ready、失败、系统事件和唯一结果交付。
修复后 operation 声明 `resultScope`、`eventIds`、`failureIds`，每条 transition 声明
result/event/failure/none emission。`start_session` 立即返回 session handle，随后通过 event
报告 ready 或失败；录像达到时限会自动进入预览并交付 `media_preview_ready`。

### 3. 字段约束与平台行为不确定

首轮焦点、缩放、时长、尺寸、方向和 MIME 主要依赖描述文本，zoom 又允许 clamp/reject
分叉。修复后 Schema 支持结构化数值、格式、枚举、跨字段条件与越界策略；Media Capture
统一 reject 非法 zoom，并以非终止 `invalid_argument` 报告请求错误。

### 4. 幂等关闭与失效句柄冲突

首轮重复 cancel/release 与 handle 失效语义互相矛盾。修复后 Session/Media 分别使用 300 秒
tombstone 支持有界幂等，过期后稳定返回 `session_invalid` 或 `media_invalid`；release 与 TTL
还具有不延长资源生命周期的 60 秒读取宽限。

### 5. Schema 漂移可能假绿

首轮 Harness 只抽查部分嵌套结构。修复后 Validator 固定完整 Version 1 Schema 摘要，并对
Profile 的 operation、字段、状态图、交付、权限、资源、句柄、租约、清理和隐私集合做精确
校验；Fixture 覆盖嵌套 Schema 漂移、双发/零发、不可达状态和资源策略缺失等失败路径。

## 复审

原 Reviewer 逐项复查上述 5 个 P1，确认全部关闭，未发现新增 P0/P1/P2。复审同时确认
`make harness-test`、`make format` 与 `git diff --check` 的最新证据通过；当时唯一的
`make harness-check` 失败来自前序 Security Review 摘要尚未同步，不属于契约缺陷。

## 验证

[测试证据](test-evidence/media-capture-capability-contract.log) 保留首轮失败、修复和最终归档
验证记录。最终门禁在审查报告与共享安全摘要落盘后重新执行。
