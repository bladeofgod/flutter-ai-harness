# Shoppe 欢迎起始页设计上下文

## 来源与范围

- 设计文件：[`Shoppe - eCommerce Clothing Fashion Store Multi Purpose UI Mobile App Design`](https://www.figma.com/design/JPP1rxO7ADGjAnECWe2Ndg/Shoppe---eCommerce-Clothing-Fashion-Store-Multi-Purpose-UI-Mobile-App-Design--Community-?node-id=0-12855&m=dev)
- Figma File Key：`JPP1rxO7ADGjAnECWe2Ndg`
- 页面节点：`0:12855`，节点名 `01 Start`
- 读取日期：2026-07-21
- 来源、作者和 CC BY 4.0 许可：[`docs/figma-links.md`](../figma-links.md)
- 本文只描述欢迎起始页。注册、登录以及其他电商页面不在当前节点范围内。

结构、尺寸和样式来自 Figma Desktop MCP 的 `get_design_context`、`get_metadata`、`get_variable_defs` 与节点截图。该节点没有绑定 Figma Variables；下列视觉值是节点事实，不代表设计稿已存在同名 Token。

## 设计事实

### 画板与图层

| 内容 | 节点 | 画板坐标与尺寸 | 说明 |
| --- | --- | --- | --- |
| 画板 | `0:12855` | `375 x 812` | 白色背景，iPhone 参考视口 |
| 品牌圆形底座 | `0:12906` | `x=121, y=232, 134 x 134` | 白色圆形及下方柔和阴影 |
| 购物袋标志 | `8:4768` | `x=147, y=253, 81.4 x 92` | 蓝色购物袋 |
| 品牌标题 | `0:12858` | `x=93, y=390, 190 x 61` | `Shoppe` |
| 说明文字 | `0:12859` | `x=63, y=469, 249 x 59` | 两行居中 |
| 主按钮 | `0:12908` | `x=20, y=634, 335 x 61` | 蓝底、圆角 16 |
| 已有账号入口 | `0:12860` | `x=81, y=713, 213 x 30` | 文字与 30 x 30 圆形箭头 |
| 状态栏 | `0:12863` | `x=0, y=0, 375 x 44` | 设计参考中的 iOS 系统 UI |
| Home Indicator | `0:12856` | `x=121, y=798, 134 x 5` | 设计参考中的 iOS 系统 UI |

应用不得绘制 Figma 中的时间、电量、信号或 Home Indicator。它们由 Android/iOS 系统和 `SafeArea` 处理，视觉比对时只比较应用内容。

### 文案与文字样式

| 用途 | 文案 | Figma 样式 |
| --- | --- | --- |
| 品牌标题 | `Shoppe` | Raleway Bold，52，行高 61，`#202020`，居中 |
| 页面说明 | `Beautiful eCommerce UI Kit for your online store` | Nunito Sans Light，19，行高 33，`#202020`，居中，两行 |
| 主操作 | `Let's get started` | Nunito Sans Light，22，行高 31，`#F3F3F3` |
| 次操作 | `I already have an account` | Nunito Sans Light，15，行高 26，`#202020`、90% 不透明度 |

Figma 输出为品牌标题提供了约 `-0.52` 的负字距。工程统一使用 `letterSpacing: 0`，这是已知的工程归一化，不把负字距带入 Flutter。

### 色彩、圆角与尺寸

| 语义 | 值 |
| --- | --- |
| 页面背景 | `#FFFFFF` |
| 品牌与正文文字 | `#202020` |
| 主色 | `#004CFF` |
| 主按钮文字 | `#F3F3F3` |
| 主按钮尺寸 | 参考视口下 `335 x 61`，水平边距 20 |
| 主按钮圆角 | 16 |
| 次操作箭头视觉尺寸 | 30 x 30 |

## 交互事实

- 页面提供“开始”和“已有账号”两个可点击入口。
- 当前节点没有通过 MCP 暴露 Prototype 跳转目标，也没有描述登录态判断、埋点、动画、加载、错误或空状态。
- 当前页面自身没有业务数据和可变状态，不需要 Controller、API、Fixture 或基础 Service。

## 资源与授权

- 正式实现从 Figma 把圆形底座、阴影和购物袋合成为一张透明 PNG，并按 Flutter Asset Variant 导出 `1x/2x/3x`。基准 PNG 使用 150 x 150 的完整视觉边界，内部圆形仍为 134 x 134；不得把整张页面截图裁成资源。
- MCP 返回的 `localhost` SVG URL 只是读取设计图层的临时通道，不得写入运行时代码或文档契约。工程不需要为该 PNG 引入 SVG 解析依赖。
- 主按钮使用 Flutter 容器与按钮能力实现；次操作使用 Flutter 提供的右箭头图标。不得把 Figma 的按钮截图、状态栏或 Home Indicator 入库。
- 设计资源沿用 [`docs/figma-links.md`](../figma-links.md) 的 CC BY 4.0 署名记录。字体文件属于独立第三方资源，入库前必须从可追溯来源确认许可并保存相应许可文本；设计文件许可不能替代字体许可核验。

## 工程推断

以下内容不是 Figma 节点直接表达的产品事实，是为了让单一参考画板在 Flutter 中稳定运行而采用的工程规则：

- 页面作为 Demo 根路由 `/` 的首屏，路由仍由 `go_router` 和壳工程统一创建。
- `app_ui` 只建立确定为全 App 事实的品牌颜色、字体注册和亮色 Theme。当前单页的字号、行高、尺寸、间距与圆角先保留在 Welcome Feature 内，后续节点确认复用语义后再提升为共享 Token。
- Welcome 页面、私有 Widget 和 Route 工厂位于 `app_features`；`apps/demo` 只通过 `app_features` 公共入口装配，不直接 import Feature 内部页面。
- 参考视口中保持上述尺寸和纵向关系；其他高度使用约束布局和必要滚动，不用整页绝对坐标 `Stack`。
- 页面内容在宽屏上以 375 逻辑像素为参考上限居中；窄屏保持至少 20 的水平边距，主按钮填满可用内容宽度。
- 短屏、横屏和增大字体时允许内容滚动，不能出现黄色溢出条、裁切或控件重叠。
- 次操作整行提供至少 48 x 48 的可点击区域，但可见圆形箭头保持 30 x 30，以兼顾 Figma 外观和可访问性。
- 品牌图形从语义树排除，避免与 `Shoppe` 文本重复朗读；两个操作保留按钮语义和英文标签。不为尚未安排的 UI 自动化预置测试专用 Key。
- 白色页面使用深色系统状态栏图标。Android/iOS 的系统栏高度和 Home Indicator 差异属于允许的平台差异。

## 当前行为边界

- `WelcomePage` 通过 `onGetStarted` 与 `onSignIn` 回调表达两个导航意图。
- 用户已确认本阶段先完成页面视觉，两个按钮暂不产生页面变化。壳工程尚未提供目标页面时，点击由注入回调安全消费并停留在欢迎页；后续页面任务负责把回调绑定到真实 Route。
- 本页没有加载、错误、空数据、登录态恢复、持久化、网络、埋点或动画状态。

## 实现时需要核验

- Raleway Bold 与 Nunito Sans Light 的字体文件来源、字重映射和许可文本。
- 导出的 `1x/2x/3x` PNG 与 Figma 节点一致，透明通道、阴影和像素尺寸正确。
- 375 x 812 参考视口的截图对齐；Android 与 iOS 均无系统栏遮挡。
- 320 x 568、375 x 812 以及增大字体场景无溢出，两个操作具有正确 Semantics。
