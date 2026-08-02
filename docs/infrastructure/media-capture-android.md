# Android Media Capture Native Core

> 实现状态：Core、concrete surface、Native UI、V4 Export Bridge、Host 权限接线、专项静态 Gate、
> JVM/Robolectric 与 Debug APK build 已完成；Android instrumented 和真机 Camera/权限/硬件性能尚未验收。

[返回 Media Capture 能力说明](./media-capture.md)

Android 模块位于 `app/native/android/media_capture/`，由 Android 原生消费者和后续 Android
Bridge Adapter 直接依赖。模块拥有 Session/Media 状态机、CameraX 采集编排、资源 Registry、
权限前置、文件租约、Render attachment、concrete `MediaCaptureRenderView` 和缩略图 managed job。
它不依赖 Flutter，不读取 Wire Map，也不通过 Channel 调用自身能力。

## 构建与依赖

模块是独立 Android Library，可单独运行 Gradle 门禁。固定工具链和平台边界如下：

| 项目 | 固定值 |
| --- | --- |
| Flutter Host 基线 | Flutter 3.35.7 |
| Gradle | 8.12，复用 Demo Host wrapper |
| Android Gradle Plugin | 8.9.1 |
| Kotlin | 2.1.0 |
| Java source/target | 11 |
| compileSdk / minSdk | 35 / 23 |
| CameraX Core/Lifecycle/Video/View | 1.5.1 |
| AndroidX ExifInterface | 1.4.2 |
| kotlinx.coroutines | 1.9.0 |
| AndroidX Test Core（仅测试） | 1.6.1 |
| Robolectric（仅测试） | 4.14.1 |

CameraX、ExifInterface 来源为 Google AndroidX Maven，使用 Apache-2.0 License；Kotlin
Coroutines 和 AndroidX Test Core 来源为 Maven Central/Google Maven，使用 Apache-2.0 License；
Robolectric 来源为 Maven Central，使用 MIT License。模块 Gradle 文件使用精确版本，不使用动态版本或
本机仓库。验证机使用可运行 AGP 8.9.1 的 JDK 21 启动 Gradle，产物仍固定为 Java 11 source/target；
Host 的 Flutter、AGP、Kotlin、Gradle 组合未改变。

实际验证命令：

```bash
JAVA_HOME=<JDK_17_OR_NEWER> ANDROID_HOME=<ANDROID_SDK> \
  app/apps/demo/android/gradlew -p app/native/android/media_capture \
  test lint assembleDebug assembleRelease
```

2026-07-28 使用上述锁定版本完成公开 Maven 依赖解析；此前 Debug/Release 各 67 个本地单测
（含 14 个 Robolectric 生产封装与 concrete surface 测试）已通过。V4 export 任务新增本地单测后，
最终 `test lint assembleDebug assembleRelease` 结果以本任务 evidence 为准。模块级 `.gitignore`
排除 Gradle 工作目录和构建产物。

## 公共 API

`MediaCapture` 是传输中立的类型化入口。它使用 `SessionHandle`、`MediaHandle`、enum、sealed event
和 `MediaCaptureException`，逐项提供 Capability V4 的操作：

- Session：`startSession`、拍照、开始/停止录像、切换镜头、闪光、对焦、缩放、重拍、确认和取消。
- Media：callback-scoped 原始读取、释放、确认媒体缩略图、确认媒体到 typed Native sink 的有界流式导出。
- Native render：创建模块定义的 concrete surface，以及 live preview 和 unconfirmed preview 的
  attach/detach。
- Lifecycle：rotation、后台、owner destroy、App restart 和 Core close。

