---
executor: android-engineer
platforms: [android]
workKinds: [native]
blockedBy:
  - media-capture-android-core
  - media-capture-wire-v2-capability-v3-compatibility
securityReview: required
---

# 实现 Android 全屏 Media Capture Native UI

## 输入与事实来源

- 已归档 Android Core 与最新 Native UI Flow Wire。
- 用户批准的拍摄交互与视觉基线；`AppColors.primary` 为 `#004CFF`，相机画布使用黑色/高对比视觉。
- `docs/native-architecture.md`、Kotlin/Android 与 Native Testing Skill。

## 目标

- 实现由 Android UI owner 全屏呈现的原生拍摄器，直接调用 Android Core 类型化 API。
- 完整支持点击拍照、长按录像、滑动缩放、切镜头、闪光、点按对焦、预览、重拍、确认、取消。
- 以 UI flow coordinator 产生 confirmed/cancelled/failure 单一终态，供 Adapter present。

## 非目标

- 不把外部设计文件标识、链接或公司资源写入仓库，不复制第三方品牌资产。
- 不在 UI 层重建 Core 状态机、权限/文件所有权或 Wire codec。
- 不实现 Flutter Adapter、Host/Manifest、Shoppe 页面、滤镜、美颜、裁剪或上传。

## 实现路径与所有权

本任务只写：

- `app/native/android/media_capture_ui/**`
- `docs/native/media-capture-android-ui.md`
- 本任务测试/Review/evidence

不得修改 Android Core、plugin `android/**`、Capability/Wire、Host、共享 docs/Registry、root Validator、
CI/Makefile 或任何 iOS/Flutter Feature 文件。

## 实现要求

1. 使用 Android 原生全屏 UI（具体 View/Compose 选择需与锁定工具链兼容并写入模块依赖），黑色相机
   画布、高对比白色控制和 Shoppe primary `#004CFF` 表达录像进度/确认；控件布局对齐批准的视觉基线，
   但不得把外部设计信息或资源写入仓库。
2. 控件按 Core `session_ready` capability snapshot 启用/隐藏；不靠失败重试探测镜头、闪光、对焦、
   zoom。点击/长按/滑动手势互斥，稳定阈值和取消区间有单元/UI 测试。
3. 拍照点击；录像按下开始、释放停止，达到 Capability 时限自动进入预览；纵向/明确方向滑动缩放并
   clamp UI 手势值到 snapshot 后再调用 Core，Wire/Core 非法输入仍按 reject。长按进入 recording 后
   隐藏闪光和切镜头控件，停止/取消录制并回到允许状态后再按 snapshot 恢复。
4. 点按画布转换为 `[0,1]` focus；切镜头、闪光与旋转/配置变化保持可解释状态。Live camera 和确认前
   preview 只组合 Core 模块提供的 concrete `MediaCaptureRenderView` 与 attachment API；UI 不实现基础
   Render Adapter，也不持有/查询 CameraX Session、PreviewView provider、媒体 path/URI 或原始 read scope。
5. 重拍回到 ready；确认只返回 Core confirmed lease metadata；取消是正常终态。权限拒绝、系统中断、
   owner destroy、后台/前台和 concurrent present 映射最新 Flow Wire，不双重 dismiss/complete。
6. Activity/Fragment/owner generation、CoroutineScope、Flow collection、surface、preview renderer 和
   session 都有明确释放；配置变化不得让旧 owner 继续回调或泄漏 Camera。
7. 无障碍 label、触控目标、安全区/系统栏、320 宽/横屏/大字号和录像状态可读；不以可见说明文字
   教用户操作，使用熟悉图标及必要 tooltip/content description。

## 测试与验收

- Presenter/ViewModel/flow coordinator 单测覆盖手势、状态、三终态、权限/Failure、自动停止、重复点击、
  owner generation、single attach、detach/revoke、owner destroy、旋转、后台/前台重新 attach 和 cleanup。
- 平台 UI 测试使用 Fake Core 验证控件可达性与视觉状态；Fake 不宣称真实 Camera preview。
- 构建不 import Flutter/Wire Map，UI 只依赖 Android Core 公共 API。
- Review 检查批准的状态布局、Shoppe 语义、非品牌复制和外部设计信息不入库。

## 验证命令

```bash
app/apps/demo/android/gradlew -p app/native/android/media_capture_ui test lint
make harness-check
git diff --check
```

## 环境限制

需要 Android SDK/JDK；local/UI Fake 不能证明真实 Camera surface、权限框、硬件录像或设备性能。
模拟器/真机行为由 Android Gate 记录，未运行时必须明确列出。
