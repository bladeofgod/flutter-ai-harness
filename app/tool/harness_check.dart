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
    _validateCiWorkflow();
    _loadMcpServerNames();
    _validateFrontmatter();
    _validateWorkflowReferences();
    _validateTasks();
    _validateMarkdownLinks();
    _validateShellSyntax();
    _validateMobileHosts();
    _validateDependencySources();
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

  void _validateCiWorkflow() {
    const relativePath = '.github/workflows/ci.yml';
    final file = _file(relativePath);
    if (!file.existsSync()) {
      errors.add('缺少持续集成配置：$relativePath');
      return;
    }
    try {
      final document = loadYaml(file.readAsStringSync());
      if (document is! YamlMap || document['jobs'] is! YamlMap) {
        errors.add('$relativePath 必须声明 jobs');
        return;
      }
    } on YamlException catch (error) {
      errors.add('$relativePath 的 YAML 无效：${error.message}');
      return;
    }
    final content = file.readAsStringSync();
    for (final required in const [
      'flutter-version: "3.35.7"',
      'run: make bootstrap',
      'run: make check',
    ]) {
      if (!content.contains(required)) {
        errors.add('$relativePath 缺少必要步骤：$required');
      }
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

  void _validateTasks() {
    final tasks = _directory('docs/tasks');
    if (!tasks.existsSync()) {
      return;
    }

    final activeTask = RegExp(
      r'^docs/tasks/sprint-(\d+)/(S(\d+)-\d{3})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$',
    );
    final completedTask = RegExp(
      r'^docs/tasks/done/(S(\d+)-\d{3})-[a-z0-9]+(?:-[a-z0-9]+)*\.md$',
    );
    final taskIds = <String>{};
    final dependencies = <({String file, String id})>[];

    for (final entity in tasks.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = _basename(entity.path);
      if (!name.startsWith('sprint-')) {
        continue;
      }
      if (!RegExp(r'^sprint-[1-9]\d*$').hasMatch(name)) {
        errors.add('无效 Sprint 目录：docs/tasks/$name');
        continue;
      }
      if (!File.fromUri(entity.uri.resolve('00-overview.md')).existsSync()) {
        errors.add('Sprint 缺少 Overview：docs/tasks/$name/00-overview.md');
      }
    }

    for (final file in _markdownFiles(tasks)) {
      final relative = _relative(file);
      if (RegExp(
        r'^docs/tasks/sprint-[1-9]\d*/00-overview\.md$',
      ).hasMatch(relative)) {
        continue;
      }
      if (RegExp(
        r'^docs/tasks/sprint-[1-9]\d*/\.figma-plan/',
      ).hasMatch(relative)) {
        continue;
      }

      final activeMatch = activeTask.firstMatch(relative);
      final completedMatch = completedTask.firstMatch(relative);
      if (activeMatch == null && completedMatch == null) {
        errors.add('任务卡路径无效：$relative');
        continue;
      }

      final id = activeMatch?.group(2) ?? completedMatch!.group(1)!;
      final idSprint = activeMatch?.group(3) ?? completedMatch!.group(2)!;
      final directorySprint = activeMatch?.group(1);
      if (directorySprint != null && directorySprint != idSprint) {
        errors.add('$relative 的任务 ID $id 与 Sprint 目录不一致');
      }
      if (!taskIds.add(id)) {
        errors.add('重复任务 ID：$id');
      }

      final metadata = _frontmatter(file);
      if (metadata == null) {
        continue;
      }
      final executor = metadata['executor'];
      if (executor is! String ||
          !const {'task-executor', 'bridge-engineer'}.contains(executor) ||
          !_agents.contains(executor)) {
        errors.add('$relative 的 executor 必须是 task-executor 或 bridge-engineer');
      }
      if (activeMatch != null) {
        final uiSpec = metadata['uiSpec'];
        if (uiSpec is! String ||
            !const {'required', 'not-required'}.contains(uiSpec)) {
          errors.add('$relative 的 uiSpec 必须是 required 或 not-required');
        }
      }

      final blockedBy = metadata['blockedBy'];
      if (blockedBy is! YamlList ||
          blockedBy.any(
            (dependency) =>
                dependency is! String ||
                !RegExp(r'^S[1-9]\d*-\d{3}$').hasMatch(dependency),
          )) {
        errors.add('$relative 的 blockedBy 必须是任务 ID 列表');
      } else {
        dependencies.addAll(
          blockedBy.cast<String>().map(
            (dependency) => (file: relative, id: dependency),
          ),
        );
      }

      if (!RegExp(
        '^# ${RegExp.escape(id)}(?:\\s|\$)',
        multiLine: true,
      ).hasMatch(file.readAsStringSync())) {
        errors.add('$relative 的一级标题必须以任务 ID $id 开头');
      }
    }

    for (final dependency in dependencies) {
      if (!taskIds.contains(dependency.id)) {
        errors.add('${dependency.file} 的 blockedBy 引用不存在：${dependency.id}');
      }
    }
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

  void _validateDependencySources() {
    final app = _directory('app');
    if (!app.existsSync()) {
      return;
    }
    final pubspecs =
        app
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (file) =>
                  _basename(file.path) == 'pubspec.yaml' &&
                  !_isExcluded(file.path),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    for (final pubspec in pubspecs) {
      final relative = _relative(pubspec);
      final YamlMap document;
      try {
        final parsed = loadYaml(pubspec.readAsStringSync());
        if (parsed is! YamlMap) {
          errors.add('$relative 的根节点必须是 Map');
          continue;
        }
        document = parsed;
      } on YamlException catch (error) {
        errors.add('$relative 的 YAML 无效：${error.message}');
        continue;
      }

      for (final section in const [
        'dependencies',
        'dev_dependencies',
        'dependency_overrides',
      ]) {
        final dependencies = document[section];
        if (dependencies == null) {
          continue;
        }
        if (dependencies is! YamlMap) {
          errors.add('$relative 的 $section 必须是 Map');
          continue;
        }
        for (final entry in dependencies.entries) {
          _validateDependencySource(
            pubspec,
            '$section.${entry.key}',
            entry.value,
          );
        }
      }
    }
  }

  void _validateDependencySource(File pubspec, String name, Object? value) {
    if (value == null || value is String) {
      return;
    }
    final relative = _relative(pubspec);
    if (value is! YamlMap) {
      errors.add('$relative 的 $name 依赖声明无效');
      return;
    }

    final sourceKeys = const {
      'sdk',
      'path',
      'git',
      'hosted',
    }.where(value.containsKey).toList();
    if (sourceKeys.length > 1) {
      errors.add('$relative 的 $name 不能声明多个依赖来源');
      return;
    }
    if (sourceKeys.isEmpty) {
      if (value.keys.any((key) => key != 'version')) {
        errors.add('$relative 的 $name 包含未知依赖来源');
      }
      return;
    }

    switch (sourceKeys.single) {
      case 'sdk':
        final sdk = value['sdk'];
        if (sdk is! String || !const {'flutter', 'dart'}.contains(sdk)) {
          errors.add('$relative 的 $name 使用不支持的 SDK 依赖');
        }
      case 'path':
        _validatePathDependency(pubspec, name, value['path']);
      case 'git':
        _validateGitDependency(pubspec, name, value['git']);
      case 'hosted':
        _validateHostedDependency(pubspec, name, value['hosted']);
    }
  }

  void _validatePathDependency(File pubspec, String name, Object? value) {
    final relative = _relative(pubspec);
    if (value is! String || value.trim().isEmpty || File(value).isAbsolute) {
      errors.add('$relative 的 $name 不得使用本机绝对 path 依赖');
      return;
    }
    final target = Directory.fromUri(pubspec.parent.uri.resolve('$value/'));
    final targetPubspec = File.fromUri(target.uri.resolve('pubspec.yaml'));
    if (!target.existsSync() || !targetPubspec.existsSync()) {
      errors.add('$relative 的 $name path 依赖不存在或缺少 pubspec.yaml');
      return;
    }
    final rootPath =
        '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}';
    final targetPath =
        '${target.resolveSymbolicLinksSync()}${Platform.pathSeparator}';
    if (!targetPath.startsWith(rootPath)) {
      errors.add('$relative 的 $name path 依赖越出仓库');
    }
  }

  void _validateGitDependency(File pubspec, String name, Object? value) {
    final relative = _relative(pubspec);
    if (value is! YamlMap) {
      errors.add('$relative 的 $name Git 依赖必须声明 url 和完整 Commit ref');
      return;
    }
    final url = value['url'];
    final ref = value['ref'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      errors.add('$relative 的 $name Git 依赖必须使用无凭据 HTTPS URL');
    }
    if (ref is! String || !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(ref)) {
      errors.add('$relative 的 $name Git 依赖必须锁定完整 Commit ref');
    }
  }

  void _validateHostedDependency(File pubspec, String name, Object? value) {
    final relative = _relative(pubspec);
    final Object? url = value is YamlMap ? value['url'] : value;
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'pub.dev' ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      errors.add('$relative 的 $name 不得使用非 Pub.dev Hosted 来源');
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
        'Makefile',
        '.gitignore',
        '.mcp.json',
        'app/apps/demo/ios/Runner.xcodeproj/project.pbxproj',
        'app/apps/demo/android/app/build.gradle.kts',
      ])
        if (_file(path).existsSync()) _file(path),
      ..._textFiles(_directory('.claude')).where(_isTextFile),
      ..._textFiles(_directory('.github')).where(_isTextFile),
      ..._textFiles(_directory('app')).where(_isTextFile),
      ..._textFiles(_directory('docs')).where(_isTextFile),
      ..._textFiles(_directory('scripts')).where(_isTextFile),
    ];
    final seen = <String>{};
    for (final file in candidates) {
      if (!seen.add(file.path)) {
        continue;
      }
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
      '/android/local.properties',
      '/ios/Flutter/Generated.xcconfig',
      '/ios/Flutter/flutter_export_environment.sh',
      '/ios/Flutter/ephemeral/',
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
