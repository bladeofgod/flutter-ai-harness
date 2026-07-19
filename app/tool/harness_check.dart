import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> arguments) {
  final root = _parseRoot(arguments);
  final checker = _HarnessChecker(root);
  checker.run();

  if (checker.errors.isNotEmpty) {
    for (final error in checker.errors) {
      stderr.writeln('错误：$error');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('[harness-check] AI Harness 静态检查通过。');
}

Directory _parseRoot(List<String> arguments) {
  if (arguments.isEmpty) {
    return Directory.current.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  stderr.writeln('Usage: dart run tool/harness_check.dart [--root <path>]');
  exit(64);
}

class _HarnessChecker {
  _HarnessChecker(this.root);

  final Directory root;
  final errors = <String>[];
  final _agents = <String>{};
  final _commands = <String>{};
  final _mcpServers = <String>{};
  final _skills = <String>{};

  void run() {
    _validateJson('.claude/settings.json');
    _validateJson('.mcp.json');
    _validateJson('app/.fvmrc');
    _loadMcpServerNames();
    _validateFrontmatter();
    _validateWorkflowReferences();
    _validateTaskExecutors();
    _validateMarkdownLinks();
    _validateShellSyntax();
    _validateMobileHosts();
    _validatePrivatePaths();
  }

  void _validateJson(String relativePath) {
    final file = _file(relativePath);
    if (!file.existsSync()) {
      errors.add('缺少 JSON 配置：$relativePath');
      return;
    }
    try {
      jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      errors.add('$relativePath 不是有效 JSON：${error.message}');
    }
  }

  void _loadMcpServerNames() {
    final file = _file('.mcp.json');
    if (!file.existsSync()) {
      return;
    }
    try {
      final document = jsonDecode(file.readAsStringSync());
      if (document is Map<String, Object?> &&
          document['mcpServers'] is Map<String, Object?>) {
        _mcpServers.addAll(
          (document['mcpServers'] as Map<String, Object?>).keys,
        );
      }
    } on FormatException {
      // _validateJson reports the actionable syntax error.
    }
  }

  void _validateFrontmatter() {
    _validateDefinitions('.claude/agents', _agents, (file, metadata) {
      _requireString(file, metadata, 'name');
      _requireString(file, metadata, 'description');
      _requireStringOrList(file, metadata, 'tools');
    });
    _validateDefinitions('.claude/commands', _commands, (file, metadata) {
      _requireString(file, metadata, 'description');
    });
    _validateDefinitions('.claude/skills', _skills, (file, metadata) {
      _requireString(file, metadata, 'name');
      final description = _requireString(file, metadata, 'description');
      for (final marker in const ['适用：', '不适用：', '触发词：']) {
        if (description != null && !description.contains(marker)) {
          errors.add('${_relative(file)} 的 description 缺少“$marker”');
        }
      }
      final paths = metadata['paths'];
      if (paths is! YamlList ||
          paths.isEmpty ||
          paths.any((path) => path is! String || path.isEmpty)) {
        errors.add('${_relative(file)} 必须声明非空字符串 paths');
      }
    }, nestedEntry: 'SKILL.md');
  }

  void _validateDefinitions(
    String relativeDirectory,
    Set<String> names,
    void Function(File file, YamlMap metadata) validate, {
    String? nestedEntry,
  }) {
    final directory = _directory(relativeDirectory);
    if (!directory.existsSync()) {
      errors.add('缺少定义目录：$relativeDirectory');
      return;
    }

    final files =
        directory
            .listSync(recursive: nestedEntry != null, followLinks: false)
            .whereType<File>()
            .where(
              (file) => nestedEntry == null
                  ? file.path.endsWith('.md')
                  : _basename(file.path) == nestedEntry,
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    if (files.isEmpty) {
      errors.add('定义目录为空：$relativeDirectory');
      return;
    }

    for (final file in files) {
      final metadata = _frontmatter(file);
      if (metadata == null) {
        continue;
      }
      validate(file, metadata);

      final expectedName = nestedEntry == null
          ? _basename(file.path).replaceFirst(RegExp(r'\.md$'), '')
          : _basename(file.parent.path);
      final declaredName = metadata['name'];
      final name = declaredName is String ? declaredName : expectedName;
      if (declaredName is String && declaredName != expectedName) {
        errors.add(
          '${_relative(file)} 的 name=$declaredName 与路径 $expectedName 不一致',
        );
      }
      if (!names.add(name)) {
        errors.add('重复定义名称：$name');
      }
    }
  }

  YamlMap? _frontmatter(File file) {
    final lines = file.readAsLinesSync();
    if (lines.isEmpty || lines.first.trim() != '---') {
      errors.add('${_relative(file)} 缺少 YAML frontmatter');
      return null;
    }
    final end = lines.indexWhere((line) => line.trim() == '---', 1);
    if (end < 0) {
      errors.add('${_relative(file)} 的 YAML frontmatter 未闭合');
      return null;
    }
    try {
      final metadata = loadYaml(lines.sublist(1, end).join('\n'));
      if (metadata is! YamlMap) {
        errors.add('${_relative(file)} 的 frontmatter 必须是 Map');
        return null;
      }
      return metadata;
    } on YamlException catch (error) {
      errors.add('${_relative(file)} 的 YAML 无效：${error.message}');
      return null;
    }
  }

  String? _requireString(File file, YamlMap metadata, String key) {
    final value = metadata[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('${_relative(file)} 缺少非空 $key');
      return null;
    }
    return value;
  }

  void _requireStringOrList(File file, YamlMap metadata, String key) {
    final value = metadata[key];
    final validString = value is String && value.trim().isNotEmpty;
    final validList =
        value is YamlList &&
        value.isNotEmpty &&
        value.every((item) => item is String && item.trim().isNotEmpty);
    if (!validString && !validList) {
      errors.add('${_relative(file)} 缺少非空 $key');
    }
  }

  void _validateWorkflowReferences() {
    final known = {..._agents, ..._commands, ..._skills, ..._mcpServers};
    final reference = RegExp(r'`([a-z][a-z0-9-]+)`');
    final trigger = RegExp(r'(使用|运行|加载|调用|交给|改为|值为)');

    for (final file in _markdownFiles(_directory('.claude/commands'))) {
      final content = file.readAsStringSync();
      for (final match in reference.allMatches(content)) {
        final prefixStart = match.start < 24 ? 0 : match.start - 24;
        final prefix = content.substring(prefixStart, match.start);
        final name = match.group(1)!;
        if (trigger.hasMatch(prefix) && !known.contains(name)) {
          errors.add('${_relative(file)} 引用不存在的 Harness 资产：$name');
        }
      }
    }

    for (final relativePath in const ['CLAUDE.md', 'AGENTS.md']) {
      final file = _file(relativePath);
      if (!file.existsSync()) {
        continue;
      }
      for (final match in RegExp(
        r'`/([a-z][a-z0-9-]+)`',
      ).allMatches(file.readAsStringSync())) {
        final name = match.group(1)!;
        if (!_commands.contains(name) && !_skills.contains(name)) {
          errors.add('$relativePath 引用不存在的命令或 Skill：/$name');
        }
      }
    }
  }

  void _validateTaskExecutors() {
    final tasks = _directory('docs/tasks');
    if (!tasks.existsSync()) {
      return;
    }
    for (final file in _markdownFiles(tasks)) {
      final metadata = _frontmatterIfPresent(file);
      final executor = metadata?['executor'];
      if (executor != null &&
          (executor is! String || !_agents.contains(executor))) {
        errors.add('${_relative(file)} 引用不存在的 executor：$executor');
      }
    }
  }

  YamlMap? _frontmatterIfPresent(File file) {
    final lines = file.readAsLinesSync();
    if (lines.isEmpty || lines.first.trim() != '---') {
      return null;
    }
    return _frontmatter(file);
  }

  void _validateMarkdownLinks() {
    final link = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');
    for (final file in _markdownFiles(root)) {
      final content = file.readAsStringSync();
      for (final match in link.allMatches(content)) {
        var target = match.group(1)!.trim();
        if (target.startsWith('<') && target.contains('>')) {
          target = target.substring(1, target.indexOf('>'));
        } else {
          target = target.split(RegExp(r'\s+')).first;
        }
        if (target.startsWith('http://') ||
            target.startsWith('https://') ||
            target.startsWith('mailto:') ||
            target.startsWith('#')) {
          continue;
        }
        target = target.split('#').first;
        if (target.isEmpty) {
          continue;
        }
        final resolved = File.fromUri(file.parent.uri.resolve(target));
        if (!resolved.existsSync() && !Directory(resolved.path).existsSync()) {
          errors.add('${_relative(file)} 包含失效本地链接：$target');
        }
      }
    }
  }

  void _validateShellSyntax() {
    final scripts = _directory('scripts');
    if (!scripts.existsSync()) {
      errors.add('缺少 scripts/');
      return;
    }
    final shellFiles = scripts
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.sh') ||
              const {'pre-commit', 'pre-push'}.contains(_basename(file.path)),
        );
    for (final file in shellFiles) {
      final result = Process.runSync('bash', ['-n', file.path]);
      if (result.exitCode != 0) {
        errors.add('${_relative(file)} 未通过 bash -n');
      }
    }
  }

  void _validateMobileHosts() {
    for (final path in const [
      'app/apps/demo/android/app/build.gradle.kts',
      'app/apps/demo/android/app/src/main/AndroidManifest.xml',
      'app/apps/demo/ios/Runner.xcodeproj/project.pbxproj',
      'app/apps/demo/ios/Runner/Info.plist',
    ]) {
      if (!_file(path).existsSync()) {
        errors.add('缺少声明支持的平台宿主文件：$path');
      }
    }

    final project = _file('app/apps/demo/ios/Runner.xcodeproj/project.pbxproj');
    if (project.existsSync() &&
        project.readAsStringSync().contains('DEVELOPMENT_TEAM')) {
      errors.add('iOS 模板不得提交本机 DEVELOPMENT_TEAM');
    }
  }

  void _validatePrivatePaths() {
    final usersRoot =
        '/Use'
        'rs/';
    final linuxHome =
        '/ho'
        'me/';
    final patterns = [
      RegExp('${RegExp.escape(usersRoot)}[^/\\s]+/'),
      RegExp('${RegExp.escape(linuxHome)}[^/\\s]+/'),
      RegExp(r'[A-Za-z]:\\Users\\[^\\\s]+\\', caseSensitive: false),
    ];
    final candidates = <File>[
      for (final path in const [
        'README.md',
        'CLAUDE.md',
        'AGENTS.md',
        '.mcp.json',
        'app/apps/demo/ios/Runner.xcodeproj/project.pbxproj',
        'app/apps/demo/android/app/build.gradle.kts',
      ])
        if (_file(path).existsSync()) _file(path),
      ..._textFiles(_directory('.claude')).where(_isTextFile),
      ..._textFiles(_directory('docs')).where(_isTextFile),
    ];
    for (final file in candidates) {
      final content = file.readAsStringSync();
      if (patterns.any((pattern) => pattern.hasMatch(content))) {
        errors.add('${_relative(file)} 包含本机用户绝对路径');
      }
    }
  }

  Iterable<File> _markdownFiles(Directory directory) =>
      _textFiles(directory).where((file) => file.path.endsWith('.md'));

  bool _isTextFile(File file) => const {
    '.dart',
    '.gradle',
    '.json',
    '.kts',
    '.log',
    '.md',
    '.pbxproj',
    '.plist',
    '.properties',
    '.sh',
    '.swift',
    '.xml',
    '.yaml',
    '.yml',
  }.any(file.path.endsWith);

  Iterable<File> _textFiles(Directory directory) sync* {
    if (!directory.existsSync()) {
      return;
    }
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || _isExcluded(entity.path)) {
        continue;
      }
      yield entity;
    }
  }

  bool _isExcluded(String path) {
    final normalized = path.replaceAll('\\', '/');
    return const [
      '/.git/',
      '/.dart_tool/',
      '/.fvm/',
      '/.idea/',
      '/build/',
      '/Pods/',
    ].any(normalized.contains);
  }

  File _file(String relativePath) =>
      File.fromUri(root.uri.resolve(relativePath));

  Directory _directory(String relativePath) => Directory.fromUri(
    root.uri.resolve(
      relativePath.endsWith('/') ? relativePath : '$relativePath/',
    ),
  );

  String _relative(File file) => file.path
      .substring(root.path.length)
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/'), '');

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
