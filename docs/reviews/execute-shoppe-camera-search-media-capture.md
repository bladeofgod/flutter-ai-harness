---
task: shoppe-camera-search-media-capture
status: passed
p0: 0
p1: 0
---

# Review: Search 图片来源选择

## 结论

最终 P0 0、P1 0。Search 只在用户明确选择来源后调用对应 Picker；Shop 页头和 Router 都不再隐式
启动相机。既有 JPEG 校验、失败映射和租约清理边界保持不变。

## 已关闭问题

- Categories 相机按钮、相机 query intent 和 `capturePhotoOnReady` 已删除，不会从 Shop 或路由重建触发拍摄。
- Search 的主图片按钮和输入框图片入口共用来源弹窗；拍摄、相册和取消都有独立稳定行为测试，入口文案
  与图标保持来源中立。
- Native Search Adapter 在接受 thumbnail 前校验 handle、photo 类型、JPEG content type、字节和尺寸边界；
  默认 decoder 实际执行 `getNextFrame()`，并释放 frame image 与 codec。
- 测试覆盖 permission/generic failure、非照片结果、thumbnail handle 不一致、损坏 JPEG、release/clear/
  dispose 重试、晚到确认与 session reset。
- logout 清理失败通过稳定的脱敏异常报告，不包含 handle、图片字节或底层异常详情。
- 任务范围补列公共 API export 和既有 Bridge 依赖声明。

## 验证

证据见 `docs/reviews/test-evidence/shoppe-camera-search-media-capture.log`。相关 Feature/Demo tests、
`make format`、`make analyze`、全量 `make test`、`make lint`、`make harness-check` 和
`git diff --check` 均为退出码 0。

## 剩余边界

按用户要求，本轮没有继续安装、点击或调试真机。Android 原生 UI 已由前置 Host 集成提供，但 Search 来源
弹窗后的实际权限弹窗、拍照确认和缩略图回传仍需用户运行验证；此前订单评价链路曾出现真实 thumbnail
无法准备的运行错误，该平台问题不因本轮静态 Consumer 测试而视为关闭。
