---
task: media-capture-render-surface-capability-evolution
status: passed
p0: 0
p1: 0
p2: 0
---

# Review: Media Capture Render Surface Capability V3

## 首轮结论

首轮独立 Review 未通过，P0 0、P1 2、P2 1。Capability V3 history、双端 surface composition、
ownership、gate、revoke/replacement、Native-only 与大量负例已形成初版，但旧版本历史仍可被改写，
actual mount 也仍可能只是声明标签，尚未机器化排除 no-op factory/identity adapter。

## P1

### 1. V1/V2 历史 description 仍可被覆盖

Validator 只固定旧条目的 `version`、`changeKind` 和 `compatibleWith`，description 仅要求非空；改写旧
版本语义仍可通过。现有负例也只修改 change kind 与兼容集合。

修复要求：固定 V1/V2 历史条目的完整稳定语义，并增加改写 V1/V2 description 的失败 Fixture。

### 2. actual mount 仍是 stable ID/string 标签

Base Schema 的 `actualMountCapability`、`factoryPolicy` 以及平台 implementation 主要由 stable ID 和类型名
组成；Profile 声明 non-empty factory 等字符串，Validator 只比对这些字符串。实现仍可保留标签却提供
no-op factory 或 identity adapter。现有 Fixture 也只替换标签，没有破坏 factory output、closed
conformance 或 module mount endpoint。旧 render target 字段文案还称“不暴露 concrete UI object”，与
V3 module-defined concrete surface 口径冲突。

修复要求：增加结构化 factory input/output、closed target/conformance、module-only backing-target mount
binding 和 ownership/lifecycle 关系；负例必须保留现有标签但分别破坏这些结构，证明 Validator 不是只
看声明。同步修正 callback resource 文案，但继续禁止 arbitrary/raw UI object 与跨 Runtime 编码。

## P2

### 1. 详情文档实现状态已过期

详情仍称“未实现”、模块尚未创建和路径是未来计划，但仓库已有双端 Core，当前新增的是 V3 surface，
UI/Adapter 仍待后续任务。

修复要求：分层记录 Android/iOS Core、V3 Contract、concrete surface、Native UI 和 Bridge Adapter 的
真实状态，不把静态契约描述成 renderer 已实现或真机已验证。

## 证据状态

首轮实现快照的 `make format` 与 `make harness-test` 已通过并写入本任务 evidence。修复后必须重新采集
最终快照，补 `make harness-check` 与 `git diff --check`；安全摘要漂移只能在独立 Security Review 后更新。

## 第 1 轮复审

最终独立复审通过，P0 0、P1 0、P2 0。

- V1/V2/V3 history description 已精确锁定，并有分别改写 V1/V2 description 的失败 Fixture。
- Base Schema 已结构化 factory input/output、non-null/fresh output、closed target conformance 和
  module-internal mount binding；Profile 与 Validator 交叉校验 resource、attachment、ownership phase、
  generation、backing target、source、renderer 和 binding，不能只靠 actual-mount 标签通过。
- 保留原标签但破坏 nullable/fresh output、closed conformance、arbitrary target、endpoint visibility、
  backing ownership 或 lifecycle phase 的负例均能精确拒绝。
- `render_target_adapter` 文案与 V3 concrete surface 对齐，同时继续禁止 arbitrary/raw UI object、
  source/renderer/binding 泄漏和跨 Runtime 编码。
- 详情文档已按 Contract、双端 Core、Renderer、Native UI、Wire、Bridge/Host 和平台 Gate 分层记录真实
  状态，没有把静态契约描述为 renderer 已实现或真机已验证。
- Harness direct Dart runner 仍通过仓库 FVM wrapper 与显式 package config 执行固定内部脚本，保持带
  空格 root、参数边界、退出码和诊断，没有增加外部输入、timeout 绕过或执行权限。

修复后最终快照的 `make format` 与 `make harness-test` 已重新采证通过。`make harness-check` 等待独立
Security Review 与既有摘要同步，`git diff --check` 仍须追加最终证据。

## 安全修复后的额外普通复审

安全修复增加了重复键拒绝与 `diagnosticPolicy`。额外普通复审未通过，P0 0、P1 2、P2 0。

### 1. 重复 platform Fixture 被 Schema maxItems 抢先拒绝

两个恶意 Android Fixture 插入第 3 个 implementation，但 Base Schema 已限制最多 2 项，因此测试会先
在 Schema 层失败，不能证明 Validator 的 duplicate-platform 前置/后置逻辑。新增的 surface/attachment
一对一与重复 attachment ID 拒绝也没有定向 Fixture。

修复要求：构造不被 `maxItems` 抢先拦截的前置/后置重复 platform 输入，或捕获并断言具体 duplicate
诊断；测试必须证明目标 Validator 分支命中。另补两个 surface 引用同一 attachment、重复 attachment ID
的负例。

### 2. 日志白名单闭合字段名但未闭合允许值域

`operation_id`、`lifecycle_state`、`stable_failure_id` 只使用一个 value-policy 标签，没有结构化绑定到
Capability operation/state/failure ID 集合；未声明或敏感字符串仍可能作为允许字段值。

修复要求：增加通用的逐字段 value-source/reference 结构，并在 Media Profile 中把 operation/state/
failure 分别绑定实际 ID 集合；Validator 交叉校验引用和值集合，增加伪 operation/state/failure 值的
失败 Fixture。Base Schema 与非媒体正例仍须保持领域通用。

## 第 2 轮最终复审

最终独立普通复审通过，P0 0、P1 0、P2 0。

- 重复 platform Fixture 使用 Schema 可接受的两项 Android 前序/后序输入，并断言具体 duplicate
  diagnostic；重复 attachment ID 与两个 surface 共享 attachment 也有独立定向诊断 Fixture。
- Base Schema 增加通用逐字段 value-source/reference；每个 allowed field 恰有一个来源。
- operation/state/failure 精确绑定当前 Capability 实际集合，record/status 回绑 policy enum；source
  kind/reference 漂移及伪 operation/state/failure ID 均有负例。
- 非媒体正例保持 Base Schema 领域无关；旧 history、actual mount、Native-only、V1/V2、分层状态和
  direct Dart runner 均未回归。

安全修复后的全量 `make harness-test`、格式、Dart analyze、Shell/JSON 与 diff 检查均通过；最终绿灯
`make harness-check` 在普通与安全报告、implementation digest 同步后追加。