`copyConfirmedMediaToSink` 只接受 active confirmed `leased` media、typed `MediaCopySink` 与
`1..52428800` 的 `maxLength`。`MediaCopySink` 是调用方作用域内的 Native object，只暴露 suspend
`begin(mediaType, contentType, byteLength)`、`write(buffer, byteCount)`、`commit(byteLength)` 和
`abort()`，公共 API 不包含 `File`、`Uri`、`OutputStream`、Flutter 类型、Wire Map 或目标存储身份。
`write` 的 `ByteArray` 是 callback-scoped borrowed memory：Consumer 必须在 suspend 调用返回前完成读取
或自行复制，不得保留引用；Core 会复用并在终态擦除该数组。`commit` 是可取消的原子发布边界：只有成功
返回才可让目标持久可见，取消或异常必须保持目标可由 `abort` 丢弃；Consumer 若违反合作取消和原子提交
契约，Core 不承诺替它恢复外部 sink。
成功结果 `MediaExportResult` 只返回 source 的 `mediaHandle`、`mediaType`、`contentType` 和
`byteLength`。调用取消映射为 `media_export_cancelled`；120 秒 deadline 映射为
`media_export_timed_out`；source/sink 底层异常只映射稳定 failure code，不把异常文本、路径、handle 或
sink detail 暴露给消费者。

生产消费者通过 `AndroidMediaCaptureFactory.create` 装配 Context、LifecycleOwner、权限 delegate、
父 Scope 和三个 Dispatcher；Factory 内部创建 CameraX、文件、thumbnail、Clock、CSPRNG 与 render
surface factory，不会把这些实现对象暴露给消费者。Framework、source、mount endpoint、文件 reference
和 renderer SPI 都是 module-internal；模块测试仍可向 internal `MediaCaptureCore` 构造注入对应窄 Fake。

`startSession` 立即返回可取消 handle，权限与 CameraX 准备在注入的父 `CoroutineScope` 中执行。
每个 Session 同时提供 `sessionObservation` `StateFlow`，保存当前 state、ready capability snapshot、
preview 和 terminal failure；调用方即使在初始化完成后才订阅，也能立即恢复关键状态。`events`
`SharedFlow` 继续用于即时通知，但不作为 Ready/Failed 的唯一可靠来源。调用方取消 Coroutine 时
`CancellationException` 继续传播；用户取消和 thumbnail 显式 cancel 使用 Capability 的稳定结果或
Failure。Core 对外只返回稳定 Failure code，不转发 CameraX、解码器、文件路径或底层异常详情。

Native Consumer 使用 `MediaCaptureRenderSurfaceOwner(Context, LifecycleOwner, ownerGeneration)` 调用
`createRenderView`，得到每次调用都新建且构造器不公开的 `MediaCaptureRenderView`。公共 attachment API
只接受该 concrete outer surface；公共 API 不提供 `PreviewView`、`SurfaceProvider`、图片/视频 source、
player、Camera、Session、文件路径、URI、Flutter 类型或 Wire Map 的 getter、callback 或 downcast
协议。Factory 只接受至少进入 `Lifecycle.State.CREATED` 且未销毁的 owner；该 View 只能 programmatic
factory 创建，不支持 XML/layout editor inflation，因此只在 class 上局部
抑制 `ViewConstructor`；CameraX source 与文件 source 只存在于 module-internal Framework/Rendering 边界。
每个 factory output 还会登记到创建它的 Core module instance；其它 Core、App restart 前创建的旧 surface
以及 factory/create 与 restart 竞态中未登记成功的 output 都不能 attach，失败 output 会移除 lifecycle
observer，不留下无 owner 的 target。

## 状态与资源

- 每个模块实例只允许一个非终态 Session；completed Session 不阻止后续 Session。
- 每个 Session 保存初始化 Job 和 epoch。cancel/restart/close 先推进 epoch，再 cancel/join；过期 prepare
  即使不响应取消，也必须在 `NonCancellable` 清理完成后才能复用同一个 Framework。
- 拍照、录像开始/停止、切换镜头和控制调用共享 Session 级 operation generation/token。调用在进入
  Framework mutex 后再次验证 Session epoch、operation token 和 Framework owner；同 Session 调用串行
  等待并在获得 owner 后重新校验状态。终态先使 token 失效，再 cancel/drain 实际调用，因此旧调用退出
  前不能 close 或把 Framework 交给替代 Session。
- Framework action 保持 coroutine cancellable，`NonCancellable` 只用于 rollback、close、delete 和最终
  ownership 提交。终态 drain 最多等待 5 秒；若 Framework 或 prepare 不响应取消，实例进入 poisoned，
  Host 生命周期继续完成且该实例永久不可复用。
