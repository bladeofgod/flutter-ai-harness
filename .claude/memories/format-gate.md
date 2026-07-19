# Dart Format 检查默认不是只读

`dart format --set-exit-if-changed` 仍然会改写文件，只是在需要格式化时额外返回非零退出码。

只读门禁必须使用：

```bash
dart format --output=none --set-exit-if-changed .
```

只有明确要格式化文件时才执行不带 `--output=none` 的 `dart format <paths>`。Makefile 和 hook 的检查目标必须保留 `--output=none`，避免验证命令悄悄弄脏工作树。
