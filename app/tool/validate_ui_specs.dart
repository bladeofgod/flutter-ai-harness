import 'dart:io';

import 'package:yaml/yaml.dart';

typedef _SpecMetadata = ({
  String id,
  int revision,
  String status,
  Set<String> itemIds,
});

void main(List<String> arguments) {
  final root = _parseRoot(arguments);
  final checker = _SpecChecker(root);
  checker.run();

  if (checker.errors.isNotEmpty) {
    for (final error in checker.errors) {
      stderr.writeln('错误：$error');
    }
    exitCode = 1;
    return;
  }
  if (checker.specCount == 0) {
    stdout.writeln('[spec-check] 当前没有 UI 行为 Spec，跳过。');
    return;
  }
  stdout.writeln('[spec-check] ${checker.specCount} 个 UI 行为 Spec 校验通过。');
}

Directory _parseRoot(List<String> arguments) {
  if (arguments.isEmpty) {
    return Directory.current.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  stderr.writeln('Usage: dart run tool/validate_ui_specs.dart [--root <path>]');
  exit(64);
}

class _SpecChecker {
  _SpecChecker(this.root);

  static const _sourceTypes = {'task', 'product', 'prototype', 'figma', 'code'};
  static const _platforms = {'android', 'ios'};
  static const _actions = {
    'tap',
    'enter_text',
    'scroll_until_visible',
    'wait_for',
  };
  static const _conditions = {
    'visible',
    'not_visible',
    'text_equals',
    'enabled',
    'disabled',
  };
  static const _selectors = {'key', 'semantics', 'text'};

  final Directory root;
  final errors = <String>[];
  final _specIds = <String>{};
  final _specs = <String, _SpecMetadata>{};
  final _auditStatuses = <String, String>{};
  var specCount = 0;

  void run() {
    final docs = Directory.fromUri(root.uri.resolve('docs/'));
    if (!docs.existsSync()) {
      return;
    }
    final specs =
        docs
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.spec.yaml'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    specCount = specs.length;
    for (final spec in specs) {
      _validateSpec(spec);
    }
    final audits =
        docs
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.audit.yaml'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final audit in audits) {
      _validateAudit(audit);
    }
    for (final entry in _specs.entries) {
      if (!entry.key.startsWith('docs/tasks/done/')) {
        continue;
      }
      if (entry.value.status != 'ready') {
        errors.add('${entry.key} 归档后必须是 ready');
        continue;
      }
      final auditPath = entry.key.replaceFirst(
        RegExp(r'\.spec\.yaml$'),
        '.audit.yaml',
      );
      if (_auditStatuses[auditPath] != 'passed') {
        errors.add('${entry.key} 归档前必须有同名 passed 静态审计：$auditPath');
      }
    }
  }

  void _validateSpec(File file) {
    final path = _relative(file);
    if (!path.startsWith('docs/tasks/') &&
        !path.startsWith('docs/app-operator/specs/')) {
      errors.add('$path 不在允许的 Spec 目录');
    }
    final YamlMap document;
    try {
      final parsed = loadYaml(file.readAsStringSync());
      if (parsed is! YamlMap) {
        errors.add('$path 的根节点必须是 Map');
        return;
      }
      document = parsed;
    } on YamlException catch (error) {
      errors.add('$path 的 YAML 无效：${error.message}');
      return;
    }

    _validateAllowedKeys(document, path, const {
      'version',
      'revision',
      'id',
      'status',
      'task',
      'title',
      'sources',
      'platforms',
      'steps',
      'assertions',
      'teardown',
      'openQuestions',
    });

    if (document['version'] != 1) {
      errors.add('$path 的 version 必须是 1');
    }
    final revision = _requiredPositiveInt(document, 'revision', path);
    final id = _requiredString(document, 'id', path);
    if (id != null) {
      if (!RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$').hasMatch(id)) {
        errors.add('$path 的 id 必须是小写 kebab-case');
      }
      if (!_specIds.add(id)) {
        errors.add('$path 的 Spec id 重复：$id');
      }
    }
    final status = _requiredString(document, 'status', path);
    if (status != null && !const {'draft', 'ready'}.contains(status)) {
      errors.add('$path 的 status 必须是 draft 或 ready');
    }
    _requiredString(document, 'title', path);

    final task = document['task'];
    String? expectedTaskRef;
    if (path.startsWith('docs/tasks/') && task == null) {
      errors.add('$path 位于任务目录时必须声明 task');
    }
    if (task != null &&
        (task is! String || !RegExp(r'^S[1-9]\d*-\d{3}$').hasMatch(task))) {
      errors.add('$path 的 task 必须是有效任务 ID');
    } else if (task is String) {
      final basename = _basename(file.path).replaceFirst('.spec.yaml', '');
      if (!basename.startsWith('$task-')) {
        errors.add('$path 的文件名必须以任务 ID $task 开头');
      }
      final taskFile = File.fromUri(file.parent.uri.resolve('$basename.md'));
      if (!taskFile.existsSync()) {
        errors.add('$path 缺少同名任务卡：${_relative(taskFile)}');
      } else {
        expectedTaskRef = _relative(taskFile);
      }
    }

    final sources = _requiredList(document, 'sources', path);
    if (sources.isEmpty) {
      errors.add('$path 必须声明至少一个 source');
    }
    var hasMatchingTaskSource = false;
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final itemPath = '$path sources[$index]';
      if (source is! YamlMap) {
        errors.add('$itemPath 必须是 Map');
        continue;
      }
      final type = _requiredString(source, 'type', itemPath);
      if (type != null && !_sourceTypes.contains(type)) {
        errors.add('$itemPath 的 type 不受支持：$type');
      }
      final ref = _requiredString(source, 'ref', itemPath);
      if (ref != null) {
        if (type == 'task') {
          if (expectedTaskRef != null && ref == expectedTaskRef) {
            hasMatchingTaskSource = true;
          }
          _validateLocalRef(ref, itemPath);
        } else if (_looksLikeLocalRef(ref)) {
          _validateLocalRef(ref, itemPath);
        }
      }
    }
    if (expectedTaskRef != null && !hasMatchingTaskSource) {
      errors.add('$path 必须声明指向 $expectedTaskRef 的 task source');
    }

    final platforms = _requiredStringList(document, 'platforms', path);
    if (platforms.isEmpty) {
      errors.add('$path 必须声明至少一个 platform');
    }
    if (platforms.any((platform) => !_platforms.contains(platform))) {
      errors.add('$path 的 platforms 只允许 android、ios');
    }

    final steps = _requiredList(document, 'steps', path);
    final stepIds = _validateSteps(steps, '$path steps');
    final assertions = _requiredList(document, 'assertions', path);
    final assertionIds = _validateAssertions(assertions, '$path assertions');
    final teardown = _requiredList(document, 'teardown', path);
    final teardownIds = _validateSteps(teardown, '$path teardown');
    final openQuestions = _requiredStringList(document, 'openQuestions', path);
    final allItemIds = {...stepIds, ...assertionIds, ...teardownIds};
    if (allItemIds.length !=
        stepIds.length + assertionIds.length + teardownIds.length) {
      errors.add('$path 的 Step、Assertion 和 Teardown id 必须全局唯一');
    }

    if (status == 'ready') {
      if (steps.isEmpty || assertions.isEmpty) {
        errors.add('$path 的 ready Spec 必须包含 Step 和 Assertion');
      }
      if (openQuestions.isNotEmpty) {
        errors.add('$path 的 ready Spec 不得保留 openQuestions');
      }
    }
    if (status == 'draft' && openQuestions.isEmpty) {
      errors.add('$path 的 draft Spec 必须说明 openQuestions');
    }
    if (id != null && revision != null && status != null) {
      _specs[path] = (
        id: id,
        revision: revision,
        status: status,
        itemIds: allItemIds,
      );
    }
  }

  Set<String> _validateSteps(YamlList items, String path) {
    final ids = <String>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final itemPath = '$path[$index]';
      if (item is! YamlMap) {
        errors.add('$itemPath 必须是 Map');
        continue;
      }
      final id = _requiredItemId(item, itemPath);
      if (id != null && !ids.add(id)) {
        errors.add('$path 包含重复 id：$id');
      }
      final action = _requiredString(item, 'action', itemPath);
      if (action != null && !_actions.contains(action)) {
        errors.add('$itemPath 的 action 不受支持：$action');
      }
      _validateTarget(item['target'], '$itemPath target');
      if (action == 'enter_text' && item['value'] is! String) {
        errors.add('$itemPath 的 enter_text 必须提供字符串 value');
      }
      _validateTimeout(item['timeoutMs'], itemPath);
    }
    return ids;
  }

  Set<String> _validateAssertions(YamlList items, String path) {
    final ids = <String>{};
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final itemPath = '$path[$index]';
      if (item is! YamlMap) {
        errors.add('$itemPath 必须是 Map');
        continue;
      }
      final id = _requiredItemId(item, itemPath);
      if (id != null && !ids.add(id)) {
        errors.add('$path 包含重复 id：$id');
      }
      final condition = _requiredString(item, 'condition', itemPath);
      if (condition != null && !_conditions.contains(condition)) {
        errors.add('$itemPath 的 condition 不受支持：$condition');
      }
      _validateTarget(item['target'], '$itemPath target');
      if (condition == 'text_equals' && item['expected'] is! String) {
        errors.add('$itemPath 的 text_equals 必须提供字符串 expected');
      }
      _validateTimeout(item['timeoutMs'], itemPath);
    }
    return ids;
  }

  void _validateAudit(File file) {
    final path = _relative(file);
    final specPath = path.replaceFirst(RegExp(r'\.audit\.yaml$'), '.spec.yaml');
    final metadata = _specs[specPath];
    if (metadata == null) {
      errors.add('$path 缺少同名有效 Spec：$specPath');
      return;
    }

    final YamlMap document;
    try {
      final parsed = loadYaml(file.readAsStringSync());
      if (parsed is! YamlMap) {
        errors.add('$path 的根节点必须是 Map');
        return;
      }
      document = parsed;
    } on YamlException catch (error) {
      errors.add('$path 的 YAML 无效：${error.message}');
      return;
    }

    _validateAllowedKeys(document, path, const {
      'version',
      'spec',
      'specId',
      'specRevision',
      'status',
      'items',
    });
    if (document['version'] != 1) {
      errors.add('$path 的 version 必须是 1');
    }
    final declaredSpec = _requiredString(document, 'spec', path);
    if (declaredSpec != null && declaredSpec != specPath) {
      errors.add('$path 的 spec 必须指向 $specPath');
    }
    final specId = _requiredString(document, 'specId', path);
    if (specId != null && specId != metadata.id) {
      errors.add('$path 的 specId 与 $specPath 不一致');
    }
    final specRevision = _requiredPositiveInt(document, 'specRevision', path);
    if (specRevision != null && specRevision != metadata.revision) {
      errors.add('$path 的 specRevision 与 $specPath 不一致');
    }
    if (metadata.status != 'ready') {
      errors.add('$path 只能审计 ready Spec');
    }

    final status = _requiredString(document, 'status', path);
    if (status != null && !const {'passed', 'failed'}.contains(status)) {
      errors.add('$path 的 status 必须是 passed 或 failed');
    }
    final items = _requiredList(document, 'items', path);
    final seen = <String>{};
    var allCovered = true;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final itemPath = '$path items[$index]';
      if (item is! YamlMap) {
        errors.add('$itemPath 必须是 Map');
        allCovered = false;
        continue;
      }
      _validateAllowedKeys(item, itemPath, const {'id', 'status', 'evidence'});
      final id = _requiredString(item, 'id', itemPath);
      if (id != null && !seen.add(id)) {
        errors.add('$path 包含重复审计 id：$id');
      }
      if (id != null && !metadata.itemIds.contains(id)) {
        errors.add('$itemPath 引用了 Spec 中不存在的 id：$id');
      }
      final itemStatus = _requiredString(item, 'status', itemPath);
      if (itemStatus != null &&
          !const {'covered', 'missing', 'wrong'}.contains(itemStatus)) {
        errors.add('$itemPath 的 status 不受支持：$itemStatus');
      }
      if (itemStatus != 'covered') {
        allCovered = false;
      }
      final evidence = _requiredStringList(item, 'evidence', itemPath);
      if (const {'covered', 'wrong'}.contains(itemStatus) && evidence.isEmpty) {
        errors.add('$itemPath 的 $itemStatus 必须包含实现证据');
      }
    }

    final missingIds = metadata.itemIds.difference(seen).toList()..sort();
    if (missingIds.isNotEmpty) {
      errors.add('$path 缺少审计项：${missingIds.join(', ')}');
      allCovered = false;
    }
    if (status == 'passed' && !allCovered) {
      errors.add('$path 只有全部条目 covered 时才能 passed');
    }
    if (status == 'failed' && allCovered) {
      errors.add('$path 的条目全部 covered，status 应为 passed');
    }
    if (status != null) {
      _auditStatuses[path] = status;
    }
  }

  String? _requiredItemId(YamlMap item, String path) {
    final id = _requiredString(item, 'id', path);
    if (id != null &&
        !RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$').hasMatch(id)) {
      errors.add('$path 的 id 必须是小写 kebab-case');
    }
    return id;
  }

  void _validateTarget(Object? value, String path) {
    if (value is! YamlMap) {
      errors.add('$path 必须是 Map');
      return;
    }
    final by = _requiredString(value, 'by', path);
    if (by != null && !_selectors.contains(by)) {
      errors.add('$path 的 by 只允许 key、semantics、text');
    }
    _requiredString(value, 'value', path);
  }

  void _validateTimeout(Object? value, String path) {
    if (value != null && (value is! int || value <= 0)) {
      errors.add('$path 的 timeoutMs 必须是正整数');
    }
  }

  void _validateAllowedKeys(YamlMap map, String path, Set<String> allowed) {
    for (final key in map.keys) {
      if (key is! String || !allowed.contains(key)) {
        errors.add('$path 包含不支持的字段：$key');
      }
    }
  }

  int? _requiredPositiveInt(YamlMap map, String key, String path) {
    final value = map[key];
    if (value is! int || value <= 0) {
      errors.add('$path 的 $key 必须是正整数');
      return null;
    }
    return value;
  }

  bool _looksLikeLocalRef(String ref) => const [
    'docs/',
    'app/',
    'protos/',
    'scripts/',
    '.claude/',
  ].any(ref.startsWith);

  void _validateLocalRef(String ref, String path) {
    final target = ref.split('#').first;
    if (target.isEmpty ||
        (!File.fromUri(root.uri.resolve(target)).existsSync() &&
            !Directory.fromUri(root.uri.resolve(target)).existsSync())) {
      errors.add('$path 引用了不存在的仓库路径：$ref');
    }
  }

  String? _requiredString(YamlMap map, String key, String path) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$path 缺少非空 $key');
      return null;
    }
    return value;
  }

  YamlList _requiredList(YamlMap map, String key, String path) {
    final value = map[key];
    if (value is! YamlList) {
      errors.add('$path 的 $key 必须是 List');
      return YamlList.wrap(const []);
    }
    return value;
  }

  List<String> _requiredStringList(YamlMap map, String key, String path) {
    final value = _requiredList(map, key, path);
    if (value.any((item) => item is! String || item.trim().isEmpty)) {
      errors.add('$path 的 $key 必须只包含非空字符串');
      return const [];
    }
    return value.cast<String>();
  }

  String _relative(File file) => file.path
      .substring(root.path.length)
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/'), '');

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
