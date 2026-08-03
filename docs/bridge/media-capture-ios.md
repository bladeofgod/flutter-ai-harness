# iOS Media Capture Bridge Adapter

iOS Adapter 位于 `app/packages/app_media_capture_bridge/ios/`，注册入口是共享 Plugin pubspec 声明的
`MediaCaptureBridgePlugin`。Adapter 只拥有 Flutter/Native 边界；相机、媒体文件、缩略图生成、原生全屏
拍摄流程和 Capability 状态仍由 `MediaCapture` 与 `MediaCaptureUI` Swift Package 拥有。

## Package 与 Host 边界

Plugin 采用 Flutter 3.41.9 官方 SwiftPM 路线，不提供 CocoaPods fallback，也不声明本机 Flutter
framework 路径。`Package.swift` 将实现拆为两个 target：

- `MediaCaptureBridgeCore` 不 import Flutter，包含 Wire Codec、类型化 Core/UI wrapper、request/listener
  registry 和生命周期协调器；
- `app_media_capture_bridge` 只包含 Flutter Channel、registrar、result/event sink、bytes 转换和当前
  presenting owner 查找。

Flutter Host 通过 `.plugin_symlinks` 引入 Plugin。manifest 从自身真实路径解析符号链接后，再按仓库
相对关系定位 `app/native/ios/MediaCapture` 与 `MediaCaptureUI`，不会依赖开发机绝对路径。真实 Demo Host
已启用 `FlutterGeneratedPluginSwiftPackage` 并通过 no-codesign build；Runner 只保留标准 Plugin 注册和权限
文案，不包含 Wire、状态机或 locator 处理。

## Wire 边界

`MediaCaptureWireCodec` 在调用 Core/UI 前完成闭合校验：

- envelope 和每种 payload 必须使用精确 key 集合；
- Wire version、requestId、Session/Media handle、枚举和列表均受闭合集约束；
- Boolean、整数和浮点类型严格区分，浮点必须有限；
- duration、focus、zoom 和 thumbnail edge 受契约范围限制；
- 未知字段、重复媒体类型、错误类型和非有限数字在 Native 调用前拒绝。

Dictionary 只存在于 Flutter/Codec 边界，Core/UI 只接收 `SessionOptions`、`SessionHandle`、
`MediaHandle`、`FlashMode` 或 Bridge 自有的 Sendable 值对象。出站值再次验证后才回调 Flutter。
错误使用固定 message 和闭合 details，不包含 payload、requestId、handle、bytes、路径、底层异常或
UIKit/AVFoundation 对象。

本 Adapter 映射 17 个操作：Session 创建与控制、拍照/录像、retake/confirm/cancel、lease release、
bounded thumbnail、`present_capture_flow`/`dismiss_capture_flow`，以及 Wire V3 的
`materialize_media_resource`/`release_materialized_media`。

## 缩略图

`read_media_thumbnail` 只消费 Core 返回的 bounded sanitized JPEG copy。Adapter 在独立 executor 上重新
检查，不在 MainActor 上扫描最多 512 KiB 的 JPEG：

- 请求边长 64 到 512；
- 输出不超过 524288 bytes，像素尺寸不超过请求边长；
- MIME 固定为 `image/jpeg`，orientation 固定为 0；
- photo 不带 poster frame，video poster frame 位于 0 到 60000 毫秒；
- JPEG 使用 canonical JFIF，尺寸与声明一致，不含 APP metadata、COM 或非法 marker 顺序。

验证后的 `Data` 仅在 Flutter target 转为 `FlutterStandardTypedData`。Adapter 不打开原始 media read
scope，不生成 URL/path fallback，也不缓存或记录 bytes。

## Scoped Transfer Locator

Export Bridge 在 `MediaCaptureBridgeCore` 内使用 App private Caches 下固定的
`app_media_capture_bridge/exports` root。Store 构造只登记 attachment，并立即调度 utility preparation；
后台逐级以 `O_DIRECTORY | O_NOFOLLOW` 打开目录 FD，并由进程级 root coordinator 对同一
cache root 只执行一次 startup sweep。多个同时存活的 Flutter Engine 共享 pending/preparing/ready/failed
准备状态，不会清扫其它 attachment 的 active transfer；全部 Store 释放后的下一代 Store 才重新执行
restart sweep。Store 持有 background preparation Task 句柄；attachment 关闭不会重新开放 generation，
但已开始的进程级 sweep 可以安全完成并唤醒其它 live Engine。staging/final 文件名只由 Security Framework
的 128-bit CSPRNG base64url handle 派生，
不接受 Dart path、URI、文件名、目录、descriptor 或 bytes。

