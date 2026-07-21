---
name: figma-to-flutter
description: "适用：读取 Figma 或根据节点实现 Flutter UI，包括 Token 反查、Auto Layout、组件 Variant、Asset 和视觉验证。不适用：替代产品决策，或从像素推断设计稿不可见的数据行为。触发词：Figma URL、node-id、design-to-code、视觉还原、Auto Layout、design token。"
paths: ["app/packages/app_features/lib/**/pages/**", "app/packages/app_features/lib/**/widgets/**", "app/packages/app_ui/lib/**", "docs/figma/**"]
---

# Figma 到 Flutter

## 编码前

1. 使用项目 `figma` 本地 MCP 读取准确节点及其父级上下文；不得用截图替代可获取的结构化设计上下文。
2. 记录层级、约束、Auto Layout、间距、字体、Fill、Stroke、Radius、Shadow、Variant、交互和 Asset。
3. 新增视觉值前检查 `app_ui` 现有 Token 和组件。
4. 区分 Figma 事实、工程推断和待决产品行为。

## 映射

- 纵向/横向 Auto Layout → 带明确约束的 `Column`/`Row`。
- Fill Container → 只有父级有界时才使用 `Expanded`。
- Hug Contents → 子节点自然尺寸；长列表避免昂贵 Intrinsic Layout。
- Overlay → 有稳定边界的 `Stack`/`Positioned`。
- 重复 Variant → 一个带显式状态参数的代码组件。
- Figma Style/Variable → 现有代码 Token；只有可复用语义决策才新增 Token。

## Asset

只有授权和导出 Scale 明确时才使用导出的 Raster/Vector。标准控件优先使用仓库 Icon Library，不得用无关 Icon 近似产品专属资源。

## 验证

在代表性移动端尺寸、文字缩放、加载/空/错误状态、键盘 Insets 和长内容下验证。可使用截图或视觉自动化，但行为测试与像素对比保持分离。

不得使用依赖单一 Viewport 的绝对定位，也不得根据屏幕宽度连续缩放字体。
