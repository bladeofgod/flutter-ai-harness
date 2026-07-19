# Dart Catch 类型选择

`avoid_catches_without_on_clauses` 鼓励显式捕获类型，但 `on Exception` 捕获不到 `TypeError` 等 Dart `Error`。

| 场景 | 建议 |
| --- | --- |
| API、业务和网络代码 | 捕获文档明确的最窄 `Exception` 类型 |
| 解析边界 | 捕获 `FormatException` 或具体解析异常 |
| 必须避免框架崩溃的 UI 边界 | `on Object`，同时记录日志并提供明确 fallback |
| 非法 Mock/平台值相关测试 | 只有边界契约要求兜底时才用 `on Object` |

不得把所有 Catch 都替换成 `on Object`，否则会掩盖编程错误。只有在有意的兜底边界才宽捕获，并保留 Stack Trace 和足够诊断上下文。