- Framework owner 明确区分 available、owned、closing 和 poisoned。只有真实 `close()` 成功才回到
  available；close 或 pending-cleanup drain 失败会进入 poisoned，稳定阻止新 Session，且不会把半关闭
  的 CameraX 实例隐式重试或复用。
- 每段录像保存独立 generation 和自动停止 Job。手动 stop、retake、失败、cancel、close 或新录像都会
  取消旧 Job；timer 只有在 Session、state 和 generation 同时匹配时才可触发 stop。
- Session/Media handle 使用 16-byte CSPRNG，Base64URL 无 padding，Registry 永不复用，且只做严格
  lookup；handle 不参与路径构造。
- 未确认预览 TTL 为 600 秒；确认 lease 为 86400 秒；release/expiry read grace 为 60 秒；终态
  tombstone 识别窗口为 300 秒。
- stop、cancel、release、detach 和 close 可重复调用。重复调用复用已有结果，不重建文件或延长期限。
- 媒体只写入 App 私有 cache 的模块目录。确认前照片移除 GPS、设备型号、序列号、owner、镜头和
  maker note 等识别元数据；模块不设置视频 location metadata。清理先撤销 read，再覆盖文件内容并
  删除，App restart 首次显式启动时清理模块命名空间内残留。Framework 产出到 Registry 接管之间使用
  commit guard；取消、metadata 拒绝或 handle 分配失败都回收未接管文件。物理删除返回明确结果，失败
  时先将未确认媒体推进 Capability 已有的 `DISCARDED`，使其不可 attach/read；物理清理进度仅保存在
  `MediaRecord` 内部并保留 pending delete 重试，不向公共 API 扩展 cleanup 状态。CameraX 所有预交接
  失败和取消都通过同一
  App 私有文件 wrapper 撤销读取并覆盖删除，失败引用转交 Core 的 pending owner 继续重试。
- `withMediaRead` 只在 active lease 中打开，读取对象在 callback 返回后确定关闭；grace 状态拒绝新读取。
- `copyConfirmedMediaToSink` 不刷新 lease、TTL、grace 或 tombstone，也不自动 release source。Core 在打开
  source 或调用 sink 前预留 module-owned `media_export_job` 和 `media_export_buffer`；同一 Media 最多
  1 个、同一 Module 最多 4 个 active export job。单 job 的 262144-byte 预算拆为最多 131072-byte 顺序
  read buffer 与最多 131072-byte callback copy，Module 总 working buffer 仍不超过 1048576 bytes。容量
  预检失败返回 `media_export_conflict` 或 `media_export_overloaded` 且不调用 sink。
  复制和成功/失败 cleanup 都显式运行在 Factory 注入的 `ioDispatcher`，使用内部
  `StreamingMediaRead` 顺序读取 App 私有文件，并在同一 dispatcher 调用 sink begin/write/commit/abort
  与关闭 source；禁止 `readBytes()` 或完整媒体分配。每次
  write 前校验累计长度，EOF 后校验实际长度等于 metadata declared length。release、lease expiry、
  caller cancellation、deadline 和 Core close 与 success commit 竞争唯一 terminal outcome；失败路径只在
  begin 成功且 commit 尚未成功后 abort sink 一次，关闭 source，擦除 buffer 并最后 unregister job。
  export worker 与 deadline 使用 lazy handle，并在 job 注册的同一 mutex 临界区内发布和启动；release、
  expiry 或 close 因此总能看到并取消完整 job。commit attempt 进入显式 committing 状态并拥有该阶段的
  最终收口：并发 failure request 先关闭 callback gate、记录稳定 failure code 并取消 worker；若 sink commit
  仍正常返回，已发布 target 对应 Success，若 callback 因取消或异常退出，则使用已记录 code 完成 Failure。
  failure owner 在不可取消上下文完成 claim/handoff，发起 abort 后再等待 worker 的有界收敛。
  callback copy 不与可立即擦除的 read buffer 共用数组；即使不合规 Consumer 超过 5 秒才从 `write`
  返回，Core 也不会并发改写它仍在读取的数组，该副本会在 callback 的 `finally` 中晚到擦除。sink 的
  begin/write/commit/abort 通过同一生命周期 gate 严格串行；超时 failure 可以先返回，但 job reservation
  会保留到晚到 callback、abort 和 identity-safe unregister 全部收口。restart/close 不提前清除这些
  reservation；late cleanup 使用不依赖 Core worker Scope 的独立 owner，因此 restart 后的新 export 仍受
  Module 4-job/1-MiB 总预算约束。

