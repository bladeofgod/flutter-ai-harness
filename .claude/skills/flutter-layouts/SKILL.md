---
name: flutter-layouts
description: "适用：复杂 Flutter 约束、Overflow、嵌套滚动、Sliver、Stack 定位、键盘/SafeArea Insets 和响应式结构切换。不适用：普通 Row/Column/Padding 组合。触发词：RenderFlex overflow、unbounded constraints、LayoutBuilder、Expanded、Sliver、Stack、keyboard inset、responsive layout。"
paths: ["app/**/pages/**/*.dart", "app/**/widgets/**/*.dart", "app/**/*_layout*.dart", "app/**/*_sliver*.dart", "app/**/*_scroll*.dart"]
---

# Flutter 布局

## 约束流程

1. 找到最近的有界宽度和高度。
2. 决定滚动轴，并确保只有一个主滚动所有者。
3. `Expanded`/`Flexible` 只用于有界 Flex 约束。
4. `LayoutBuilder` 用于结构断点，不用于连续字体缩放。
5. 固定格式元素通过 Constraint 或 AspectRatio 保持稳定尺寸。
6. SafeArea 和键盘 Insets 由受影响区域的所有者处理。
7. 验证长文本、大字号、窄屏、旋转和键盘弹出状态。

## 常见修正

- `Column` + 长列表：用 `Expanded` 约束，或改成一个 `CustomScrollView`。
- `SingleChildScrollView` + `Expanded`：移除冲突 Flex Child 或改用 Sliver。
- Overlay 漂移：约束 `Stack`，相对稳定父级定位。
- 底部操作被键盘遮挡：分离滚动内容和 Insets 感知操作区。
- 嵌套列表：只有小规模有界内容才禁用内层滚动，否则统一滚动所有权。

优先使用可推导约束，不写设备专属魔法数字。
