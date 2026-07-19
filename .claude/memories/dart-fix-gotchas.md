# `dart fix --apply` 后续检查

批量自动修复后必须人工审查 diff，常见回归包括：

1. 精确 Import 与 Barrel Import 同时被重写，产生重复导入。
2. `LinkedHashMap<K, V>()` 被替换为 `<K, V>{}`，但目标静态类型仍要求 `LinkedHashMap`。
3. `library;` 被插入到 Import 后或其他无效位置。
4. 机械 lint 修复扩大异常捕获、改变空值行为或改变集合类型。

执行后运行：

```bash
git diff -- '*.dart'
make analyze
make test
```

只撤销错误的机械改动。原写法确实必要时，使用窄范围 `ignore` 并写明具体原因。
