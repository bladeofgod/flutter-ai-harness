---
task: media-capture-thumbnail-capability-evolution
status: passed
p0: 0
p1: 0
p2: 0
implementationFiles:
  - docs/native/contracts/capability.schema.json
  - docs/infrastructure/contracts/media-capture.capability.json
  - docs/infrastructure/media-capture.md
  - app/tool/harness_check.dart
  - scripts/quality/test-harness.sh
implementationDigest: 503ca52c6f127855ea8cbf230a2316123851c9098c134b2beafdc5beba0a0601
---

# Security Review: Media Capture Native Preview 与缩略图 Capability 演进

## iOS dismiss 支持状态影响复审

后续 Wire/Harness 变化只提升 Adapter dismissal 的 iOS support；Native preview generation、thumbnail
source/decoder cleanup、工作预算、bounded JPEG copy 与路径禁入规则均未变化。独立 Security Reviewer
确认 P0 0、P1 0、P2 0，摘要已绑定当前共享文件。

## 首轮结论

首轮独立 Security Review 未通过，P0 0、P1 2、P2 1。审查覆盖相机/预览资产、opaque handle、
租约和文件访问、RenderTarget callback、thumbnail decoder/copy、日志/cache、竞态与 App restart。

## P1

### 1. Retired owner generation 可以重新抢占当前渲染 owner

攻击或竞态入口是已销毁、旋转前或后台前的旧 UI owner。当前 `owner_generation` 只有正整数边界，
attachment 对所有 different generation 都执行 revoke-old-before-attach-new；因此旧 generation 延迟
attach 可能撤销当前 owner，旧 generation detach 也可能拆掉当前 binding。

影响是实时相机画面或确认前媒体重新暴露给已销毁 owner，并可形成持续抢占。修复必须增加受机器
校验的 high-watermark、retired generation 永不接受、same-generation same-target 限制、stale attach
稳定 Failure，以及 stale/mismatched detach no-op 语义和负例。

### 2. 缩略图竞态只丢弃输出，没有停止敏感 source/decoder 工作

Release、TTL、cancel 或 restart 获胜时，当前策略只执行 `discard_partial_copy`，未要求撤销 source
access、取消并等待 decoder 停止、关闭文件句柄或清理 decoded pixels。结果虽然不交付，敏感像素、
CPU、内存和句柄仍可能超出租约状态继续存活。

修复必须把 in-flight thumbnail generation 建模为受管资源，在访问 source 前登记，并按固定顺序执行：
revoke source access、cancel and await decoder、close handles、wipe decoded pixels、discard partial copy，
最后提交唯一 Failure。负例必须拒绝只清理 copy 的策略。

## P2

### 1. 缺少缩略图生成工作预算

512px/512KiB 只限制最终结果，不限制高分辨率源的完整解码和并发调用。应增加每 Media/每 Module
并发上限、decoded pixel/working-memory 预算和 decode-time subsampling 语义，并要求平台 Core/Gate
使用大尺寸媒体与并发调用验证。

## 已确认边界

- Opaque handle 仍使用 CSPRNG、至少 128-bit entropy、strict registry lookup，禁止路径派生和拼接。
- 24 小时 lease、60 秒 read grace、grace 后禁止新读取和强制关闭删除未回归。
- JPEG、512px、512KiB、upright、EXIF/位置/文件名清理和 source bytes/path/URI 禁止已有确定性门禁。
- Wire V1 projection 未暴露新增 RenderTarget 或 thumbnail 能力；既有 typed boundary、exactly-once、
  resource adoption、late cleanup 未见回归。
- Agent task path、Executor 路由、Reviewer 只读与 Security digest 门禁未见回归。

三份旧 Security Review 摘要当前不得刷新；修复并完成独立复审后再级联更新。

## 第 1 轮复审

Generation high-watermark、retired replay 拒绝、managed job、完整失败 cleanup、原子 first-winner、
commit ownership 与工作预算已通过复审，原 P1-2 和 P2 关闭。仍有 1 个 P1：Profile 声明 detach
必须同时匹配 generation 与 adapter instance identity，但两个 detach request 只携带 handle 和
`owner_generation`，Core 无法识别 mismatched target。Detach request 必须增加 Native-only
`render_target_adapter`（或等价不可伪造 binding token），Harness 需固定 request shape，并补
“adapter B attach 被拒后不能 detach adapter A”负例。

当前仍不可刷新三份旧 Security Review 摘要。

## iOS 综合修正后的最终复审

上面的阶段性限制已由后续实现和复审关闭。独立 Security Reviewer 重新核对共享 Gate、golden、Core、
Rendering、UI 与文档增量，确认本轮没有修改 Capability/Wire 结构、thumbnail ownership、权限或 Agent
能力。最终结论为 P0/P1/P2 0/0/0，本报告按当前实现文件重新绑定摘要；方向适配不在本轮范围内。

## 跨 Runtime 集成影响

最终集成未修改 thumbnail 能力，只更新共享 Harness、状态文档和跨 Runtime vectors；bounded copy、
内存预算与 Native-only source 边界不变。独立安全复审为 P0/P1/P2 0/0/0，本报告刷新摘要。

## V4 Harness 最终复审

后续修复已确保失败与成功路径在擦除敏感 buffer 后最后注销 managed job，并由失败 Fixture 固定。
独立安全复审进一步确认 V4 export 未削弱 thumbnail 的 active lease、净化、大小、EXIF 和 caller copy
边界。当前实现 `P0=0`、`P1=0`、`P2=0`；摘要已绑定最终 Capability 与共享 Harness。

## 第 3 轮最终复审

最终独立 Security Review 通过，P0 0、P1 0、P2 0。失败和成功路径都先清理 source、decoder、
handle、decoded pixels 与 generation buffer，再把 `unregister_managed_job` 作为最后的 registry、
并发槽和预算释放动作；已原子转移的 caller copy 不进入清理序列。Generation replay、detach
identity、replacement ordering、first-winner、工作预算与隐私边界均保持闭合。

复审同时重新核对 Capability handle/read-grace、Wire typed boundary/lifecycle coordinator/resource
adoption，以及 Agent task/Reviewer/digest 安全不变量，确认共享 Harness 改动没有回归。允许同步更新
三份既有 Security Review 摘要；平台 decoder 的真实内存擦除与 subsampling 仍由后续双端 Core/Gate
运行验证。

## 第 2 轮复审

Detach identity、replacement 顺序和 caller copy 保留均已关闭。仍有 1 个 P1：失败 cleanup 未包含
`wipe_generation_buffer` 与 `unregister_managed_job`；成功 finalization 又在擦除 decoded pixels/
generation buffer 之前过早注销 job。两条路径都必须把 unregister 放在所有敏感 buffer 擦除之后，
作为最后的 registry/并发/预算释放动作，并增加缺失 unregister 与提前 unregister 的负例。

当前仍不可刷新三份旧 Security Review 摘要。