Core 通过构造函数接收 `CaptureFramework`、`PermissionGateway`、`MediaFileStore`、Clock、CSPRNG、
thumbnail generator、Dispatcher 和父 Scope。CameraX 的 LifecycleOwner、Main Dispatcher 与 I/O
Dispatcher 只在生产 Framework wrapper 装配时注入。

## 权限与 CameraX

模块 Manifest 不声明 Host 权限，也不会在初始化时请求权限。Host 后续必须按真实流程声明并接入：

- `android.permission.CAMERA`：用户显式开始 Session 时检查或请求。
- `android.permission.RECORD_AUDIO`：仅 `audioEnabled` 的录像在用户点击/长按开始录像时检查或请求。
- Photo Library：不声明、不检查、不请求。

Core 先通过 `PermissionGateway` 得到 granted 结果，才调用需要录音权限的 CameraX API；窄调用点仍
捕获运行时 `SecurityException` 并映射 `permission_denied`。CameraX wrapper 负责 bind/unbind、录像
时限、镜头/闪光/对焦/缩放、编码输出和稳定 Failure 映射；要求 UI/System API 的调用显式切换到
注入的 Main Dispatcher，文件与媒体元数据处理使用 I/O Dispatcher。

## Capability V3 Render Surface 与 Attachment

`MediaCaptureRenderView` 是闭合的 Android surface factory output，内部创建并持有 CameraX
`PreviewView`、照片 `ImageView` 和视频 `VideoView` player surface。Native UI 只决定 outer view 的
布局位置和 `LifecycleOwner` 生命周期，不实现 Adapter，也不能取得 source、mount endpoint、binding、
媒体 reference 或路径。owner generation 同时存在于 factory input 与 V2 attachment operation；两者不一致
在任何 registry 或 target mutation 前返回 `invalid_argument`。

这里的闭合边界是公共 API、所有权和跨 Runtime 边界，不把同一 App 进程内的 Android View hierarchy
当作安全沙箱。模块不会通过类型化 API、Channel、日志或 callback 交付内部 target；Native consumer 也不得
遍历或修改 outer view 的实现 child。已经能在 App 进程内执行任意代码的恶意依赖仍可检查 View 树、截屏或
反射进程内对象，这属于 Host 供应链与进程完整性边界，不能由一个 View 子类提供机密性隔离。

实际 mount 由 module-internal `MediaCaptureRenderMountEndpoint` 完成：

- Live source 保存 CameraX `Preview`，在 owner UI dispatcher 上真实执行
  `Preview.setSurfaceProvider(PreviewView.surfaceProvider)`；revoke/detach 把 provider 设回 null。
- Photo source 保存 App 私有 `AndroidStoredMedia` 与已验证 orientation metadata，在 I/O dispatcher 按
  surface 尺寸和内部 2048-edge/4194304-pixel 上限采样模块私有文件，物理旋转为 upright bitmap，再回到
  owner UI dispatcher 安装到照片 target；detach 清空 drawable 并回收 module bitmap。
- Video source 保存 App 私有 `AndroidStoredMedia`，在 owner UI dispatcher 把私有文件交给真实
  `VideoView`/MediaPlayer pipeline；prepared callback 每次先校验 lifecycle/binding gate。detach 停止
  playback、清空 listener/source、移除旧 player surface 并创建无 source 的新内部 target。播放器异步错误
  仅在当前 binding gate 有效时触发 Core attachment revoke；过期 callback 直接丢弃，不传播平台错误码。

Core 为每个 Session/Media scope 保留 `ownerGeneration` 高水位并使用 concrete surface 的内部 target
实例身份比较：

1. 只有严格大于高水位的新 generation 可以替换 binding。
2. 同 generation、同实例只在当前仍绑定时幂等；同 generation、不同实例返回
   `attachment_target_conflict`。