Controller 在调用文件系统与 Capability 前原子预留 pending/active 合计最多 4 个 export、104857600 active
bytes 和当前请求的 dedupe slot；文件创建、URI 校验和删除都在 utility task 执行。单文件最大
52428800 bytes；超限请求仍先遵守 count/bytes 预留和空 staging 创建顺序，再由 Core 的 maximum-length
preflight 返回 `media_export_too_large` 并删除 staging，因此容量已满时不会越过 Adapter 调用 Core。
Bridge 使用 `openat(O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC)` 创建 staging，并从创建到 commit
始终持有同一个 FD；每次写入以 `fstat` 绑定 device/inode/regular-file/link-count/length，再用 POSIX
partial-write 循环复制 callback-scoped chunk。commit 在 `fsync` 后以
`renameatx_np(..., RENAME_EXCL)` descriptor-relative 发布 final，拒绝覆盖同名替换；cleanup 与 startup
sweep 使用 `fstatat/unlinkat` 和 no-follow 目录遍历，不按可变路径递归。Core 返回的
handle/type/MIME/length 必须和 confirmed metadata 及 committed inode 完全一致，失败会 abort/delete，且
不会释放或刷新 source lease。

成功后 Controller 先登记 active transfer，并在 Flutter callback 前启动基于 monotonic deadline 的固定
300 秒 TTL task，再在 MainActor 完成 Flutter；同步阻塞 callback 不会延长实际 lease。`fileUri` 只由
Foundation file URL API 生成，并经过和 Dart/Android 共享的 ASCII、uppercase percent encoding、空 host、
无 query/fragment/dot segment、4096 字符上限校验；只有成功 payload 可以包含 locator，错误、Event、日志和
evidence 均不包含 URI/path/export handle/media handle。

`release_materialized_media` 以 opaque export handle 严格查表。首次 release 先预留最多 4096 个独立
tombstone 槽并领取 cleanup；并发 request 加入同一 claim，不重复删除或归还容量。删除失败保留 record、
容量和 tombstone reservation，先执行有界重试，耗尽后由后续访问重新触发。成功删除后才归还 active
count/bytes 并写入 300 秒 tombstone；重复 release 幂等成功，未知、TTL 过期或跨 attachment handle 返回
`materialized_media_invalid`。TTL、late result 和 Engine detach 使用相同先删除后丢弃边界；新 attachment
在没有其它 live attachment 时重新准备 root，并清扫上次未能删除的残留。

## 生命周期与并发

`MediaCaptureBridgeController` 由 `@MainActor` 隔离，并线性化以下状态：

- 最多 32 个 pending request，以及 pending + 五分钟 completed tombstone 合计 4096 的容量；tombstone
  使用 monotonic uptime，不受系统时间前后跳变影响；
- 恰好一次 completion、一个 Event sink generation 和一个原生 presentation slot；
- Session、unconfirmed preview 和 Engine-owned confirmed lease；
- in-flight/active transfer、release claim、TTL、cleanup pending 与 release tombstone；
- UI owner disconnect、Engine detach、resource adoption 和 late cleanup。

Native async 调用返回后，Controller 先验证 generation、接管 Session/preview/lease 并写入 tombstone，
再同步回调 Flutter。边界事件先从 registry claim 并 tombstone 请求，再取消任务和清理资源，因此迟到的
Session 会被 cancel、迟到的 lease 会被 release，且不会产生第二次回调。
Controller 在存在 owner-scoped pending request、Session 或 presentation 时，以 250ms 间隔重新验证确切
window、可见性与当前 Flutter messenger hierarchy。即使没有新的 Flutter 调用，window 被隐藏、root
replacement 或 add-to-app FlutterViewController 被 pop 也会触发统一 owner boundary，不依赖 Scene
disconnect。完成路径会主动 claim/tombstone 请求、回收同 owner 的 Session/preview 并返回
`bridge_unavailable(view_controller_destroyed)`。preview 的 thumbnail/release 仍属于 owner；只有 confirm
后已交付给 Engine 的 lease 不再绑定 owner。

每个可能悬挂的 Native await 都通过独立 call gate 执行。请求取消后先在五秒 drain 窗口等待迟到结果并
清理 Session/preview/lease/thumbnail copy；超时后请求 Task 与 Controller 解耦，Flutter completion 仍闭合，
只由不持有 Controller 的 late cleanup owner 继续等待 Native 调用。owner presentation gate 在该 cleanup
真正 settled 前保持 poisoned，不允许新展示；Engine detach 则可以释放 Controller，不会被不合作调用
永久持有。

`start_session` 在 Core 返回 handle 后，还会等待该 Session 的首个 ready/failed 事件。首事件可早于
waiter 注册并由 32 项有界缓冲接管；`unsupported_capability` 直接作为启动失败返回并回收 Session，
其它失败先完成 `session_created`，再按 Event Contract 投递。请求若在握手期间取消，已创建 Session
同样会被 cancel，不留下未归属资源。首个请求还必须等待 `core.events()` 完成订阅注册，避免 ready/failed
在 Event collector 建立前丢失；Engine detach 会关闭该 barrier 并释放等待请求。
等待 barrier 时发生 detach 也会以 `engine_detached` 恰好一次完成，不会调用 Core。Native operation
失败与成功使用同一 owner boundary 判定；owner 已失效时由 owner destroy 覆盖原始 Capability failure。

