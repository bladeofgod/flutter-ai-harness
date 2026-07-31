---
executor: task-executor
platforms: [android, ios]
workKinds: [capability-contract, harness]
blockedBy:
  - media-capture-thumbnail-capability-evolution
securityReview: required
---

# 演进 Media Capture 模块定义平台 Render Surface Capability V3

## 输入与事实来源

- 已归档 `media-capture-thumbnail-capability-evolution` 的 Capability V2、Schema、Harness 与安全结论。
- Android/iOS Core 实现与独立 Review 共同确认的结构缺口：Core 私有持有 live/file source，Native UI
  私有持有 backing surface；V2 同时禁止所有可安装 surface/source/frame 表达，无法产生真实画面。
- 用户批准：提升到 Capability V3，不把该缺口静默改写为 V2 erratum。
- `docs/native-architecture.md`、Capability Contract、双端原生规范与测试策略。

## 目标

- 将 `media_capture` 提升到 Capability V3，允许受限的、模块定义的平台 Render Surface。
- 让 Android/iOS Module 能实际把 live camera 与确认前 photo/video renderer 安装到模块 surface，同时
  保持 Core 状态、source、内部 renderer 和文件所有权不泄露给 Native UI 或 Flutter。
- 为双端 Core、Wire 兼容和后续 Native UI 提供可机器校验的相同所有权、挂载与撤销语义。

## 非目标

- 不实现 Android/iOS Surface、全屏 Native UI、Bridge Adapter、Dart Client 或 Shoppe Feature。
- 不允许 arbitrary `View`/`UIView`/`CALayer`、CameraX/AVFoundation Session、PreviewLayer、
  SurfaceProvider、sample/pixel frame、媒体 bytes、路径、URI 或文件描述符成为 Capability 数据字段。
- 不使用 `AnyObject`、任意 opaque token、identity-only marker、空 factory 或仅保存 source 的 binding
  冒充可渲染 surface。
- 不改变 V1/V2 operation、state、failure、lease、thumbnail 或 handle 语义。

## 实现路径与所有权

本任务只写：

- `docs/native/contracts/capability.schema.json`
- `docs/infrastructure/contracts/media-capture.capability.json`
- `docs/infrastructure/media-capture.md`
- `app/tool/harness_check.dart`
- `scripts/quality/test-harness.sh`
- 本任务 Review、Security Review 与 evidence

不得修改 Wire Profile、Android/iOS Core/UI、Flutter Package、Host、CI、Makefile 或已归档任务卡。

## 契约要求

1. 提升 `capabilityVersion` 到 3；version history 保留 V1/V2 并新增 V3 additive 记录，V3
   `compatibleWith: [1, 2, 3]`。Harness 必须拒绝覆盖历史、跳号或缩窄既有语义。
2. 在通用 Capability Schema 中增加 transport-neutral、可复用的 module-defined platform render
   surface/renderer 结构；Base 结构不得写死 Camera、Media Capture、Android View、UIKit 或具体 Framework。
3. Media Capture Profile 固定两类 V3 surface：外层 concrete surface 生命周期由 native consumer/UI
   owner 持有；内部 live/file source、renderer/player/layer、binding 和 cleanup 仍由 Native Module 独占。
4. Surface 必须具有机器化的实际 mount 能力和双平台实现义务，不能只是 identity、callback 通知、
   空 factory 或无法访问 source/backing target 的 marker。
5. Android 允许 Module 提供具体 `MediaCaptureRenderView`，其内部拥有 CameraX `PreviewView`/
   SurfaceProvider、photo renderer 和 video player surface；这些内部对象不得出现在 Core capability model。
6. iOS 允许独立 Module product 提供具体 `MediaCaptureRenderView`；Core product 保持 transport-neutral，
   Rendering product 内部拥有 `AVCaptureVideoPreviewLayer`、photo content 和 `AVPlayerLayer`。
7. 继续禁止 raw/arbitrary UI object、platform SDK source、capture session、preview/player layer、sample
   buffer、pixel/media bytes、路径、URI、descriptor、untyped Map 和任何跨 Runtime surface 编码。
8. Module 在 install 前及每次 target mutation、observer/player callback 前校验 active scope、target
   identity、owner generation 与 lifecycle gate。被动 Framework pipeline 不伪造逐硬件帧 callback。
9. revoke/detach/replacement 固定顺序：invalidate callback gate，断开 source/session/player，移除并清空
   module renderer/content，detach surface，最后清理 registry/state；旧 generation 不得再次修改 surface。
10. Surface owner destroy、rotation、background、terminal、Core close 和 restart 必须沿用 V2 generation
    high-watermark、identity match、fresh replacement 和 exactly-once cleanup 语义。
11. 更新资源、ownership phase、callback resource、platform difference、security policy、data classification
    与 compatibility，明确 surface 仅限 Native consumer，不能成为 Wire projection。
12. Harness 负例至少覆盖：缺 actual mount、identity-only/opaque/AnyObject、裸 UI/SDK source、可编码
    surface、UI 持有 Session/PreviewLayer/SurfaceProvider/path、缺 ownership、cleanup 顺序漂移、旧 generation
    mutation、单平台缺失、V3 history/compatibility 错误和 V1/V2 语义回归。

## 测试与验收

- Schema/Profile/Harness 对 V1/V2/V3 history、V3 surface model 和双平台 parity 确定性通过。
- Contract 能让 Android/iOS Core 分别确定 concrete surface、内部 source、mount、revoke 与 cleanup，
  无需实现阶段再选择所有权或传递任意 SDK 对象。
- Wire V2 尚未在本任务中修改；文档明确后续兼容卡仍必须把 V3 surface 保持 Native-only。
- 普通 Review 与 Security Review 均确认没有扩大跨 Runtime 数据面、媒体读取或 UI owner 权限。

## 验证命令

```bash
make format
make harness-check
make harness-test
git diff --check
```

## 环境限制

本任务是静态 Capability/Schema/Harness 演进，不需要 Android SDK、Xcode、设备或 Figma。静态契约不能
证明真实相机出帧；双端生产 renderer 接线由 Core 任务验证，真实 live frame 由平台 Gate 留证。
