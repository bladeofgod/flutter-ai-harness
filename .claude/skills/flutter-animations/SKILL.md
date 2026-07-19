---
name: flutter-animations
description: "适用：需要 AnimationController、Tween、Curve、Interval、Simulation 的显式动画、自定义过渡、Hero、滚动驱动或物理动画。不适用：一行即可完成的简单隐式动画或默认路由转场。触发词：AnimationController、TickerProvider、Tween、Hero、FadeTransition、SlideTransition、spring、scroll animation。"
paths: ["app/**/*animat*.dart", "app/**/*transition*.dart", "app/**/*hero*.dart", "app/**/*scroll*.dart"]
---

# Flutter 动画

1. 单一属性随状态变化时优先使用隐式动画。
2. 只有需要编排、中断、协调或直接控制进度时才使用 `AnimationController`。
3. Controller 由生命周期匹配的 Widget/Controller 持有并释放。
4. 动画子树保持最小；昂贵内容使用 `child` 参数和 RepaintBoundary。
5. 滚动动画使用有界归一化进度，不按每个像素重建整页。
6. Hero Tag 必须稳定且唯一，起终点几何关系应兼容。
7. 尊重减少动态效果等无障碍设置，不用动画阻塞输入或隐藏状态。
8. 测试起点、终点和中断行为；时序与构图使用视觉验证。

路由转场归 `go_router` Page Builder，不得为了动画混用导航体系。
