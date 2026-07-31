---
task: shoppe-order-review-media-capture
status: passed
p0: 0
p1: 0
p2: 1
---

# Review：Shoppe Order Review Media Capture

## 结论

独立普通 Review 通过，P0/P1 为 0。附件状态、真实缩略图、替换/移除/提交/Route close 的 lease 清理和
Registry 注入均符合任务边界；pending presentation 可主动 dismiss，`media_invalid` 按清理收敛处理。

## P2 Follow-up

补充“Route close 时 presentation 正在等待”和自然 `media_invalid` 的 Controller 级直接测试。
Owner：Flutter Orders。底层 API 对两条路径已有测试，不阻断本轮 Android 真机验证。
