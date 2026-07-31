---
task: shoppe-support-media-resource-preview
status: passed
p0: 0
p1: 0
p2: 2
---

# Review：Shoppe Support Media Resource Preview

## 结论

独立普通 Review 最终通过，P0/P1 为 0。消息持有 `MediaResourceId` 与会话 lease；Gallery/Camera 先导入
Store 再释放 export/native lease；发送、reset、dispose 通过 FIFO 串行，失败保留清理所有权。图片/视频
气泡与全屏 Viewer 已接通，Support close/reset 可终止 pending pick。

## P2 Follow-up

- 补充 API dispose 与 in-flight send 同时发生的直接 FIFO 测试。Owner：Flutter Support。
- Support Route 使用真实可解码测试视频覆盖 play/pause/seek；设备级行为由
  `media-capture-cross-runtime-integration` 验证。Owner：Flutter Support。
