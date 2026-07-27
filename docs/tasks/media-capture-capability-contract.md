---
executor: task-executor
blockedBy:
  - native-harness-agent-standards
securityReview: required
---

# 定义 Media Capture 模块能力契约

## 背景

Media Capture 将同时服务 Flutter Consumer 与原生业务模块，因此必须先从模块自身和原生消费者角度定义能力，再由外层 Flutter Bridge 派生 Wire Contract。Native Module 的公共 API 不得被 MethodChannel 的字符串、Map、字段命名或 Codec 限制反向塑形。

本任务只定义与传输方式无关的模块能力、生命周期、权限和文件策略，不定义 Flutter Channel、Wire DTO 或最终 UI。

## 输入与事实来源

- `CLAUDE.md`
- `docs/native-architecture.md`
- `docs/infrastructure-modules.md`
- `docs/figma/shoppe-main-app-design-context.md` 中已有订单评价节点 `66/67` 的设计上下文。
- `app/packages/app_features/lib/feature_orders/pages/order_review_page.dart` 中已有不含媒体入口的订单评价实现。
- 当前确认的 V1 范围：拍照、录像、切换镜头、闪光灯、对焦、缩放、拍后预览、重拍、确认与取消。
- 当前确认的非目标：滤镜、美颜、贴纸、涂鸦、裁剪、远程上传和生产媒体服务。
- 用户已明确批准 Media Capture 作为项目基础能力：Flutter Consumer 通过独立 Bridge Adapter 使用，Android/iOS 原生业务模块直接依赖对应 Native Module；该归类是项目决策，不是 Harness 根据技术类型自动划分业务归属。
- 现有订单评价设计与页面已经存在，但 Media Capture 入口、拍摄器、拍后预览和附件状态尚无已批准的增量设计；本任务不得从既有评价画板推断这些新增 UI。

## 目标

- 在基础模块索引中登记 Media Capture 的项目归类、所有者、状态和消费者。
- 定义 transport-neutral 的模块操作、状态、请求、结果、取消和失败语义。
- 定义 Android/iOS Native Module 对外暴露协议必须达到的行为一致性和允许的平台差异。
- 明确媒体文件所有权、有效期、清理、隐私元数据和权限策略。
- 为 Android/iOS Core 与后续 Bridge Contract 提供唯一模块能力依据。

## 非目标

- 不定义 Channel、method/event 名称、Wire Payload、snake_case 字段或 PlatformException。
- 不创建 `app/native/`、Flutter Bridge 或 Camera Engine 实现。
- 不增加 Camera、Microphone 或 Photo Library 权限配置。
- 不实现 Native UI、Flutter 页面、Route 或结果缩略图。
- 不决定 Figma 可见布局、动画参数和品牌样式。

## 具体要求

1. 在 `docs/infrastructure-modules.md` 增加“原生媒体拍摄”能力，计划入口指向 Android/iOS Native Module，决策状态为已批准、实现状态为未实现，首个消费者记录为 Shoppe 订单评价，并记录这是用户批准的项目分类决定。
2. 新增 `docs/infrastructure/media-capture.md`，包含返回索引链接、模块职责、Native Consumer/Flutter Consumer 依赖图、公共能力、生命周期、权限、媒体文件策略、平台差异、消费者和验证计划。
3. 在固定路径新增 JSON 产物：通用 Schema 为 `docs/native/contracts/capability.schema.json`，Media Capture 实例为 `docs/infrastructure/contracts/media-capture.capability.json`。两者使用标准 JSON Parser 校验，实例至少表达 `contractId`、独立的 `capabilityVersion`、platform、operation、request、result、state、failure、permission、lifecycle 和 ownership，不出现 Flutter、Channel 或平台 SDK 类型。
4. 共享能力文档只维护跨平台语义和汇总链接。未来 Android/iOS 实际模块路径、依赖、生命周期和验证证据分别由平台详情文档管理，平台并行任务不得同时改写共享实现状态。
5. 能力文档明确 Native Consumer 直接调用平台 Native API；Dart Client 与两端 Bridge Adapter 组成另一条消费者链路，不是能力所有者。
6. Android/iOS 可以使用符合语言惯例的不同 API 形态，但必须映射到同一操作、状态、结果、取消和 Failure 语义；不能为了表面一致复制不适合某平台的 SDK 结构。
7. 公共模块结果使用受 App 管理的媒体句柄或临时文件描述、媒体类型、尺寸、时长、方向等必要元数据；不得暴露 CameraX/AVFoundation 内部对象或未经约束的任意路径。
8. 文档明确媒体文件创建者、读写范围、确认前后所有权、取消/失败清理、超时清理、App 重启行为、日志脱敏和 EXIF/位置隐私策略。
9. 权限模型区分 Camera、Microphone 和非目标的相册访问；权限请求必须由明确用户操作触发，并定义 denied/restricted/permanently-denied 等平台可表达状态的稳定能力语义。
10. 定义取消、系统中断、资源被占用、空间不足、编码失败、文件失效和不支持能力；用户主动取消不得伪装成系统异常。
11. `operation`、`state`、`failure` 和 `permission` 使用跨版本稳定的语义 ID；实例必须使用独立的 `capabilityVersion` 字段表示模块公共语义兼容性，不以 `wireVersion` 代替。两个版本数值恰好相同不表示绑定。
12. 以 `app/tool/harness_check.dart` 为 Validator 入口、`scripts/quality/test-harness.sh` 为 Fixture 入口，对上述固定 JSON 路径、JSON Schema 形态、必需字段、平台集合、稳定 ID、版本、所有权和文档引用执行当前快照可证明的确定性校验；不得要求尚未存在的实现文件或 Bridge 文件。

## 同时编写的测试

- 有效 Capability Contract 通过。
- 缺少版本、平台、operation、failure、permission、lifecycle 或 ownership 时失败。
- 出现 Flutter Channel、Wire DTO、Proto、CameraX/AVFoundation 类型或未声明自由结构时失败。
- Android/iOS 语义缺失或未声明平台差异时失败。
- 文件所有权、取消和失败清理不完整时失败。
- Capability 与基础模块索引/详情链接失效时失败。
- Capability 实例路径、Schema 引用、稳定 ID 或独立 `capabilityVersion` 字段不符合约定时失败。

## 验收标准

- Android/iOS Core 可以只依据 Capability Contract 设计类型化公共 API，不读取 Bridge Contract。
- 原生业务消费者可以直接理解并调用模块能力，不经过 Flutter。
- 后续 Bridge Contract 只能映射既有能力，不能改变模块状态机或文件策略。
- 文件、权限、取消、错误和生命周期边界足以支持独立安全审查。
- `make harness-check`、`make harness-test` 和 `git diff --check` 通过。

## 验证命令

```bash
make harness-check
make harness-test
git diff --check
```

## 平台或环境限制

本任务不连接 Camera、设备、Figma 或 Marionette。既有订单评价设计不包含 Media Capture 增量交互，但这不会阻塞模块能力语义；只有新增 Native UI、媒体入口、附件状态和 Shoppe 页面视觉接入等待增量设计，Core、Contract、Dart Client、平台 Adapter 与非 UI 集成不等待 Figma。

## 待决事项

- 媒体句柄采用 app-owned path、URI 还是 opaque identifier，需要结合两端沙箱和消费者访问方式设计，但结论属于模块能力契约，不由 Flutter Wire 格式决定。
