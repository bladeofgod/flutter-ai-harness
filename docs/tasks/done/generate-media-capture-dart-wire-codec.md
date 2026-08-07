---
executor: task-executor
platforms: [flutter]
workKinds: [dart-client]
blockedBy:
  - define-media-capture-wire-generation
securityReview: required
---

# 迁移 Media Capture Dart Wire 生成代码

## 输入与事实来源

- `define-media-capture-wire-generation` 完成的 Contract manifest、generator 和 Dart renderer。
- `app/packages/app_media_capture_bridge/lib/src/media_capture_constants.dart`、models、wire codec、client 和现有
  Dart 测试。
- Wire V3 golden vector、MethodChannel/EventChannel 不可信输入和 Dart Client dispose/cleanup 契约。

## 目标

- 生成并接入 Dart Runtime 的 Wire version、channel/method/event/result/error identifiers、闭合 wire enum、
  payload descriptor、字段范围和基础 codec。
- 删除被生成输出替代的手工同步表，保持类型化 Dart Client API、严格入站校验和资源生命周期完全不变。

## 非目标

- 不修改 Contract、generator、Android/iOS、Native Module、Host 或 Feature。
- 不生成 Client request pending/completed 状态机、Stream 生命周期、dispose/cleanup、媒体资源导入或业务模型。
- 不放宽未知字段、dynamic/Map 公共 API、PlatformException、路径/URI或原始媒体 bytes 边界。

## 实现要求

1. 只通过前置生成器的 `--runtime dart` 写入约定 `*.g.dart`；生成文件禁止手工修改。Package 公共 barrel
   仍只导出稳定类型化 API，不直接暴露内部 descriptor 或裸 wire collection。
2. 手写 `MediaCaptureWireCodec`/Client 改为消费生成的标识、字段表和 primitive；删除所有已由 manifest
   拥有的重复 channel/method/error/enum/range 常量。复杂跨字段验证、request registry、错误脱敏和 cleanup
   保持手写并引用生成边界。
3. 生成 enum 与现有公共 model 的转换必须 total；未知入站值仍归一为 `invalid_wire_payload`，出站无法编码
   仍为 `wire_encoding_failed`，不得用 `enum.name` 或 `toString()` 偶然形成 wire 值。
4. 保持 17 个 method、5 个 event、Wire/Capability error 来源、signed-64、thumbnail、materialize URI/handle、
   presentation/dismiss 和历史 vector 的现有语义与诊断。
5. 测试新增生成 drift、descriptor coverage 和 public API leak 检查；保留全部恶意 payload、MethodChannel/
   EventChannel、late callback、dispose和 transfer cleanup 测试，不以 generated snapshot 替代行为测试。

## 写入所有权

- `app/packages/app_media_capture_bridge/lib/**`
- `app/packages/app_media_capture_bridge/test/**` 中 Dart Runtime 测试
- 必要的 Package 分析配置

不得修改前置 Contract/generator、`android/**`、`ios/**`、共享最终 golden 或 Host。

## 验收与验证

```bash
cd app && dart run tool/generate_media_capture_wire.dart --runtime dart --check
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh analyze --fatal-infos
TOOL_WORKDIR=app/packages/app_media_capture_bridge bash scripts/flutter-tool.sh test
make format
make analyze
make harness-check
git diff --check
```

## 环境限制

Mock Channel 测试只证明 Dart codec/client，不证明平台 Adapter 的线程、生命周期或 Native mapping。任何需要
改变生成规则的问题都必须停止并返回 `define-media-capture-wire-generation`。