`foregroundActive` scene 只用于新建原生展示。App 进入后台不会被视为 owner 销毁，已存在请求和
Session 继续存活；Scene disconnect 和上述精确 window/hierarchy liveness 都可触发 owner destroy。
owner destroy 会 dismiss 当前 UI、cancel owner-scoped Session/preview，但保留已交付且由 Engine 拥有的
lease。Engine detach 会额外结束 Event sink、release 全部 lease、close Core，并移除 scene observer。
detach 同时先关闭 transfer generation，使 in-flight sink fail closed；随后删除 partial/active transfer，
再完成 pending Flutter 请求。bounded 删除失败由下一 attachment 的 startup sweep 继续收敛。

owner/Engine 边界最多使用一个 5 秒总预算等待请求和 cleanup。Session cancel、lease release 以及 Core
close 均通过有界 call gate 执行；某个 Native cleanup 不响应取消时不会无限阻塞 Flutter completion、
Event sink 或 Controller 释放。Engine close 只在当时已登记资源清理及 pending request 的晚到资源清理
结束或总预算耗尽后启动，因此正常完成的晚到 lease 一定先 release、再 close Core。owner 边界则保留
presentation cleanup gate，直到实际 Native cleanup 和请求 drain 都 settled，期间不允许新展示。lease
到期后先进入 settling 状态，仍允许 `media_read_revoked` 事件和显式 release 完成，但不再允许读取缩略图；
显式 release 的已交付 lease 也保留在 settling 状态，直到 Core 的 read revoke 事件完成契约闭环。

## Presentation 与 Event

Plugin 只从包含当前 `FlutterBinaryMessenger` 对应 `FlutterViewController` 的唯一 foreground-active、
可见 `UIWindow` 查找最上层 presented/navigation/tab/split ViewController；错误 Engine 的窗口、不可见
窗口或多个候选窗口都会被拒绝。owner identity 绑定到该确切窗口，Scene disconnect 再通过受控映射销毁
窗口 owner，不会先验证 Scene 后改用另一个 key/overlay window。`present_capture_flow` 最多同时存在
一个；confirmed、cancelled 和 Capability failure 分别映射为三个不同终态，系统失败不会伪装成用户
取消。confirmed lease 在 success callback 前接管；dismiss 与 confirm 并发时 dismiss 获胜，迟到的
confirmed lease 会被释放。

`present_capture_flow` 占用 owner slot 后、创建 `MediaCaptureUiPresenter` 前先做能力预检：始终确认
Camera 硬件存在，再检查或请求 Camera 权限；配置启用 video 且 `audioEnabled` 为 true 时，才确认
Microphone 硬件存在并检查或请求 Microphone 权限。缺少硬件、拒绝、受限、永久拒绝或不支持会直接返回
闭合 Capability failure，原生拍摄页面不会先出现；Native Core 仍在 Session 启动时做第二次权限检查，
覆盖预检后的系统权限变化。

`dismiss_capture_flow` 只按 originating presentation request ID 命中当前 flow。匹配时原请求以
`capture_flow_cancelled` 完成，dismiss 请求以 `capture_flow_dismissed` 完成；未知或已结束 ID 是幂等
no-op，不会关闭其它 flow。

Event Channel 支持 session ready/failed、preview ready、lease expired、read revoked 和独立的
session timeout failure envelope。第二个 listener 不会替换第一个；cancel 后的新 listener 使用新的
generation。Native-only render attachment revoke 不投影到 Flutter。

## 验证边界

`ios/tool/verify-core-tests.sh` 从 `simctl` JSON 选择可用 iPhone Simulator，将 Bridge Core、测试与
Native Package 复制到受限临时目录，并用独立的 `Package.core-tests.swift` 固定测试 graph，运行
69 个 Codec/Controller/Transfer Store XCTest；生产 `Package.swift` 不通过环境变量改变依赖图。Core 测试和 Host
验证共用 `safe-rsync-copy.sh`，以大小写不敏感规则统一排除完整 `.env*` 范围、签名证书/私钥、Provisioning Profile、
钥匙串导出物、本地配置和生成目录，并只保留目标目录内的安全符号链接。没有可用 Simulator 时会明确
报告 runtime tests skipped。
`MediaCaptureBridgeCore` 另用 generic iOS Simulator SDK 编译，验证 iOS 13、UIKit/MainActor 与 Core/UI
products。`ios/tool/verify-host-route.sh` 使用权限收紧且可清理的临时 App Workspace，排除环境文件、
签名材料、钥匙容器和生成目录（包括完整 `.env*` 范围），仅保留目标目录内的安全符号链接，并验证复制
结果不存在越界链接；Core DerivedData 也位于权限收紧的临时根。Simulator destination、home/repository/
临时绝对路径和所有标准 UUID 在输出前统一替换，替换后仍存在 home 路径或 UUID 时脚本 fail closed；
随后只在临时 Demo pubspec 开启项目级 SwiftPM，执行 no-codesign Flutter iOS build 并确认 Plugin
discovery。`ios/tool/test-safe-workspace-copy.sh` 用夹具验证越界链接与敏感容器会被排除。

Fake/Simulator 不能证明真实 Camera、系统权限弹窗、硬件录像或设备性能。真实 Demo Runner SwiftPM 接线
与 no-codesign build 已由最终 Integration 验证；真机系统能力验收由人工执行。