3. stale attach 返回 `attachment_generation_retired`；stale/mismatched detach 不改变当前 binding。
4. 每个 binding 使用强类型、module-internal `MediaCaptureRenderBinding` 身份；失败或 stale binding 的
   cleanup 不能清除另一 scope 已提交的 surface content。Core binding 强持有 surface，直到唯一 cleanup
   完成；surface 生命周期 callback 对 Core 使用弱引用，非活跃 binding 不反向延长 Core 生命周期。
5. 替换顺序固定为锁内推进高水位并令旧 callback guard 失效，锁外等待旧 attach settle 后执行
   revoke/detach，再 attach fresh target，最后凭 binding identity 回锁提交。mount 前和每次 UI/player
   mutation 都通过强类型 `MediaCaptureRenderMutationGate` 与 invalidate/commit 线性化，并核对 active
   scope、surface identity、owner generation 与 `LifecycleOwner` gate。
6. revoke/detach 固定执行 callback gate 失效、断开 Preview source/停止 player、移除并清空 content、
   detach surface binding，最后清理 Core registry。Core 的 `cleanupStarted` 保证每个 active binding
   exactly once；partial mount、replacement、rotation、background、owner destroy、terminal、restart 和
   close 复用同一清理路径。
7. rotation、后台、owner destroy、拍照/停止录像、确认/重拍、终态、restart 和 close 均先撤销 callback
   再清理状态或媒体。恢复必须使用新的 generation 显式 attach。

模块不生成 render diagnostic 日志，因此不会记录 surface/target 实例、owner generation、source、
renderer、binding、mount endpoint、SDK description、路径、媒体 bytes、opaque token 或 raw exception。
平台异常只映射到现有稳定 Failure，不向 Consumer 暴露 backend detail。

## 受限缩略图

`readMediaThumbnail` 只接受 active confirmed lease 和 `64..512` 的 edge。Core 在 source access 前
登记 managed job，并执行每 Media 1 个、每 Module 2 个、单 job 1048576 decoded pixels、8388608
working bytes、Module 16777216 working bytes的上限；超限在打开 source 前返回
`thumbnail_overloaded`。

Android generator 在完整图片分配前读取 bounds 并 subsample；API 27 及以上的视频使用
`getScaledFrameAtTime`，API 23-26 对超过 decoded-pixel 预算的源在完整 frame 分配前拒绝。视频 poster
target 为 `min(1000, floor(duration/2))`，通过 `MediaExtractor` 优先选择 target 或其后第一个可解码
sync frame，没有时选择 target 前最后一个，并返回实际时间。

输出物理旋转为 upright，再编码为最多 512 px、524288 bytes 的 JPEG。Generator 不依赖 OEM JPEG
编码器是否输出 APP0，而是在编码后移除设备产生的 APP/COM metadata，并写入固定、无缩略图数据的
canonical JFIF APP0；这样 Core 输出确定性满足 Bridge 的净化 JPEG 约束。Core 在 ownership commit 前
再次拒绝 APP1、其它非展示 APP marker 和 comment metadata。成功时 Core 先复制独立 caller-owned
ByteArray，再清理 Module buffer，因此后续 release、expiry、restart 或 cleanup 不能修改已提交 copy。

result commit、caller cancel、release、同步/定时 lease expiry、restart 和 decoder failure 在 Core mutex
下通过同一个 terminal claim 决定唯一结果，success commit 还会在该线性化点重新确认 active lease。
descriptor 获取使用 cancellable ownership transfer；若 dispatcher 已打开 descriptor 但调用方取消，资源
会在交给 generator work 前关闭。terminal claim 失败的一方会擦除 claim 前创建但未交付的 caller copy。
失败清理固定为 revoke source、cancel/await decoder、close handles、wipe pixels、wipe generation
buffer、discard partial copy，最后 unregister job；成功 finalization 固定为 close source、finish/close
decoder、close handles、wipe pixels、wipe generation buffer，最后 unregister job。两条清理路径都在
`NonCancellable` 中逐步 best-effort 执行；单步抛错不能跳过 unregister，也不能覆盖已确定的稳定结果。

## 验证边界

本地单测和 Framework Fake 覆盖范围包括：

