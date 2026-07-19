# Bridge 契约

本目录是 Flutter 与原生端 MethodChannel/EventChannel 协议的唯一事实源。

## 规则

1. 实现代码改动前先更新契约文档。
2. Flutter、Android、iOS 在声明支持的范围内保持一致。
3. method、event、error code 和枚举 wire 值使用小写 `snake_case`。
4. `PlatformException(code, message, details)` 使用稳定字符串错误码。
5. 参数只允许 Flutter 平台通道支持的基础类型与集合。
6. 禁止跨平台通道传递 Proto 对象。
7. Native 回调 Flutter 时切回平台 UI 线程。
8. 有意的平台差异和不支持能力必须显式记录。
9. 每次 wire 变化必须追加变更日志。
10. 删除、改名或类型变化必须提升协议版本。

## 命名空间

使用可替换的反向域名：

```text
com.example.<module>.<feature>
```

基于 Harness 创建的应用必须在发布前替换 `com.example`。

## 契约模板

每份协议文档应包含：

1. 目标与版本。
2. Channel 标识。
3. Flutter → Native method 表。
4. Native → Flutter event 表。
5. Payload Schema 和可选性。
6. 错误码。
7. 线程与生命周期。
8. 各平台实现位置。
9. 平台差异。
10. 端到端流程。
11. 变更日志。

首份实际契约由 Demo 的第一个真实 Bridge 任务生成，本目录不预置虚构协议清单。