- 全部 Session/Media 主要转换、非法输入、权限触发、重复 stop/cancel/release、并发 Session、TTL、
  grace、tombstone、restart 和 callback read close。
- CSPRNG entropy/唯一性和 Registry 不复用。
- 两类 attachment 的 identity、高水位、替换、stale attach/detach、rotation、后台、owner destroy 和
  terminal revoke；强类型 mutation gate 还用受控双线程测试证明 install/commit/callback/invalidation
  的线性化顺序。
- thumbnail edge/并发/内存预算、managed registration、success ownership transfer、release/cancel/
  restart/decoder first-winner、cleanup 顺序、JPEG metadata 拒绝和确定性 video target/actual poster 字段。
- export JPEG/MP4 success、边界长度、截断/增长、完整 V4 direct Failure taxonomy、同媒体 1 job/Module
  4 job/1MiB buffer 预算、sink begin/write/commit/abort failure、never-returning cancellable sink、
  120 秒 deadline、caller cancel、release/expiry/restart/Core close 竞态、Core mutex 竞争、callback gate、
  callback Dispatcher affinity、并发 export、late completion 和 exactly-once abort/commit。Robolectric
  还直接覆盖生产 `StreamingMediaRead` 的顺序读取、EOF、revoke 和 idempotent close。
- cancel-during-prepare 与不响应取消的 stale prepare、旧录像 timer、捕获取消/非法 metadata/handle 耗尽、
  删除失败重试、late subscription、调用方 mutable Set 改写、attachment 重入/清理抛错，以及 thumbnail
  同步 expiry 和每个 cleanup step 抛错。
- cancel 与不响应取消的 photo/recording/control、并发 capture 重新校验、Framework close 失败 poisoned、
  `DISCARDED` 后的内部物理删除重试、离开 preview 后的 late subscriber、attach/cleanup completion gate，
  以及 Framework pending cleanup 向 Core 重试 owner 的交接。
- 响应取消的 gated capture 无需释放 gate 即可完成 lifecycle drain；不响应取消的 capture/prepare 在 5 秒
  上限后 poisoned 隔离。thumbnail 还覆盖 caller copy 已创建后 failure 先胜，验证未交付 copy 擦除、失败
  cleanup 顺序和 managed slot 注销。
- preview 已提交并发布到 StateFlow、旧 capture 仍卡在最终 pending-cleanup drain 时，retake 同样在 5 秒
  上限后 poison 仍被旧 operation 占用的 Framework；后续 operation、restart 和新 Session 稳定拒绝或
  有界完成，不重新进入旧 Framework。
- concrete surface factory 每次返回 fresh instance，并拒绝 generation mismatch；公共 Consumer API 不含
  Flutter/Wire、source、provider、文件或 backing target 类型。
- Robolectric 直接验证真实 CameraX `SurfaceProvider` 安装/清空、App 私有照片采样/旋转与 content 清空、
  私有视频 path 交给真实 `VideoView` pipeline、player target 移除、replacement、same-generation target
  conflict、retired generation、跨 module/restart surface 拒绝、owner destroy 与 lifecycle gate。

Robolectric 生产封装测试直接运行 `AndroidPrivateMediaStore`、`AndroidPhotoMetadataSanitizer` 和
`AndroidSanitizedThumbnailGenerator`、CameraX pre-handoff ownership guard 和 concrete render surface，
覆盖 scoped read、覆盖删除、
真实 EXIF GPS/设备/时间清理、图片 decode-time subsample、JPEG 重编码不保留 EXIF、descriptor 获取取消
清理、删除失败 pending handoff，以及 poster/bounds/嵌套 `SecurityException` 的生产 helper 映射。它们
不使用 Framework Fake 代替上述 Android wrapper。

本地 JVM/Robolectric 结果不证明真实 Camera、Microphone 权限框、CameraX 生命周期、硬件中断、不同
厂商编码器、真实 PreviewView 出帧、真实 VideoView 解码/播放、大尺寸媒体内存峰值或录像性能。
Android Quality Gate 和最终集成必须在模拟器/设备上验证
Activity 生命周期、rotation/background、真实视频 metadata、大尺寸媒体和并发 thumbnail，并在真机
验证 Camera/Microphone 授权、拍照、录像时限、系统中断和性能。
