import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import 'codex_adapters.dart';
import 'implementation_digest.dart';

const _taskExecutors = {
  'task-executor',
  'android-engineer',
  'ios-engineer',
  'bridge-engineer',
};
const _taskPlatforms = {'flutter', 'android', 'ios'};
const _taskWorkKinds = {
  'documentation',
  'planning',
  'harness',
  'flutter',
  'dart-client',
  'capability-contract',
  'native',
  'bridge-adapter',
  'bridge-contract',
  'integration',
  'quality-gate',
};

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
    _validateClaudePermissions();
    _validateCiWorkflow();
    _loadMcpServerNames();
    _validateFrontmatter();
    _validateCodexAdapters();
    _validateWorkflowReferences();
    _validateTasks();
    _validateNativeArchitectureDocumentation();
    _validateCapabilityContracts();
    _validateWireContracts();
    _validateMarkdownLinks();
    _validateShellSyntax();
    _validateMobileHosts();
    _validateDependencySources();
    _validatePrivatePaths();
  }

  void _validateCodexAdapters() {
    errors.addAll(CodexAdapterManager(root).check());
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
    final YamlMap jobs;
    try {
      final document = loadYaml(file.readAsStringSync());
      if (document is! YamlMap || document['jobs'] is! YamlMap) {
        errors.add('$relativePath 必须声明 jobs');
        return;
      }
      jobs = document['jobs'] as YamlMap;
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
    _validateCiBuildJob(
      jobs,
      relativePath,
      name: 'android-build',
      runnerPrefix: 'ubuntu-',
      command:
          'TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh '
          'build apk --debug',
      gateCommand: 'make media-capture-android',
    );
    _validateCiBuildJob(
      jobs,
      relativePath,
      name: 'ios-build',
      runnerPrefix: 'macos-',
      command:
          'TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh '
          'build ios --debug --no-codesign',
      gateCommand: 'make media-capture-ios',
    );
  }

  void _validateCiBuildJob(
    YamlMap jobs,
    String path, {
    required String name,
    required String runnerPrefix,
    required String command,
    required String gateCommand,
  }) {
    final job = jobs[name];
    if (job is! YamlMap) {
      errors.add('$path 缺少 $name Job');
      return;
    }
    final runner = job['runs-on'];
    if (runner is! String || !runner.startsWith(runnerPrefix)) {
      errors.add('$path 的 $name 必须使用 $runnerPrefix Runner');
    }
    final steps = job['steps'];
    if (steps is! YamlList ||
        !steps.whereType<YamlMap>().any((step) => step['run'] == command)) {
      errors.add('$path 的 $name 缺少构建命令：$command');
    }
    if (steps is! YamlList ||
        !steps.whereType<YamlMap>().any((step) => step['run'] == gateCommand)) {
      errors.add('$path 的 $name 缺少平台专项门禁：$gateCommand');
    }
  }

  void _validateClaudePermissions() {
    const path = '.claude/settings.json';
    final file = _file(path);
    if (!file.existsSync()) {
      return;
    }
    try {
      final document = jsonDecode(file.readAsStringSync());
      if (document is! Map<String, Object?> ||
          document['permissions'] is! Map<String, Object?>) {
        errors.add('$path 必须声明 permissions');
        return;
      }
      final permissions = document['permissions'] as Map<String, Object?>;
      final allow = _jsonStringSet(permissions['allow']);
      final deny = _jsonStringSet(permissions['deny']);
      if (allow == null || deny == null) {
        errors.add('$path 的 permissions.allow/deny 必须是字符串列表');
        return;
      }
      if (allow.contains('Bash(git *)')) {
        errors.add('$path 不得无条件允许全部 Git 命令');
      }
      for (final required in const {
        'Bash(git reset *)',
        'Bash(git clean *)',
        'Bash(git checkout -- *)',
        'Bash(git restore *)',
      }) {
        if (!deny.contains(required)) {
          errors.add('$path 缺少破坏性 Git 拒绝规则：$required');
        }
      }
    } on FormatException {
      // _validateJson reports the actionable syntax error.
    }
  }

  Set<String>? _jsonStringSet(Object? value) {
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      return null;
    }
    return value.cast<String>().toSet();
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
      } else {
        _validateSkillPaths(file, metadata, paths.cast<String>());
      }
    }, nestedEntry: 'SKILL.md');
    _validateDefinitions('.claude/agents', _agents, (file, metadata) {
      _requireString(file, metadata, 'name');
      _requireString(file, metadata, 'description');
      _requireStringOrList(file, metadata, 'tools');
      _validateAgentSkillReferences(file, metadata);
      _validateReviewerTools(file, metadata);
      _validateNativeEngineer(file, metadata);
    });
    _validateDefinitions('.claude/commands', _commands, (file, metadata) {
      _requireString(file, metadata, 'description');
    });
  }

  void _validateAgentSkillReferences(File file, YamlMap metadata) {
    final value = metadata['skills'];
    if (value == null) {
      return;
    }
    if (value is! YamlList ||
        value.isEmpty ||
        value.any((item) => item is! String || item.trim().isEmpty)) {
      errors.add('${_relative(file)} 的 skills 必须是非空 Skill 名称列表');
      return;
    }

    final seen = <String>{};
    for (final item in value) {
      final name = item as String;
      if (!seen.add(name)) {
        errors.add('${_relative(file)} 的 skills 不得重复：$name');
      }
      if (!_skills.contains(name)) {
        errors.add('${_relative(file)} 引用不存在的 Skill：$name');
      }
    }
  }

  void _validateSkillPaths(File file, YamlMap metadata, List<String> paths) {
    final relative = _relative(file);
    if (paths.toSet().length != paths.length) {
      errors.add('$relative 的 paths 不得重复');
    }
    if (paths.any(
      (path) =>
          path.startsWith('/') ||
          path.contains('\\') ||
          path.split('/').any((segment) => segment.isEmpty) ||
          path.split('/').contains('..'),
    )) {
      errors.add('$relative 的 paths 必须是安全的仓库相对正斜杠 glob');
    }

    final name = metadata['name'];
    if (name == 'kotlin-android-standards') {
      const expected = {
        'app/native/android/**',
        'app/apps/*/android/**',
        'app/packages/*/android/**',
      };
      if (paths.toSet().difference(expected).isNotEmpty ||
          expected.difference(paths.toSet()).isNotEmpty ||
          paths.any((path) => path.contains('/ios/'))) {
        errors.add('$relative 的 paths 必须只覆盖约定 Android 源码范围');
      }
    } else if (name == 'swift-ios-standards') {
      const expected = {
        'app/native/ios/**',
        'app/apps/*/ios/**',
        'app/packages/*/ios/**',
      };
      if (paths.toSet().difference(expected).isNotEmpty ||
          expected.difference(paths.toSet()).isNotEmpty ||
          paths.any((path) => path.contains('/android/'))) {
        errors.add('$relative 的 paths 必须只覆盖约定 iOS 源码范围');
      }
    } else if (name == 'native-testing-strategy') {
      final hasAndroid = paths.any((path) => path.contains('/android/'));
      final hasIos = paths.any((path) => path.contains('/ios/'));
      final onlyNativeTests = paths.every(
        (path) =>
            (path.contains('/android/') || path.contains('/ios/')) &&
            (path.contains('/test/') ||
                path.contains('/androidTest/') ||
                path.contains('Tests/')) &&
            !path.endsWith('.dart') &&
            !path.contains('/integration_test/'),
      );
      if (!hasAndroid || !hasIos || !onlyNativeTests) {
        errors.add('$relative 的 paths 必须同时且只覆盖 Android/iOS 原生测试范围');
      }
    }
  }

  void _validateReviewerTools(File file, YamlMap metadata) {
    if (!const {'reviewer', 'security-reviewer'}.contains(metadata['name'])) {
      return;
    }
    final tools = _toolNames(metadata['tools']);
    if (tools == null ||
        tools.isEmpty ||
        tools.any((tool) => !const {'Read', 'Grep', 'Glob'}.contains(tool))) {
      errors.add(
        '${_relative(file)} 的只读 Reviewer 只能使用 Read、Grep、Glob，'
        '不得获得 Bash 或写入工具',
      );
    }
  }

  void _validateNativeEngineer(File file, YamlMap metadata) {
    final name = metadata['name'];
    if (!const {'android-engineer', 'ios-engineer'}.contains(name)) {
      return;
    }
    final expectedSkills = name == 'android-engineer'
        ? const ['kotlin-android-standards', 'native-testing-strategy']
        : const ['swift-ios-standards', 'native-testing-strategy'];
    final rawSkills = metadata['skills'];
    final hasExpectedSkills =
        rawSkills is YamlList &&
        rawSkills.length == expectedSkills.length &&
        Iterable<int>.generate(
          expectedSkills.length,
        ).every((index) => rawSkills[index] == expectedSkills[index]);
    if (!hasExpectedSkills) {
      errors.add(
        '${_relative(file)} 的 skills 必须精确为 ${expectedSkills.join(', ')}',
      );
    }
    const requiredTools = {'Read', 'Write', 'Edit', 'Bash', 'Grep', 'Glob'};
    final tools = _toolNames(metadata['tools']);
    if (tools == null ||
        tools.difference(requiredTools).isNotEmpty ||
        requiredTools.difference(tools).isNotEmpty) {
      errors.add('${_relative(file)} 只能使用实现所需的 Read、Write、Edit、Bash、Grep、Glob');
    }
    final content = file.readAsStringSync();
    for (final boundary in const ['不 commit、push、发布或读取凭据', '不使用无约束外部网络']) {
      if (!content.contains(boundary)) {
        errors.add('${_relative(file)} 缺少执行能力边界：$boundary');
      }
    }
  }

  Set<String>? _toolNames(Object? rawTools) {
    if (rawTools is String) {
      return rawTools
          .split(',')
          .map((tool) => tool.trim())
          .where((tool) => tool.isNotEmpty)
          .toSet();
    }
    if (rawTools is YamlList && rawTools.every((tool) => tool is String)) {
      return rawTools.cast<String>().map((tool) => tool.trim()).toSet();
    }
    return null;
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
    if (!_validateTaskRoot(tasks)) {
      return;
    }

    const taskSlugPattern = r'[a-z][a-z0-9]*(?:-[a-z0-9]+)*';
    final taskSlug = RegExp('^$taskSlugPattern\$');
    final activeTask = RegExp('^docs/tasks/($taskSlugPattern)\\.md\$');
    final completedTask = RegExp('^docs/tasks/done/($taskSlugPattern)\\.md\$');
    final taskSlugs = <String>{};
    final completedTaskSlugs = <String>{};
    final dependencies =
        <({String file, String owner, String slug, bool ownerCompleted})>[];
    final dependencyGraph = <String, Set<String>>{};

    _validateTaskNodes(tasks);

    for (final file in _markdownFiles(tasks)) {
      final relative = _relative(file);
      final activeMatch = activeTask.firstMatch(relative);
      final completedMatch = completedTask.firstMatch(relative);
      if (activeMatch == null && completedMatch == null) {
        errors.add('任务卡路径无效：$relative');
        continue;
      }

      final slug = activeMatch?.group(1) ?? completedMatch!.group(1)!;
      if (!taskSlugs.add(slug)) {
        errors.add('重复任务 slug：$slug');
      }
      if (completedMatch != null) {
        completedTaskSlugs.add(slug);
      }

      final metadata = _frontmatter(file);
      if (metadata == null) {
        continue;
      }
      final executor = metadata['executor'];
      if (executor is! String ||
          !_taskExecutors.contains(executor) ||
          !_agents.contains(executor)) {
        errors.add('$relative 的 executor 不在允许值中或缺少对应 Agent');
      }
      _validateTaskScope(
        relative,
        metadata,
        completed: completedMatch != null,
        executor: executor is String ? executor : null,
      );
      if (metadata.containsKey('uiSpec')) {
        errors.add('$relative 不得声明 uiSpec；UI 自动化由人独立安排');
      }
      final hasSecurityReview = metadata.containsKey('securityReview');
      final securityReview = metadata['securityReview'];
      if (hasSecurityReview && securityReview != 'required') {
        errors.add('$relative 的 securityReview 只允许 required，低风险任务应省略该字段');
      }
      if (completedMatch != null) {
        _validateCompletedTaskArtifacts(
          file,
          slug,
          requiresSecurityReview: securityReview == 'required',
        );
      }

      final blockedBy = metadata['blockedBy'];
      if (blockedBy is! YamlList ||
          blockedBy.any(
            (dependency) =>
                dependency is! String || !taskSlug.hasMatch(dependency),
          )) {
        errors.add('$relative 的 blockedBy 必须是任务 slug 列表');
      } else {
        final dependencySlugs = blockedBy.cast<String>();
        if (dependencySlugs.toSet().length != dependencySlugs.length) {
          errors.add('$relative 的 blockedBy 不得包含重复任务 slug');
        }
        dependencyGraph[slug] = dependencySlugs.toSet();
        dependencies.addAll(
          dependencySlugs.map(
            (dependency) => (
              file: relative,
              owner: slug,
              slug: dependency,
              ownerCompleted: completedMatch != null,
            ),
          ),
        );
      }

      if (!RegExp(
        r'^#\s+\S',
        multiLine: true,
      ).hasMatch(file.readAsStringSync())) {
        errors.add('$relative 必须包含非空一级标题');
      }
    }

    for (final dependency in dependencies) {
      if (dependency.owner == dependency.slug) {
        errors.add('${dependency.file} 的 blockedBy 不得引用自身：${dependency.slug}');
      }
      if (!taskSlugs.contains(dependency.slug)) {
        errors.add('${dependency.file} 的 blockedBy 引用不存在：${dependency.slug}');
      }
      if (dependency.ownerCompleted &&
          taskSlugs.contains(dependency.slug) &&
          !completedTaskSlugs.contains(dependency.slug)) {
        errors.add('${dependency.file} 已归档，但依赖任务尚未归档：${dependency.slug}');
      }
    }
    _validateTaskDependencyCycles(dependencyGraph);
  }

  bool _validateTaskRoot(Directory tasks) {
    for (final relative in const ['docs', 'docs/tasks']) {
      final type = FileSystemEntity.typeSync(
        root.uri.resolve(relative).toFilePath(),
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        return false;
      }
      if (type != FileSystemEntityType.directory) {
        errors.add('$relative 必须是普通目录，且路径组件不得为符号链接');
        return false;
      }
    }

    try {
      final rootPath = root.resolveSymbolicLinksSync();
      final taskPath = tasks.resolveSymbolicLinksSync();
      final rootPrefix = '$rootPath${Platform.pathSeparator}';
      if (!taskPath.startsWith(rootPrefix)) {
        errors.add('docs/tasks 解析后的真实路径必须位于仓库内');
        return false;
      }
    } on FileSystemException catch (error) {
      errors.add('无法解析 docs/tasks 的真实路径：${error.message}');
      return false;
    }
    return true;
  }

  void _validateTaskNodes(Directory tasks) {
    for (final entity in tasks.listSync(recursive: true, followLinks: false)) {
      final relative = _relativeEntity(entity);
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        errors.add('docs/tasks/ 不允许符号链接：$relative');
      } else if (type == FileSystemEntityType.directory) {
        if (relative != 'docs/tasks/done') {
          errors.add('docs/tasks/ 只允许 done 子目录：$relative');
        }
      } else if (type == FileSystemEntityType.file) {
        if (!relative.endsWith('.md')) {
          errors.add('docs/tasks/ 只允许 Markdown 任务卡：$relative');
        }
      } else {
        errors.add('docs/tasks/ 不允许特殊文件节点：$relative');
      }
    }
  }

  void _validateTaskScope(
    String relative,
    YamlMap metadata, {
    required bool completed,
    required String? executor,
  }) {
    final hasPlatforms = metadata.containsKey('platforms');
    final hasWorkKinds = metadata.containsKey('workKinds');
    if (completed && !hasPlatforms && !hasWorkKinds) {
      return;
    }
    if (!hasPlatforms || !hasWorkKinds) {
      errors.add('$relative 必须同时声明 platforms 和 workKinds');
      return;
    }

    final rawPlatforms = metadata['platforms'];
    final rawWorkKinds = metadata['workKinds'];
    final validPlatforms =
        rawPlatforms is YamlList &&
        rawPlatforms.every((item) => item is String);
    final validWorkKinds =
        rawWorkKinds is YamlList &&
        rawWorkKinds.isNotEmpty &&
        rawWorkKinds.every((item) => item is String);
    if (!validPlatforms) {
      errors.add('$relative 的 platforms 必须是平台字符串列表');
    }
    if (!validWorkKinds) {
      errors.add('$relative 的 workKinds 必须是非空工作类型字符串列表');
    }
    if (!validPlatforms || !validWorkKinds) {
      return;
    }

    final platforms = rawPlatforms.cast<String>();
    final workKinds = rawWorkKinds.cast<String>();
    if (platforms.toSet().length != platforms.length) {
      errors.add('$relative 的 platforms 不得重复');
    }
    if (workKinds.toSet().length != workKinds.length) {
      errors.add('$relative 的 workKinds 不得重复');
    }
    final unknownPlatforms = platforms.toSet().difference(_taskPlatforms);
    if (unknownPlatforms.isNotEmpty) {
      errors.add('$relative 的 platforms 包含未知值：${unknownPlatforms.join(', ')}');
    }
    final unknownWorkKinds = workKinds.toSet().difference(_taskWorkKinds);
    if (unknownWorkKinds.isNotEmpty) {
      errors.add('$relative 的 workKinds 包含未知值：${unknownWorkKinds.join(', ')}');
    }
    if (unknownPlatforms.isNotEmpty || unknownWorkKinds.isNotEmpty) {
      return;
    }
    if (platforms.isEmpty &&
        !workKinds.every(
          const {'documentation', 'planning', 'harness'}.contains,
        )) {
      errors.add('$relative 只有 documentation、planning、harness 可以使用空 platforms');
      return;
    }

    final expected = _expectedExecutor(platforms.toSet(), workKinds.toSet());
    if (expected == null) {
      errors.add('$relative 的 platforms/workKinds 组合跨越多个 Executor 或范围无效');
    } else if (executor != expected) {
      errors.add('$relative 的结构化范围必须使用 executor: $expected');
    }
  }

  String? _expectedExecutor(Set<String> platforms, Set<String> workKinds) {
    final substantiveKinds = workKinds.difference(const {'documentation'});
    final owners = <String>{};
    for (final kind
        in substantiveKinds.isEmpty
            ? const {'documentation'}
            : substantiveKinds) {
      switch (kind) {
        case 'native':
        case 'bridge-adapter':
          final owner = _singlePlatformOwner(platforms, allowFlutter: false);
          if (owner == null || owner == 'task-executor') {
            return null;
          }
          owners.add(owner);
        case 'quality-gate':
          final owner = _singlePlatformOwner(platforms, allowFlutter: true);
          if (owner == null) {
            return null;
          }
          owners.add(owner);
        case 'bridge-contract':
          if (platforms.length < 2 || !platforms.contains('flutter')) {
            return null;
          }
          owners.add('bridge-engineer');
        case 'integration':
          if (platforms.length > 1) {
            owners.add('bridge-engineer');
          } else {
            final owner = _singlePlatformOwner(platforms, allowFlutter: true);
            if (owner == null) {
              return null;
            }
            owners.add(owner);
          }
        case 'documentation':
        case 'planning':
        case 'harness':
        case 'capability-contract':
          owners.add('task-executor');
        case 'flutter':
        case 'dart-client':
          if (platforms.length != 1 || !platforms.contains('flutter')) {
            return null;
          }
          owners.add('task-executor');
      }
    }
    return owners.length == 1 ? owners.single : null;
  }

  String? _singlePlatformOwner(
    Set<String> platforms, {
    required bool allowFlutter,
  }) {
    if (platforms.length != 1) {
      return null;
    }
    return switch (platforms.single) {
      'android' => 'android-engineer',
      'ios' => 'ios-engineer',
      'flutter' when allowFlutter => 'task-executor',
      _ => null,
    };
  }

  void _validateCompletedTaskArtifacts(
    File task,
    String slug, {
    required bool requiresSecurityReview,
  }) {
    final basename = _basename(task.path).replaceFirst(RegExp(r'\.md$'), '');
    _validatePassedTaskReview(
      task,
      slug,
      'docs/reviews/execute-$basename.md',
      label: 'Review',
    );
    if (requiresSecurityReview) {
      _validatePassedTaskReview(
        task,
        slug,
        'docs/reviews/security-$basename.md',
        label: 'Security Review',
        requireImplementationBinding: true,
      );
    }

    final evidencePath = 'docs/reviews/test-evidence/$basename.log';
    final evidence = _file(evidencePath);
    if (!evidence.existsSync()) {
      errors.add('${_relative(task)} 归档前缺少测试证据：$evidencePath');
    } else if (!RegExp(
      r'^Exit code: -?\d+$',
      multiLine: true,
    ).hasMatch(evidence.readAsStringSync())) {
      errors.add('$evidencePath 缺少命令退出码');
    }
  }

  void _validatePassedTaskReview(
    File task,
    String slug,
    String reviewPath, {
    required String label,
    bool requireImplementationBinding = false,
  }) {
    final review = _file(reviewPath);
    if (!review.existsSync()) {
      errors.add('${_relative(task)} 归档前缺少 $label：$reviewPath');
    } else {
      final metadata = _frontmatter(review);
      if (metadata != null) {
        if (metadata['task'] != slug) {
          errors.add('$reviewPath 的 task 必须是 $slug');
        }
        if (metadata['status'] != 'passed' ||
            metadata['p0'] != 0 ||
            metadata['p1'] != 0) {
          errors.add('$reviewPath 必须声明 passed 且 P0/P1 为 0');
        }
        if (requireImplementationBinding) {
          _validateSecurityReviewBinding(reviewPath, metadata);
        }
      }
    }
  }

  void _validateSecurityReviewBinding(String reviewPath, YamlMap metadata) {
    final rawFiles = metadata['implementationFiles'];
    if (rawFiles is! YamlList ||
        rawFiles.isEmpty ||
        rawFiles.any((path) => path is! String || path.trim().isEmpty)) {
      errors.add('$reviewPath 的任务门禁报告必须声明非空 implementationFiles');
      return;
    }

    final files = rawFiles.cast<String>();
    if (files.toSet().length != files.length) {
      errors.add('$reviewPath 的 implementationFiles 不得重复');
      return;
    }
    if (files.any((path) => path.startsWith('docs/reviews/'))) {
      errors.add('$reviewPath 的 implementationFiles 不得包含 Review 报告自身');
      return;
    }

    final declaredDigest = metadata['implementationDigest'];
    if (declaredDigest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(declaredDigest)) {
      errors.add('$reviewPath 必须声明小写 SHA-256 implementationDigest');
      return;
    }

    try {
      final calculatedDigest = calculateImplementationDigest(root, files);
      if (calculatedDigest != declaredDigest) {
        errors.add('$reviewPath 的 implementationDigest 与当前实现不一致');
      }
    } on FileSystemException catch (error) {
      errors.add('$reviewPath 无法计算实现摘要：${error.message}');
    } on FormatException catch (error) {
      errors.add('$reviewPath 无法计算实现摘要：${error.message}');
    }
  }

  void _validateTaskDependencyCycles(Map<String, Set<String>> graph) {
    final visited = <String>{};
    final visiting = <String>{};
    final path = <String>[];
    final reported = <String>{};

    void visit(String taskSlug) {
      if (visited.contains(taskSlug)) {
        return;
      }
      final cycleStart = path.indexOf(taskSlug);
      if (visiting.contains(taskSlug) && cycleStart >= 0) {
        final cycle = [...path.sublist(cycleStart), taskSlug];
        final signature = cycle.toSet().toList()..sort();
        if (reported.add(signature.join(','))) {
          errors.add('任务依赖存在循环：${cycle.join(' -> ')}');
        }
        return;
      }

      visiting.add(taskSlug);
      path.add(taskSlug);
      for (final dependency in graph[taskSlug] ?? const <String>{}) {
        if (graph.containsKey(dependency)) {
          visit(dependency);
        }
      }
      path.removeLast();
      visiting.remove(taskSlug);
      visited.add(taskSlug);
    }

    for (final taskSlug in graph.keys) {
      visit(taskSlug);
    }
  }

  void _validateNativeArchitectureDocumentation() {
    const architecturePath = 'docs/native-architecture.md';
    final architecture = _file(architecturePath);

    final claude = _file('CLAUDE.md');
    if (!claude.existsSync()) {
      errors.add('缺少项目契约文档：CLAUDE.md');
    } else {
      final importantReferences = _markdownLevelTwoSection(
        claude.readAsStringSync(),
        '重要参考',
      );
      if (importantReferences == null) {
        errors.add('CLAUDE.md 缺少“## 重要参考”区段');
      } else if (!_contentLinksTo(claude, importantReferences, architecture)) {
        errors.add('CLAUDE.md 的“## 重要参考”必须链接 $architecturePath');
      }
    }

    for (final entry in const {
      'docs/architecture.md': '跨运行时总览',
      'docs/infrastructure-modules.md': '基础模块索引',
      'docs/bridge/README.md': 'Bridge 契约',
    }.entries) {
      final source = _file(entry.key);
      if (!source.existsSync()) {
        errors.add('缺少${entry.value}文档：${entry.key}');
      } else if (!_linksTo(source, architecture)) {
        errors.add('${entry.key} 必须链接 $architecturePath');
      }
    }

    if (!architecture.existsSync()) {
      errors.add('缺少原生架构文档：$architecturePath');
      return;
    }

    final contract = _readNativeArchitectureContract(architecture);
    if (contract == null) {
      return;
    }

    _validateExactJsonKeys(contract, const {
      'schemaVersion',
      'hosts',
      'nativeModules',
      'bridgePackages',
      'layoutTemplates',
      'components',
      'dependencyEdges',
      'forbiddenDependencyEdges',
    }, '原生架构契约');
    if (contract['schemaVersion'] != 1) {
      errors.add('$architecturePath 的 schemaVersion 必须是 1');
    }
    _validateNativeArchitectureHosts(contract['hosts']);
    _validateNativeModules(contract['nativeModules']);
    _validateNativeBridgePackages(contract['bridgePackages']);
    _validateNativeLayoutTemplates(contract['layoutTemplates']);
    _validateNativeComponents(contract['components']);

    final dependencies = _nativeDependencyEdges(
      contract['dependencyEdges'],
      'dependencyEdges',
    );
    final forbiddenDependencies = _nativeDependencyEdges(
      contract['forbiddenDependencyEdges'],
      'forbiddenDependencyEdges',
    );
    const requiredDependencies = {
      'android_native_consumer->android_native_module',
      'ios_native_consumer->ios_native_module',
      'flutter_consumer->dart_client',
      'dart_client->channel',
      'channel->android_bridge_adapter',
      'channel->ios_bridge_adapter',
      'android_bridge_adapter->android_native_module',
      'ios_bridge_adapter->ios_native_module',
      'host->native_module',
      'host->bridge_adapter_registration',
    };
    for (final dependency in requiredDependencies) {
      if (dependencies != null && !dependencies.contains(dependency)) {
        errors.add('$architecturePath 的 dependencyEdges 缺少：$dependency');
      }
    }
    if (dependencies != null) {
      for (final dependency in dependencies.difference(requiredDependencies)) {
        errors.add('$architecturePath 的 dependencyEdges 包含未允许边：$dependency');
      }
    }

    const requiredForbiddenDependencies = {'native_module->flutter'};
    if (forbiddenDependencies != null) {
      for (final dependency in requiredForbiddenDependencies) {
        if (!forbiddenDependencies.contains(dependency)) {
          errors.add(
            '$architecturePath 的 forbiddenDependencyEdges 缺少：$dependency',
          );
        }
      }
      for (final dependency in forbiddenDependencies.difference(
        requiredForbiddenDependencies,
      )) {
        errors.add(
          '$architecturePath 的 forbiddenDependencyEdges 包含未声明边：$dependency',
        );
      }
    }
    const nativeModuleMustNotDependOnFlutter = 'native_module->flutter';
    if (dependencies != null &&
        dependencies.contains(nativeModuleMustNotDependOnFlutter)) {
      errors.add(
        '$architecturePath 的 dependencyEdges 不得包含禁止边：'
        '$nativeModuleMustNotDependOnFlutter',
      );
    }
  }

  void _validateCapabilityContracts() {
    const schemaPath = 'docs/native/contracts/capability.schema.json';
    const contractPath =
        'docs/infrastructure/contracts/media-capture.capability.json';
    const indexPath = 'docs/infrastructure-modules.md';
    const detailPath = 'docs/infrastructure/media-capture.md';

    final schema = _readJsonObject(schemaPath, 'Capability JSON Schema');
    final contract = _readJsonObject(
      contractPath,
      'Media Capture Capability Contract',
    );
    final index = _file(indexPath);
    final detail = _file(detailPath);

    if (!index.existsSync()) {
      errors.add('缺少基础模块索引：$indexPath');
    } else {
      _validateMediaCaptureIndex(index, detail);
    }
    if (!detail.existsSync()) {
      errors.add('缺少 Media Capture 能力文档：$detailPath');
    } else {
      for (final target in [
        index,
        _file(schemaPath),
        _file(contractPath),
        _file('docs/native-architecture.md'),
      ]) {
        if (!_linksTo(detail, target)) {
          errors.add('$detailPath 必须链接 ${_relative(target)}');
        }
      }
    }

    if (schema != null) {
      _validateCapabilitySchema(schema, schemaPath);
    }
    if (contract != null) {
      _validateMediaCaptureCapability(contract, contractPath);
    }
  }

  Map<String, Object?>? _readJsonObject(String path, String label) {
    final file = _file(path);
    if (!file.existsSync()) {
      errors.add('缺少$label：$path');
      return null;
    }
    try {
      final value = jsonDecode(file.readAsStringSync());
      if (value is! Map<String, Object?>) {
        errors.add('$path 的根节点必须是 JSON Object');
        return null;
      }
      return value;
    } on FormatException catch (error) {
      errors.add('$path 不是有效 JSON：${error.message}');
      return null;
    }
  }

  void _validateMediaCaptureIndex(File index, File detail) {
    final rows = index
        .readAsLinesSync()
        .where((line) => line.startsWith('| 原生媒体拍摄 |'))
        .toList();
    if (rows.length != 1) {
      errors.add('docs/infrastructure-modules.md 必须且只能登记一条原生媒体拍摄能力');
      return;
    }
    final row = rows.single;
    for (final requiredValue in const [
      'app/native/android/media_capture/',
      'app/native/ios/MediaCapture/',
      'Android/iOS Media Capture Native Module',
      '已批准',
      '已实现',
      'Customer Support',
      'Shoppe 订单评价',
    ]) {
      if (!row.contains(requiredValue)) {
        errors.add('原生媒体拍摄索引行缺少：$requiredValue');
      }
    }
    if (!_contentLinksTo(index, row, detail)) {
      errors.add('原生媒体拍摄索引行必须链接 docs/infrastructure/media-capture.md');
    }
  }

  void _validateCapabilitySchema(Map<String, Object?> schema, String path) {
    const expectedSchemaDigest =
        'fc491641bbdf5abb3e4ad73ab2888766da1745f2b6f32d0519785169c7be276e';
    final schemaDigest = calculateImplementationDigest(root, [path]);
    if (schemaDigest != expectedSchemaDigest) {
      errors.add('$path 的完整 Version 4 Schema 摘要不匹配');
    }
    const fields = {
      r'$schema',
      'contractId',
      'capabilityVersion',
      'versionHistory',
      'platform',
      'operation',
      'field',
      'request',
      'result',
      'event',
      'stateMachines',
      'failure',
      'permission',
      'lifecycle',
      'resourcePolicy',
    };
    _validateCapabilityExactKeys(schema, const {
      r'$schema',
      r'$id',
      'title',
      'description',
      'type',
      'additionalProperties',
      'required',
      'properties',
      r'$defs',
    }, '$path 根节点');
    if (schema[r'$schema'] != 'https://json-schema.org/draft/2020-12/schema') {
      errors.add('$path 必须使用 JSON Schema Draft 2020-12');
    }
    if (schema[r'$id'] != 'urn:flutter-ai-harness:schema:native-capability:4') {
      errors.add('$path 必须使用稳定的非网络 \$id');
    }
    if (schema['type'] != 'object' || schema['additionalProperties'] != false) {
      errors.add('$path 根节点必须是拒绝未知字段的 object schema');
    }
    final required = _capabilityStringSet(schema['required'], '$path required');
    if (required != null && !_sameStringSet(required, fields)) {
      errors.add('$path required 必须精确声明 Capability 顶层字段');
    }
    final properties = _capabilityObject(
      schema['properties'],
      '$path properties',
    );
    if (properties != null &&
        !_sameStringSet(properties.keys.toSet(), fields)) {
      errors.add('$path properties 必须精确声明 Capability 顶层字段');
    }
    final definitions = _capabilityObject(schema[r'$defs'], '$path \$defs');
    const requiredDefinitions = {
      'stableId',
      'semanticEntry',
      'versionEntry',
      'platformContract',
      'platformDifference',
      'operation',
      'operationValidFrom',
      'dataShape',
      'field',
      'fieldValidation',
      'conditionalRule',
      'stateMachine',
      'state',
      'transition',
      'emission',
      'failure',
      'permissionContract',
      'permissionResource',
      'lifecycleContract',
      'resourcePolicy',
      'resource',
      'ownershipPhase',
      'handlePolicy',
      'leasePolicy',
      'attachmentPolicy',
      'renderSurfacePolicy',
      'platformRenderSurface',
      'renderSurfaceFactoryContract',
      'renderSurfaceFactoryInput',
      'renderSurfaceFactoryOutput',
      'renderSurfaceDiagnosticPolicy',
      'diagnosticFieldValueSource',
      'diagnosticValueReference',
      'renderTargetConformance',
      'renderMountBinding',
      'boundedCopyPolicy',
      'roleBinding',
      'preconditionPolicy',
      'boundPolicy',
      'transformPolicy',
      'ownershipTransferPolicy',
      'executionPolicy',
      'preAccessRegistrationPolicy',
      'concurrencyBound',
      'workBudget',
      'raceArbitrationPolicy',
      'raceTriggerPolicy',
      'streamingCopyPolicy',
      'streamingSourceRepresentation',
      'streamingSinkProtocol',
      'streamingSinkMethod',
      'streamingExecutionPolicy',
      'streamingTerminalPolicy',
      'streamingFailureBehavior',
      'cleanupRule',
    };
    if (definitions != null &&
        !_sameStringSet(definitions.keys.toSet(), requiredDefinitions)) {
      errors.add('$path \$defs 必须精确声明受约束的 Capability 结构');
    }
    if (definitions?['stableId'] case final Map<String, Object?> stableId) {
      if (stableId['pattern'] != r'^[a-z][a-z0-9_]*$') {
        errors.add('$path 必须用固定 pattern 约束稳定语义 ID');
      }
    } else {
      errors.add('$path 缺少 stableId 定义');
    }
    if (properties != null) {
      _validateCapabilitySchemaPropertyRef(
        properties,
        'contractId',
        '#/\$defs/stableId',
        path,
      );
      for (final entry in const {
        'platform': '#/\$defs/platformContract',
        'permission': '#/\$defs/permissionContract',
        'lifecycle': '#/\$defs/lifecycleContract',
        'resourcePolicy': '#/\$defs/resourcePolicy',
      }.entries) {
        _validateCapabilitySchemaPropertyRef(
          properties,
          entry.key,
          entry.value,
          path,
        );
      }
      for (final entry in const {
        'versionHistory': '#/\$defs/versionEntry',
        'operation': '#/\$defs/operation',
        'field': '#/\$defs/field',
        'request': '#/\$defs/dataShape',
        'result': '#/\$defs/dataShape',
        'event': '#/\$defs/dataShape',
        'stateMachines': '#/\$defs/stateMachine',
        'failure': '#/\$defs/failure',
      }.entries) {
        _validateCapabilitySchemaArrayItemRef(
          properties,
          entry.key,
          entry.value,
          path,
        );
      }
    }
    if (definitions != null) {
      final field = _capabilityObject(
        definitions['field'],
        '$path \$defs.field',
      );
      final dataShape = _capabilityObject(
        definitions['dataShape'],
        '$path \$defs.dataShape',
      );
      final dataShapeProperties = dataShape == null
          ? null
          : _capabilityObject(
              dataShape['properties'],
              '$path \$defs.dataShape.properties',
            );
      final dataShapeFields = dataShapeProperties == null
          ? null
          : _capabilityObject(
              dataShapeProperties['fieldIds'],
              '$path \$defs.dataShape.fieldIds',
            );
      final dataShapeFieldItems = dataShapeFields == null
          ? null
          : _capabilityObject(
              dataShapeFields['items'],
              '$path \$defs.dataShape.fieldIds.items',
            );
      if (dataShapeFields?['type'] != 'array' ||
          dataShapeFields?.containsKey('minItems') == true ||
          dataShapeFieldItems?[r'$ref'] != '#/\$defs/stableId') {
        errors.add('$path 的 dataShape.fieldIds 必须是允许空值的稳定 ID 数组');
      }
      final fieldProperties = field == null
          ? null
          : _capabilityObject(
              field['properties'],
              '$path \$defs.field.properties',
            );
      final valueType = fieldProperties == null
          ? null
          : _capabilityObject(
              fieldProperties['valueType'],
              '$path \$defs.field.valueType',
            );
      final valueTypes = _capabilityStringSet(
        valueType?['enum'],
        '$path \$defs.field.valueType.enum',
      );
      const expectedValueTypes = {
        'boolean',
        'decimal',
        'enum',
        'integer',
        'bounded_copy',
        'callback_resource',
        'opaque_id',
        'sink_capability',
        'scoped_read_access',
        'string',
        'string_list',
        'timestamp',
      };
      if (valueTypes != null &&
          !_sameStringSet(valueTypes, expectedValueTypes)) {
        errors.add('$path 的 field.valueType enum 与能力类型快照不一致');
      }

      final transition = _capabilityObject(
        definitions['transition'],
        '$path \$defs.transition',
      );
      final transitionProperties = transition == null
          ? null
          : _capabilityObject(
              transition['properties'],
              '$path \$defs.transition.properties',
            );
      final triggerKind = transitionProperties == null
          ? null
          : _capabilityObject(
              transitionProperties['triggerKind'],
              '$path \$defs.transition.triggerKind',
            );
      final triggerKinds = _capabilityStringSet(
        triggerKind?['enum'],
        '$path \$defs.transition.triggerKind.enum',
      );
      if (triggerKinds != null &&
          !_sameStringSet(triggerKinds, const {'operation', 'lifecycle'})) {
        errors.add('$path 的 transition.triggerKind enum 不完整');
      }
      final outcome = transitionProperties == null
          ? null
          : _capabilityObject(
              transitionProperties['outcome'],
              '$path \$defs.transition.outcome',
            );
      final outcomes = _capabilityStringSet(
        outcome?['enum'],
        '$path \$defs.transition.outcome.enum',
      );
      if (outcomes != null &&
          !_sameStringSet(outcomes, const {
            'success',
            'cancelled',
            'failure',
            'expired',
          })) {
        errors.add('$path 的 transition.outcome enum 不完整');
      }

      final operation = _capabilityObject(
        definitions['operation'],
        '$path \$defs.operation',
      );
      final operationProperties = operation == null
          ? null
          : _capabilityObject(
              operation['properties'],
              '$path \$defs.operation.properties',
            );
      final validFrom = operationProperties == null
          ? null
          : _capabilityObject(
              operationProperties['validFrom'],
              '$path \$defs.operation.validFrom',
            );
      final validFromItems = validFrom == null
          ? null
          : _capabilityObject(
              validFrom['items'],
              '$path \$defs.operation.validFrom.items',
            );
      if (validFrom?['uniqueItems'] != true ||
          validFromItems?[r'$ref'] != '#/\$defs/operationValidFrom') {
        errors.add('$path 的 operation.validFrom 必须引用受约束定义并拒绝重复');
      }
      final stateMachine = _capabilityObject(
        definitions['stateMachine'],
        '$path \$defs.stateMachine',
      );
      final machineProperties = stateMachine == null
          ? null
          : _capabilityObject(
              stateMachine['properties'],
              '$path \$defs.stateMachine.properties',
            );
      final transitions = machineProperties == null
          ? null
          : _capabilityObject(
              machineProperties['transitions'],
              '$path \$defs.stateMachine.transitions',
            );
      final transitionItems = transitions == null
          ? null
          : _capabilityObject(
              transitions['items'],
              '$path \$defs.stateMachine.transitions.items',
            );
      if (transitions?['uniqueItems'] != true ||
          transitionItems?[r'$ref'] != '#/\$defs/transition') {
        errors.add('$path 的 state transitions 必须引用受约束定义并拒绝重复');
      }
      final resourcePolicy = _capabilityObject(
        definitions['resourcePolicy'],
        '$path \$defs.resourcePolicy',
      );
      final resourcePolicyProperties = resourcePolicy == null
          ? null
          : _capabilityObject(
              resourcePolicy['properties'],
              '$path \$defs.resourcePolicy.properties',
            );
      final renderSurfaces = resourcePolicyProperties == null
          ? null
          : _capabilityObject(
              resourcePolicyProperties['renderSurfaces'],
              '$path \$defs.resourcePolicy.renderSurfaces',
            );
      final renderSurfaceItems = renderSurfaces == null
          ? null
          : _capabilityObject(
              renderSurfaces['items'],
              '$path \$defs.resourcePolicy.renderSurfaces.items',
            );
      if (renderSurfaces?['type'] != 'array' ||
          renderSurfaces?['uniqueItems'] != true ||
          renderSurfaceItems?[r'$ref'] != '#/\$defs/renderSurfacePolicy') {
        errors.add('$path 的 resourcePolicy.renderSurfaces 必须引用通用受约束定义');
      }
      final streamingCopies = resourcePolicyProperties == null
          ? null
          : _capabilityObject(
              resourcePolicyProperties['streamingCopies'],
              '$path \$defs.resourcePolicy.streamingCopies',
            );
      final streamingCopyItems = streamingCopies == null
          ? null
          : _capabilityObject(
              streamingCopies['items'],
              '$path \$defs.resourcePolicy.streamingCopies.items',
            );
      if (streamingCopies?['type'] != 'array' ||
          streamingCopies?['uniqueItems'] != true ||
          streamingCopyItems?[r'$ref'] != '#/\$defs/streamingCopyPolicy') {
        errors.add('$path 的 resourcePolicy.streamingCopies 必须引用通用受约束定义');
      }
      _validateGenericRenderSurfaceSchema(definitions, path);
      _validateGenericBoundedCopySchema(definitions, path);
      _validateGenericStreamingCopySchema(definitions, path);
    }
    _validateObjectSchemasRejectUnknownFields(schema, path);
  }

  void _validateGenericRenderSurfaceSchema(
    Map<String, Object?> definitions,
    String path,
  ) {
    final renderSurface = _capabilityObject(
      definitions['renderSurfacePolicy'],
      '$path \$defs.renderSurfacePolicy',
    );
    if (renderSurface == null) {
      return;
    }
    final serialized = jsonEncode(renderSurface).toLowerCase();
    for (final forbiddenDomain in const {
      'media_capture',
      'camera',
      'thumbnail',
      'previewview',
      'uiview',
      'camerax',
      'avfoundation',
    }) {
      if (serialized.contains(forbiddenDomain)) {
        errors.add(
          '$path Base renderSurfacePolicy 不得写死领域或 Framework：$forbiddenDomain',
        );
      }
    }

    final nonMediaFixture = <String, Object?>{
      'id': 'diagnostic_dashboard_surface',
      'description': 'Mounts a module-owned diagnostic renderer.',
      'resourceId': 'dashboard_surface',
      'attachmentPolicyId': 'dashboard_attachment',
      'targetFieldId': 'dashboard_target',
      'ownerGenerationFieldId': 'owner_generation',
      'consumerScope': 'native_consumer_only',
      'surfaceKind': 'diagnostic_dashboard',
      'actualMountRequired': true,
      'actualMountCapability': 'module_mounts_private_renderer',
      'factoryPolicy': 'module_defined_factory',
      'identityPolicy': 'concrete_instance_identity',
      'surfaceOwner': 'native_consumer',
      'sourceOwner': 'native_module',
      'rendererOwner': 'native_module',
      'bindingOwner': 'native_module',
      'cleanupOwner': 'native_module',
      'ownerAccessPolicy': 'outer_surface_only',
      'factoryContract': <String, Object?>{
        'ownerRoleId': 'native_module',
        'inputBindings': <Object?>[
          <String, Object?>{
            'roleId': 'surface_owner',
            'bindingKind': 'ownership_phase',
            'bindingId': 'dashboard_surface_owner',
            'required': true,
          },
        ],
        'output': <String, Object?>{
          'roleId': 'surface_instance',
          'resourceId': 'dashboard_surface',
          'platformConformanceRoleId': 'closed_target_conformance',
          'nullable': false,
          'freshInstancePerInvocation': true,
          'identityPolicy': 'concrete_instance_identity',
        },
        'emptyOutputPolicy': 'reject',
      },
      'diagnosticPolicy': <String, Object?>{
        'id': 'diagnostic_surface_log_policy',
        'allowedRecordKindIds': <Object?>['mount_failed'],
        'allowedFieldIds': <Object?>['record_kind', 'redacted_status'],
        'allowedStatusIds': <Object?>['redacted_failure'],
        'fieldValueSources': <Object?>[
          <String, Object?>{
            'fieldId': 'record_kind',
            'sourceKind': 'declared_enum',
            'reference': <String, Object?>{
              'scopeId': 'diagnostic_policy',
              'collectionId': 'allowed_record_kind_ids',
              'valueMemberId': 'item',
            },
            'allowedValueIds': <Object?>['mount_failed'],
          },
          <String, Object?>{
            'fieldId': 'redacted_status',
            'sourceKind': 'declared_enum',
            'reference': <String, Object?>{
              'scopeId': 'diagnostic_policy',
              'collectionId': 'allowed_status_ids',
              'valueMemberId': 'item',
            },
            'allowedValueIds': <Object?>['redacted_failure'],
          },
        ],
        'valuePolicy': 'stable_enum_or_redacted_status_only',
        'redactionPolicy': 'redact_before_record_creation',
        'forbiddenDataIds': <Object?>['surface_instance', 'raw_exception'],
        'exceptionPolicy': 'stable_failure_id_only_no_raw_exception',
      },
      'platformImplementations': <Object?>[
        <String, Object?>{
          'platform': 'android',
          'moduleProduct': 'diagnostic_android',
          'publicSurfaceType': 'DiagnosticSurface',
          'factoryInputType': 'DiagnosticSurfaceOwner',
          'factoryOutputType': 'DiagnosticSurface',
          'factoryOutputConformanceId': 'diagnostic_target_conformance',
          'concreteSurfaceRequired': true,
          'actualMountTargetIds': <Object?>['dashboard_target'],
          'moduleOwnedRendererIds': <Object?>['dashboard_renderer'],
          'ownerAccessibleIds': <Object?>['outer_surface'],
          'sourceAccessPolicy': 'module_internal_only',
          'rendererAccessPolicy': 'module_internal_only',
          'targetConformance': <String, Object?>{
            'id': 'diagnostic_target_conformance',
            'closed': true,
            'factoryOutputType': 'DiagnosticSurface',
            'acceptedTargetKindIds': <Object?>['dashboard_target'],
            'requiredMountEndpointType': 'DiagnosticMountEndpoint',
            'targetOwnerRoleId': 'native_module',
            'arbitraryTargetPolicy': 'reject',
          },
          'mountBinding': <String, Object?>{
            'endpointType': 'DiagnosticMountEndpoint',
            'endpointVisibility': 'module_internal',
            'endpointOwnerRoleId': 'native_module',
            'backingTargetOwnerRoleId': 'native_module',
            'sourceOwnerRoleId': 'native_module',
            'rendererOwnerRoleId': 'native_module',
            'bindingOwnerRoleId': 'native_module',
            'surfaceResourceId': 'dashboard_surface',
            'attachmentPolicyId': 'dashboard_attachment',
            'factoryOutputRoleId': 'surface_instance',
            'targetConformanceId': 'diagnostic_target_conformance',
            'lifecycleOwnershipPhaseId': 'dashboard_surface_owner',
            'ownerGenerationFieldId': 'owner_generation',
            'mountMutationPolicy': 'validate_before_mutation',
          },
        },
      ],
      'mountSourceKindIds': <Object?>['diagnostic_snapshot'],
      'installSequenceIds': <Object?>['validate_scope', 'mount_renderer'],
      'mutationGate': 'validate_before_mutation',
      'passiveFramePolicy': 'framework_pipeline',
      'revokeSequenceIds': <Object?>['invalidate_gate', 'detach_renderer'],
      'replacementSequenceIds': <Object?>[
        'advance_generation',
        'detach_renderer',
        'mount_renderer',
      ],
      'cleanupExecution': 'exactly_once',
      'staleMutationPolicy': 'drop',
      'replacementPolicy': 'fresh_generation',
      'crossRuntimeProjection': 'forbidden',
      'forbiddenRepresentationIds': <Object?>['untyped_object'],
    };
    if (!_matchesCapabilitySchemaValue(
      nonMediaFixture,
      renderSurface,
      definitions,
    )) {
      errors.add('$path Base renderSurfacePolicy 无法表达非媒体平台 surface 正例');
    }
  }

  void _validateGenericBoundedCopySchema(
    Map<String, Object?> definitions,
    String path,
  ) {
    final boundedCopy = _capabilityObject(
      definitions['boundedCopyPolicy'],
      '$path \$defs.boundedCopyPolicy',
    );
    if (boundedCopy == null) {
      return;
    }
    final serialized = jsonEncode(boundedCopy).toLowerCase();
    for (final forbiddenRole in const {
      'pixelwidth',
      'pixelheight',
      'orientationfield',
      'sampletime',
      'poster',
      'maxpixeledge',
      'contenttypefield',
      'mediatype',
      'thumbnail',
    }) {
      if (serialized.contains(forbiddenRole)) {
        errors.add('$path Base boundedCopyPolicy 不得强制媒体角色：$forbiddenRole');
      }
    }

    final nonMediaFixture = <String, Object?>{
      'id': 'bounded_diagnostic_export',
      'description': 'Exports a bounded redacted diagnostic text copy.',
      'operationId': 'read_diagnostic_excerpt',
      'roleBindings': <Object?>[
        <String, Object?>{
          'roleId': 'source_resource',
          'bindingKind': 'resource',
          'bindingId': 'diagnostic_buffer',
        },
        <String, Object?>{
          'roleId': 'result_copy',
          'bindingKind': 'resource',
          'bindingId': 'diagnostic_excerpt',
        },
        <String, Object?>{
          'roleId': 'module_scope',
          'bindingKind': 'scope',
          'bindingId': 'module_instance',
        },
      ],
      'preconditions': <Object?>[],
      'bounds': <Object?>[
        <String, Object?>{
          'id': 'excerpt_byte_bound',
          'roleId': 'result_copy',
          'minimum': 1,
          'maximum': 4096,
          'boundaryRoleId': null,
          'enforcement': 'verify_before_commit',
        },
      ],
      'transforms': <Object?>[
        <String, Object?>{
          'id': 'redact_diagnostic_text',
          'inputRoleIds': <Object?>['source_resource'],
          'outputRoleIds': <Object?>['result_copy'],
          'guaranteeIds': <Object?>['remove_sensitive_values'],
        },
      ],
      'ownershipTransfer': <String, Object?>{
        'initialOwnerRoleId': 'source_resource',
        'transferAtId': 'atomic_result_commit',
        'transferredOwnerRoleId': 'result_copy',
        'atomic': true,
        'postTransferPolicy': 'caller_copy_independent',
      },
      'execution': <String, Object?>{
        'preAccessRegistration': <String, Object?>{
          'managedRoleId': 'source_resource',
          'beforeAccessRoleId': 'source_resource',
          'required': true,
        },
        'concurrencyBounds': <Object?>[
          <String, Object?>{'scopeRoleId': 'module_scope', 'maximum': 1},
        ],
        'workBudgets': <Object?>[
          <String, Object?>{
            'id': 'excerpt_memory_budget',
            'scopeRoleId': 'module_scope',
            'unitId': 'byte',
            'maximum': 8192,
            'enforcement': 'reject_before_budget_exceeded',
          },
        ],
        'sourceReductionPolicy': 'stream_before_full_materialization',
        'overloadFailureId': 'resource_overloaded',
      },
      'raceArbitration': <String, Object?>{
        'linearizationPoint': 'atomic_terminal_outcome_commit',
        'winnerPolicy': 'first_terminal_trigger_wins',
        'outcomeDelivery': 'exactly_once',
        'cleanupExecution': 'exactly_once_for_non_success_winner',
        'successFinalizationExecution': 'exactly_once_before_result_delivery',
        'successCommitEffect': 'caller_copy_independent',
        'failureCleanupSequenceIds': <Object?>['discard_partial_copy'],
        'successFinalizationSequenceIds': <Object?>[
          'close_source_access',
          'preserve_caller_copy',
        ],
        'triggerPolicies': <Object?>[
          <String, Object?>{
            'triggerKind': 'commit',
            'triggerId': 'result_commit',
            'outcomeKind': 'result',
            'outcomeId': 'diagnostic_excerpt',
            'sequenceKind': 'success_finalization',
            'sequenceIds': <Object?>[
              'close_source_access',
              'preserve_caller_copy',
            ],
          },
        ],
      },
      'privacyPolicyIds': <Object?>['redact_sensitive_values'],
      'forbiddenRepresentationIds': <Object?>['unbounded_source'],
      'backendDetailsPolicy': 'redact_backend_details',
    };
    if (!_matchesCapabilitySchemaValue(
      nonMediaFixture,
      boundedCopy,
      definitions,
    )) {
      errors.add('$path Base boundedCopyPolicy 无法表达非媒体 bounded-copy 正例');
    }
  }

  void _validateGenericStreamingCopySchema(
    Map<String, Object?> definitions,
    String path,
  ) {
    final streamingCopy = _capabilityObject(
      definitions['streamingCopyPolicy'],
      '$path \$defs.streamingCopyPolicy',
    );
    if (streamingCopy == null) {
      return;
    }
    final serialized = jsonEncode(streamingCopy).toLowerCase();
    for (final forbiddenDomain in const {
      'media_capture',
      'media_handle',
      'image_jpeg',
      'video_mp4',
      '52428800',
      '262144',
    }) {
      if (serialized.contains(forbiddenDomain)) {
        errors.add(
          '$path Base streamingCopyPolicy 不得写死领域字段或预算：$forbiddenDomain',
        );
      }
    }

    final nonMediaFixture = <String, Object?>{
      'id': 'bounded_diagnostic_stream',
      'description': 'Streams a bounded diagnostic archive to a typed sink.',
      'operationId': 'copy_diagnostic_archive',
      'roleBindings': <Object?>[
        <String, Object?>{
          'roleId': 'source_resource',
          'bindingKind': 'resource',
          'bindingId': 'diagnostic_archive',
        },
        <String, Object?>{
          'roleId': 'sink_capability',
          'bindingKind': 'field',
          'bindingId': 'diagnostic_sink',
        },
        <String, Object?>{
          'roleId': 'job',
          'bindingKind': 'resource',
          'bindingId': 'diagnostic_export_job',
        },
        <String, Object?>{
          'roleId': 'buffer',
          'bindingKind': 'resource',
          'bindingId': 'diagnostic_export_buffer',
        },
      ],
      'preconditions': <Object?>[],
      'sourceRepresentations': <Object?>[
        <String, Object?>{
          'sourceValueId': 'diagnostic_archive',
          'formatId': 'compressed_archive',
          'contentType': 'application/x-diagnostic-archive',
        },
      ],
      'bounds': <Object?>[
        <String, Object?>{
          'id': 'stream_bound',
          'roleId': 'buffer',
          'minimum': 1,
          'maximum': 4096,
          'boundaryRoleId': null,
          'enforcement': 'verify_before_write',
        },
      ],
      'sinkProtocol': <String, Object?>{
        'sinkRoleId': 'sink_capability',
        'consumerScope': 'native_call_only',
        'serializationPolicy': 'forbidden',
        'registryStoragePolicy': 'forbidden',
        'methods': <Object?>[
          <String, Object?>{
            'id': 'begin_sink',
            'phase': 'begin',
            'cardinality': 'once',
            'payloadRoleIds': <Object?>[],
          },
          <String, Object?>{
            'id': 'write_sink',
            'phase': 'write',
            'cardinality': 'zero_or_more',
            'payloadRoleIds': <Object?>['buffer'],
          },
          <String, Object?>{
            'id': 'commit_sink',
            'phase': 'commit',
            'cardinality': 'success_once',
            'payloadRoleIds': <Object?>[],
          },
          <String, Object?>{
            'id': 'abort_sink',
            'phase': 'abort',
            'cardinality': 'failure_once',
            'payloadRoleIds': <Object?>[],
          },
        ],
        'invocationOrderIds': <Object?>[
          'begin_sink',
          'write_sink',
          'commit_or_abort',
        ],
        'sequentialWrites': true,
        'terminalExclusivity': 'commit_xor_abort',
        'cancellationAware': true,
        'cancellationConvergenceSeconds': 3,
      },
      'execution': <String, Object?>{
        'reservationRoleIds': <Object?>['job', 'buffer'],
        'beforeAccessRoleIds': <Object?>['source_resource', 'sink_capability'],
        'atomicReservation': true,
        'capacityPolicy': 'reject_before_access',
        'concurrencyBounds': <Object?>[
          <String, Object?>{'scopeRoleId': 'job', 'maximum': 1},
        ],
        'workBudgets': <Object?>[
          <String, Object?>{
            'id': 'buffer_budget',
            'scopeRoleId': 'job',
            'unitId': 'byte',
            'maximum': 4096,
            'enforcement': 'reject_before_allocation',
          },
        ],
        'deadlineSeconds': 10,
        'deadlineStartId': 'reservation_committed',
        'cancellationPolicy': 'cooperative',
        'lateResultPolicy': 'drop',
        'lengthCheckIds': <Object?>['before_copy', 'before_commit'],
        'fullBufferingPolicy': 'forbidden',
        'overloadFailureId': 'diagnostic_overloaded',
      },
      'terminalPolicy': <String, Object?>{
        'linearizationPoint': 'terminal_commit',
        'winnerPolicy': 'first_wins',
        'outcomeDelivery': 'exactly_once',
        'successSinkActionId': 'commit_sink',
        'failureSinkActionId': 'abort_sink',
        'successSinkActionCardinality': 'exactly_once',
        'failureSinkActionCardinality': 'exactly_once_after_begin',
        'terminalExclusivity': 'commit_xor_abort',
        'failureCleanupSequenceIds': <Object?>['abort_sink', 'release_job'],
        'successFinalizationSequenceIds': <Object?>[
          'commit_sink',
          'release_job',
        ],
      },
      'failureBehaviors': <Object?>[
        <String, Object?>{
          'failureId': 'diagnostic_write_failed',
          'recoverable': true,
          'terminal': false,
          'triggerIds': <Object?>['sink_write_failed'],
          'raceWinnerId': 'sink_failure',
          'sinkActionId': 'abort_after_begin',
          'sourceLeaseEffect': 'unchanged',
          'detailsPolicy': 'redacted',
        },
      ],
      'successResultId': 'diagnostic_exported',
      'successResultFieldIds': <Object?>['byte_length'],
      'sourceLeasePolicy': 'unchanged',
      'privacyPolicyIds': <Object?>['redact_diagnostics'],
      'forbiddenRepresentationIds': <Object?>['path'],
      'backendDetailsPolicy': 'redact_backend_details',
    };
    if (!_matchesCapabilitySchemaValue(
      nonMediaFixture,
      streamingCopy,
      definitions,
    )) {
      errors.add('$path Base streamingCopyPolicy 无法表达非媒体 bounded stream 正例');
    }
  }

  bool _matchesCapabilitySchemaValue(
    Object? value,
    Map<String, Object?> schema,
    Map<String, Object?> definitions,
  ) {
    final reference = schema[r'$ref'];
    if (reference is String && reference.startsWith('#/\$defs/')) {
      final definition = definitions[reference.substring('#/\$defs/'.length)];
      return definition is Map<String, Object?> &&
          _matchesCapabilitySchemaValue(value, definition, definitions);
    }
    final oneOf = schema['oneOf'];
    if (oneOf is List<Object?>) {
      return oneOf.whereType<Map<String, Object?>>().any(
        (candidate) =>
            _matchesCapabilitySchemaValue(value, candidate, definitions),
      );
    }
    final enumValues = schema['enum'];
    if (enumValues is List<Object?> && !enumValues.contains(value)) {
      return false;
    }
    final type = schema['type'];
    if (type is List<Object?>) {
      return type.any(
        (candidate) => _matchesCapabilitySchemaValue(value, <String, Object?>{
          'type': candidate,
        }, definitions),
      );
    }
    if (type == 'object') {
      if (value is! Map<String, Object?>) {
        return false;
      }
      final required =
          (schema['required'] as List<Object?>?)?.whereType<String>().toSet() ??
          const <String>{};
      final properties = schema['properties'];
      if (properties is! Map<String, Object?> ||
          !value.keys.toSet().containsAll(required) ||
          (schema['additionalProperties'] == false &&
              !properties.keys.toSet().containsAll(value.keys))) {
        return false;
      }
      for (final entry in value.entries) {
        final propertySchema = properties[entry.key];
        if (propertySchema is! Map<String, Object?> ||
            !_matchesCapabilitySchemaValue(
              entry.value,
              propertySchema,
              definitions,
            )) {
          return false;
        }
      }
    } else if (type == 'array') {
      final minItems = schema['minItems'];
      if (value is! List<Object?> ||
          (minItems is int && value.length < minItems)) {
        return false;
      }
      final itemSchema = schema['items'];
      if (itemSchema is Map<String, Object?> &&
          value.any(
            (item) =>
                !_matchesCapabilitySchemaValue(item, itemSchema, definitions),
          )) {
        return false;
      }
    } else if (type == 'string' && value is! String) {
      return false;
    } else if (type == 'integer' && value is! int) {
      return false;
    } else if (type == 'number' && value is! num) {
      return false;
    } else if (type == 'boolean' && value is! bool) {
      return false;
    } else if (type == 'null' && value != null) {
      return false;
    }
    final pattern = schema['pattern'];
    return pattern is! String ||
        (value is String && RegExp(pattern).hasMatch(value));
  }

  void _validateCapabilitySchemaPropertyRef(
    Map<String, Object?> properties,
    String field,
    String expectedRef,
    String path,
  ) {
    final property = _capabilityObject(
      properties[field],
      '$path properties.$field',
    );
    if (property?[r'$ref'] != expectedRef) {
      errors.add('$path 的 properties.$field 必须引用 $expectedRef');
    }
  }

  void _validateCapabilitySchemaArrayItemRef(
    Map<String, Object?> properties,
    String field,
    String expectedRef,
    String path,
  ) {
    final property = _capabilityObject(
      properties[field],
      '$path properties.$field',
    );
    final items = property == null
        ? null
        : _capabilityObject(property['items'], '$path properties.$field.items');
    if (property?['type'] != 'array' || items?[r'$ref'] != expectedRef) {
      errors.add('$path 的 properties.$field 必须是引用 $expectedRef 的数组');
    }
  }

  void _validateObjectSchemasRejectUnknownFields(Object? value, String path) {
    if (value is Map<String, Object?>) {
      if (value['type'] == 'object') {
        if (value['additionalProperties'] != false) {
          errors.add(
            '$path 的所有 object schema 必须声明 additionalProperties: false',
          );
        }
        final required = value['required'];
        final properties = value['properties'];
        if (required is! List<Object?> ||
            required.any((item) => item is! String) ||
            properties is! Map<String, Object?> ||
            !_sameStringSet(
              required.cast<String>().toSet(),
              properties.keys.toSet(),
            )) {
          errors.add('$path 的所有 object schema 必须让 required 精确匹配 properties');
        }
      }
      for (final child in value.values) {
        _validateObjectSchemasRejectUnknownFields(child, path);
      }
    } else if (value is List<Object?>) {
      for (final child in value) {
        _validateObjectSchemasRejectUnknownFields(child, path);
      }
    }
  }

  void _validateMediaCaptureCapability(
    Map<String, Object?> contract,
    String path,
  ) {
    const topLevelFields = {
      r'$schema',
      'contractId',
      'capabilityVersion',
      'versionHistory',
      'platform',
      'operation',
      'field',
      'request',
      'result',
      'event',
      'stateMachines',
      'failure',
      'permission',
      'lifecycle',
      'resourcePolicy',
    };
    _validateCapabilityExactKeys(contract, topLevelFields, path);
    if (contract[r'$schema'] !=
        '../../native/contracts/capability.schema.json') {
      errors.add('$path 必须引用固定 Capability JSON Schema 路径');
    }
    if (contract['contractId'] != 'media_capture') {
      errors.add('$path 的 contractId 必须是 media_capture');
    }
    final version = contract['capabilityVersion'];
    if (version != 4) {
      errors.add('$path 必须声明当前 capabilityVersion 4');
    }
    if (contract.containsKey('wireVersion')) {
      errors.add('$path 不得用 wireVersion 替代 capabilityVersion');
    }
    _validateCapabilityVersionHistory(contract['versionHistory'], path);

    _validateCapabilityTransportNeutral(contract, path);
    _validateCapabilityPlatforms(contract['platform'], path);

    final fields = _validateCapabilityFields(contract['field'], path);

    final requests = _validateCapabilityDataShapes(
      contract['request'],
      'request',
      const {
        'start_session_request',
        'session_action_request',
        'flash_mode_request',
        'focus_point_request',
        'zoom_request',
        'media_handle_request',
        'live_preview_attachment_request',
        'live_preview_detach_request',
        'unconfirmed_preview_attachment_request',
        'unconfirmed_preview_detach_request',
        'media_thumbnail_request',
        'media_export_request',
      },
      fields,
      path,
    );
    final results = _validateCapabilityDataShapes(
      contract['result'],
      'result',
      const {
        'session_created',
        'control_applied',
        'recording_started',
        'media_preview',
        'retake_ready',
        'confirmed_media',
        'session_cancelled',
        'scoped_media_read',
        'media_released',
        'render_attachment_attached',
        'render_attachment_detached',
        'media_thumbnail',
        'media_export_result',
      },
      fields,
      path,
    );
    final events = _validateCapabilityDataShapes(
      contract['event'],
      'event',
      const {
        'session_ready',
        'session_failed',
        'media_preview_ready',
        'media_lease_expired',
        'media_read_revoked',
        'render_attachment_revoked',
      },
      fields,
      path,
    );
    final failures = _validateCapabilityFailures(contract['failure'], path);
    _validateCapabilityTerminalFailureField(
      contract['field'],
      contract['failure'],
      path,
    );
    final operations = _validateCapabilityOperations(
      contract['operation'],
      requests,
      results,
      events,
      failures,
      path,
    );
    final lifecycleRules = _validateCapabilityLifecycle(
      contract['lifecycle'],
      path,
    );
    final stateIds = _validateCapabilityStates(
      contract['stateMachines'],
      contract['operation'],
      operations,
      lifecycleRules,
      results,
      events,
      failures,
      path,
    );
    _validateCapabilityPermissions(contract['permission'], operations, path);
    _validateCapabilityResourcePolicy(
      contract['resourcePolicy'],
      fields,
      operations,
      stateIds,
      lifecycleRules,
      failures,
      path,
    );
  }

  void _validateCapabilityVersionHistory(Object? value, String path) {
    final entries = _capabilityObjectList(value, '$path versionHistory');
    if (entries == null) {
      return;
    }
    final signatures = <int, String>{};
    final descriptions = <int, String>{};
    for (final entry in entries) {
      _validateCapabilityExactKeys(entry, const {
        'version',
        'changeKind',
        'compatibleWith',
        'description',
      }, '$path versionHistory entry');
      final version = entry['version'];
      final compatible = entry['compatibleWith'];
      if (version is! int || version < 1 || signatures.containsKey(version)) {
        errors.add('$path versionHistory 必须使用唯一正整数 version');
        continue;
      }
      if (compatible is! List<Object?> ||
          compatible.isEmpty ||
          compatible.any((item) => item is! int || item < 1) ||
          compatible.toSet().length != compatible.length) {
        errors.add('$path versionHistory.compatibleWith 必须是非空唯一正整数数组');
        continue;
      }
      _validateCapabilityDescription(entry, '$path versionHistory entry');
      final sorted = compatible.cast<int>()..sort();
      signatures[version] = '${entry['changeKind']}|${sorted.join(',')}';
      if (entry['description'] is String) {
        descriptions[version] = entry['description'] as String;
      }
    }
    const expected = <int, String>{
      1: 'baseline|1',
      2: 'additive|1,2',
      3: 'additive|1,2,3',
      4: 'additive|1,2,3,4',
    };
    if (signatures.length != expected.length ||
        expected.entries.any((entry) => signatures[entry.key] != entry.value)) {
      errors.add('$path 必须保留 V1-V3 历史并声明兼容 1/2/3/4 的 V4 additive 演进');
    }
    const expectedDescriptions = {
      1:
          'Established capture sessions, confirmed media leases, '
          'callback-scoped native reads, ownership, permission, lifecycle, '
          'and stable failure semantics.',
      2:
          'Adds native-only render attachments and a sanitized bounded '
          'thumbnail copy while preserving every Version 1 operation and '
          'state semantic.',
      3:
          'Adds module-defined concrete platform render surfaces with actual '
          'mount, lifecycle gate, ownership, and revoke semantics while '
          'preserving every Version 1 and Version 2 operation, state, '
          'failure, lease, thumbnail, and handle semantic.',
      4:
          'Adds bounded streaming export from active confirmed media to a '
          'caller-scoped native sink while preserving every Version 1 '
          'through Version 3 operation, state, render, thumbnail, lease, '
          'and handle semantic.',
    };
    if (descriptions.length != expectedDescriptions.length ||
        expectedDescriptions.entries.any(
          (entry) => descriptions[entry.key] != entry.value,
        )) {
      errors.add('$path 的 V1/V2/V3/V4 history description 不得覆盖或改写');
    }
  }

  void _validateCapabilityTransportNeutral(Object? value, String path) {
    final forbidden = RegExp(
      r'(^|[^a-z])(flutter|methodchannel|eventchannel|channel|wire|protobuf|proto|camerax|avfoundation)([^a-z]|$)',
      caseSensitive: false,
    );

    void inspect(Object? node, String location) {
      if (node is Map<String, Object?>) {
        for (final entry in node.entries) {
          if (forbidden.hasMatch(entry.key)) {
            errors.add('$path 包含传输或平台 SDK 字段：$location.${entry.key}');
          }
          inspect(entry.value, '$location.${entry.key}');
        }
      } else if (node is List<Object?>) {
        for (var index = 0; index < node.length; index += 1) {
          inspect(node[index], '$location[$index]');
        }
      } else if (node is String && forbidden.hasMatch(node)) {
        errors.add('$path 包含传输或平台 SDK 语义：$location');
      }
    }

    inspect(value, r'$');
  }

  void _validateCapabilityPlatforms(Object? value, String path) {
    final platform = _capabilityObject(value, '$path platform');
    if (platform == null) {
      return;
    }
    _validateCapabilityExactKeys(platform, const {
      'supported',
      'semanticParity',
      'differences',
    }, '$path platform');
    final supported = _capabilityStringSet(
      platform['supported'],
      '$path platform.supported',
    );
    if (supported != null &&
        !_sameStringSet(supported, const {'android', 'ios'})) {
      errors.add('$path 必须且只能支持 android 与 ios');
    }
    if (platform['semanticParity'] != 'required') {
      errors.add('$path 必须要求 Android/iOS 公共语义一致');
    }
    final differences = _capabilityObjectList(
      platform['differences'],
      '$path platform.differences',
    );
    if (differences == null) {
      return;
    }
    final ids = <String>{};
    final seenPlatforms = <String>{};
    final platformByDifferenceId = <String, String>{};
    for (final difference in differences) {
      _validateCapabilityExactKeys(difference, const {
        'platform',
        'id',
        'description',
      }, '$path platform difference');
      final platformId = difference['platform'];
      if (platformId is String) {
        seenPlatforms.add(platformId);
      }
      _addStableCapabilityId(
        ids,
        difference['id'],
        '$path platform difference',
      );
      _validateCapabilityDescription(difference, '$path platform difference');
      if (difference['id'] is String && platformId is String) {
        platformByDifferenceId[difference['id'] as String] = platformId;
      }
    }
    if (!_sameStringSet(seenPlatforms, const {'android', 'ios'})) {
      errors.add('$path 必须为 Android/iOS 都声明允许的平台差异');
    }
    const expectedIds = {
      'android_permission_retry_resolution',
      'android_private_cache_mapping',
      'android_module_render_surface',
      'ios_permission_retry_resolution',
      'ios_private_cache_mapping',
      'ios_module_render_surface',
    };
    if (!_sameStringSet(ids, expectedIds)) {
      errors.add('$path 的平台差异 ID 与已批准快照不一致');
    }
    for (final id in expectedIds) {
      final expectedPlatform = id.startsWith('android_') ? 'android' : 'ios';
      if (platformByDifferenceId[id] != expectedPlatform) {
        errors.add('$path 的平台差异 $id 必须属于 $expectedPlatform');
      }
    }
  }

  Map<String, String> _validateCapabilityFields(Object? value, String path) {
    final fields = _capabilityObjectList(value, '$path field');
    final signatures = <String, String>{};
    if (fields == null) {
      return signatures;
    }
    const valueTypes = {
      'boolean',
      'decimal',
      'enum',
      'integer',
      'bounded_copy',
      'callback_resource',
      'opaque_id',
      'sink_capability',
      'scoped_read_access',
      'string',
      'string_list',
      'timestamp',
    };
    const expectedTypes = {
      'enabled_media_types': 'string_list|true|false|photo,video',
      'preferred_camera': 'enum|true|false|front,rear',
      'audio_enabled': 'boolean|true|false|',
      'max_video_duration_millis': 'integer|true|false|',
      'session_handle': 'opaque_id|true|false|',
      'flash_mode': 'enum|true|false|auto,off,on,torch',
      'normalized_x': 'decimal|true|false|',
      'normalized_y': 'decimal|true|false|',
      'zoom_factor': 'decimal|true|false|',
      'media_handle': 'opaque_id|true|false|',
      'active_camera': 'enum|true|false|front,rear',
      'available_cameras': 'string_list|true|false|front,rear',
      'switch_camera_supported': 'boolean|true|false|',
      'supported_flash_modes': 'string_list|true|false|auto,off,on,torch',
      'focus_point_supported': 'boolean|true|false|',
      'min_zoom_factor': 'decimal|true|false|',
      'max_zoom_factor': 'decimal|true|false|',
      'audio_included': 'boolean|true|false|',
      'media_type': 'enum|true|false|photo,video',
      'pixel_width': 'integer|true|false|',
      'pixel_height': 'integer|true|false|',
      'duration_millis': 'integer|true|true|',
      'orientation_degrees': 'integer|true|false|',
      'byte_length': 'integer|true|false|',
      'lease_expires_at': 'timestamp|true|false|',
      'read_access': 'scoped_read_access|true|false|',
      'content_type': 'string|true|false|',
      'terminal_failure_id':
          'enum|true|false|encoding_failed,permission_denied,'
          'permission_permanently_denied,permission_restricted,'
          'resource_in_use,session_timeout,storage_full,system_interrupted',
      'render_target_adapter': 'callback_resource|true|false|',
      'owner_generation': 'integer|true|false|',
      'attachment_kind': 'enum|true|false|live_preview,unconfirmed_preview',
      'max_pixel_edge': 'integer|true|false|',
      'thumbnail_copy': 'bounded_copy|true|false|',
      'thumbnail_byte_length': 'integer|true|false|',
      'thumbnail_pixel_width': 'integer|true|false|',
      'thumbnail_pixel_height': 'integer|true|false|',
      'thumbnail_content_type': 'string|true|false|',
      'thumbnail_orientation_degrees': 'integer|true|false|',
      'poster_frame_millis': 'integer|true|true|',
      'media_copy_sink': 'sink_capability|true|false|',
      'media_export_max_length': 'integer|true|false|',
    };
    const expectedValidation = {
      'enabled_media_types': 'false|null|null||1|2|none|null|reject|',
      'preferred_camera':
          'false|null|null||null|null|none|null|not_applicable|',
      'audio_enabled': 'false|null|null||null|null|none|null|not_applicable|',
      'max_video_duration_millis':
          'true|1|60000||null|null|duration_millis|null|reject|',
      'session_handle':
          'false|null|null||null|null|opaque_handle|null|not_applicable|',
      'flash_mode': 'false|null|null||null|null|none|null|reject|',
      'normalized_x': 'true|0|1||null|null|normalized_coordinate|null|reject|',
      'normalized_y': 'true|0|1||null|null|normalized_coordinate|null|reject|',
      'zoom_factor':
          'true|null|null||null|null|zoom_factor|session_zoom_range|reject|',
      'media_handle':
          'false|null|null||null|null|opaque_handle|null|not_applicable|',
      'active_camera': 'false|null|null||null|null|none|null|not_applicable|',
      'available_cameras': 'false|null|null||1|2|none|null|not_applicable|',
      'switch_camera_supported':
          'false|null|null||null|null|none|null|not_applicable|',
      'supported_flash_modes': 'false|null|null||1|4|none|null|not_applicable|',
      'focus_point_supported':
          'false|null|null||null|null|none|null|not_applicable|',
      'min_zoom_factor': 'true|0.01|null||null|null|zoom_bound|null|reject|',
      'max_zoom_factor': 'true|0.01|null||null|null|zoom_bound|null|reject|',
      'audio_included': 'false|null|null||null|null|none|null|not_applicable|',
      'media_type': 'false|null|null||null|null|none|null|not_applicable|',
      'pixel_width': 'true|1|null||null|null|pixel_dimension|null|reject|',
      'pixel_height': 'true|1|null||null|null|pixel_dimension|null|reject|',
      'duration_millis':
          'true|1|60000||null|null|duration_millis|null|reject|'
          'media_type:equals:photo:must_be_null,'
          'media_type:equals:video:must_be_non_null',
      'orientation_degrees':
          'true|null|null|0,90,180,270|null|null|orientation_degrees|null|reject|',
      'byte_length': 'true|1|null||null|null|byte_length|null|reject|',
      'lease_expires_at':
          'true|0|null||null|null|unix_epoch_millis|null|reject|',
      'read_access':
          'false|null|null||null|null|scoped_read_access|null|not_applicable|',
      'content_type': 'false|null|null||null|null|mime_type|null|reject|',
      'terminal_failure_id':
          'false|null|null||null|null|none|null|not_applicable|',
      'render_target_adapter':
          'false|null|null||null|null|render_target_adapter|null|not_applicable|',
      'owner_generation':
          'true|1|9223372036854775807||null|null|owner_generation|null|reject|',
      'attachment_kind': 'false|null|null||null|null|none|null|reject|',
      'max_pixel_edge': 'true|64|512||null|null|pixel_dimension|null|reject|',
      'thumbnail_copy':
          'false|null|null||null|null|caller_owned_bounded_copy|null|not_applicable|',
      'thumbnail_byte_length':
          'true|1|524288||null|null|byte_length|null|reject|',
      'thumbnail_pixel_width':
          'true|1|512||null|null|pixel_dimension|max_pixel_edge|reject|',
      'thumbnail_pixel_height':
          'true|1|512||null|null|pixel_dimension|max_pixel_edge|reject|',
      'thumbnail_content_type':
          'false|null|null||null|null|image_jpeg_content_type|null|reject|',
      'thumbnail_orientation_degrees':
          'true|null|null|0|null|null|orientation_degrees|null|reject|',
      'poster_frame_millis':
          'true|0|60000||null|null|duration_millis|null|reject|'
          'media_type:equals:photo:must_be_null,'
          'media_type:equals:video:must_be_non_null',
      'media_copy_sink':
          'false|null|null||null|null|native_only_sink_capability|null|not_applicable|',
      'media_export_max_length':
          'true|1|52428800||null|null|byte_length|null|reject|',
    };

    for (final field in fields) {
      _validateCapabilityExactKeys(field, const {
        'id',
        'description',
        'valueType',
        'required',
        'nullable',
        'enumValues',
        'validation',
      }, '$path field entry');
      final id = field['id'];
      if (id is! String) {
        errors.add('$path field 必须声明字符串 id');
        continue;
      }
      _validateStableCapabilityId(id, '$path field');
      if (signatures.containsKey(id)) {
        errors.add('$path field 包含重复 id：$id');
      }
      _validateCapabilityDescription(field, '$path field entry');
      if (id == 'render_target_adapter' &&
          field['description'] !=
              'Native-only callback resource implemented by a module-defined '
                  'concrete platform surface; its outer lifecycle is '
                  'consumer-owned while backing target, source, renderer, '
                  'and mount binding remain module-private.') {
        errors.add(
          '$path render_target_adapter 必须允许 module-defined concrete surface 并保持内部 mount 私有',
        );
      }
      if (!valueTypes.contains(field['valueType']) ||
          field['required'] is! bool ||
          field['nullable'] is! bool) {
        errors.add('$path field $id 的类型/required/nullable 无效');
      }
      final enumValues = _capabilityStringSet(
        field['enumValues'],
        '$path field.$id.enumValues',
      );
      for (final value in enumValues ?? const <String>{}) {
        _validateStableCapabilityId(value, '$path field.$id.enumValues');
      }
      final sortedEnums = (enumValues ?? const <String>{}).toList()..sort();
      final typeSignature =
          '${field['valueType']}|${field['required']}|${field['nullable']}|'
          '${sortedEnums.join(',')}';
      if (expectedTypes[id] != typeSignature) {
        errors.add('$path field $id 的类型语义与 V4 Profile 不一致');
      }
      final validation = _capabilityObject(
        field['validation'],
        '$path field.$id.validation',
      );
      final validationSignature = _capabilityValidationSignature(
        validation,
        '$path field.$id.validation',
      );
      if (expectedValidation[id] != validationSignature) {
        errors.add('$path field $id 的结构化 validation 与 V4 Profile 不一致');
      }
      signatures[id] = '$typeSignature|$validationSignature';
    }
    if (!_sameStringSet(signatures.keys.toSet(), expectedTypes.keys.toSet())) {
      errors.add('$path 的 field ID 与 Media Capture V4 Profile 不一致');
    }
    if (!_sameStringSet(
      expectedValidation.keys.toSet(),
      expectedTypes.keys.toSet(),
    )) {
      errors.add('Harness 的 Media Capture field validation 快照不完整');
    }
    return signatures;
  }

  String _capabilityValidationSignature(
    Map<String, Object?>? validation,
    String label,
  ) {
    if (validation == null) {
      return 'invalid';
    }
    _validateCapabilityExactKeys(validation, const {
      'finite',
      'minimum',
      'maximum',
      'allowedIntegers',
      'minItems',
      'maxItems',
      'format',
      'boundarySource',
      'outOfRangePolicy',
      'conditionalRules',
    }, label);
    if (validation['finite'] is! bool ||
        (validation['minimum'] != null && validation['minimum'] is! num) ||
        (validation['maximum'] != null && validation['maximum'] is! num) ||
        (validation['minItems'] != null && validation['minItems'] is! int) ||
        (validation['maxItems'] != null && validation['maxItems'] is! int) ||
        validation['format'] is! String ||
        (validation['boundarySource'] != null &&
            validation['boundarySource'] is! String) ||
        !const {
          'reject',
          'clamp',
          'not_applicable',
        }.contains(validation['outOfRangePolicy'])) {
      errors.add('$label 的标量约束无效');
    }
    final integers = validation['allowedIntegers'];
    final integerValues = <int>[];
    if (integers is! List<Object?> || integers.any((item) => item is! int)) {
      errors.add('$label.allowedIntegers 必须是整数数组');
    } else {
      integerValues.addAll(integers.cast<int>()..sort());
      if (integerValues.toSet().length != integerValues.length) {
        errors.add('$label.allowedIntegers 不得重复');
      }
    }
    final conditionalRules = _capabilityObjectList(
      validation['conditionalRules'],
      '$label.conditionalRules',
    );
    final ruleSignatures = <String>[];
    for (final rule in conditionalRules ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(rule, const {
        'whenFieldId',
        'operator',
        'value',
        'effect',
      }, '$label conditional rule');
      final signature =
          '${rule['whenFieldId']}:${rule['operator']}:${rule['value']}:'
          '${rule['effect']}';
      if (!ruleSignatures.contains(signature)) {
        ruleSignatures.add(signature);
      } else {
        errors.add('$label 包含重复 conditional rule');
      }
    }
    ruleSignatures.sort();
    return '${validation['finite']}|${validation['minimum']}|'
        '${validation['maximum']}|${integerValues.join(',')}|'
        '${validation['minItems']}|${validation['maxItems']}|'
        '${validation['format']}|${validation['boundarySource']}|'
        '${validation['outOfRangePolicy']}|${ruleSignatures.join(',')}';
  }

  Set<String> _validateCapabilityDataShapes(
    Object? value,
    String field,
    Set<String> expectedIds,
    Map<String, String> definedFields,
    String path,
  ) {
    final shapes = _capabilityObjectList(value, '$path $field');
    final ids = <String>{};
    if (shapes == null) {
      return ids;
    }
    const requestFieldIds = <String, Set<String>>{
      'start_session_request': {
        'enabled_media_types',
        'preferred_camera',
        'audio_enabled',
        'max_video_duration_millis',
      },
      'session_action_request': {'session_handle'},
      'flash_mode_request': {'session_handle', 'flash_mode'},
      'focus_point_request': {'session_handle', 'normalized_x', 'normalized_y'},
      'zoom_request': {'session_handle', 'zoom_factor'},
      'media_handle_request': {'media_handle'},
      'live_preview_attachment_request': {
        'session_handle',
        'render_target_adapter',
        'owner_generation',
      },
      'live_preview_detach_request': {
        'session_handle',
        'render_target_adapter',
        'owner_generation',
      },
      'unconfirmed_preview_attachment_request': {
        'media_handle',
        'render_target_adapter',
        'owner_generation',
      },
      'unconfirmed_preview_detach_request': {
        'media_handle',
        'render_target_adapter',
        'owner_generation',
      },
      'media_thumbnail_request': {'media_handle', 'max_pixel_edge'},
      'media_export_request': {
        'media_handle',
        'media_copy_sink',
        'media_export_max_length',
      },
    };
    const resultFieldIds = <String, Set<String>>{
      'session_created': {'session_handle'},
      'control_applied': {'session_handle'},
      'recording_started': {'session_handle', 'audio_included'},
      'media_preview': {
        'media_handle',
        'media_type',
        'pixel_width',
        'pixel_height',
        'duration_millis',
        'orientation_degrees',
        'byte_length',
      },
      'retake_ready': {'session_handle'},
      'confirmed_media': {
        'media_handle',
        'media_type',
        'pixel_width',
        'pixel_height',
        'duration_millis',
        'orientation_degrees',
        'byte_length',
        'lease_expires_at',
      },
      'session_cancelled': {'session_handle'},
      'scoped_media_read': {
        'media_handle',
        'read_access',
        'byte_length',
        'content_type',
      },
      'media_released': {'media_handle'},
      'render_attachment_attached': {'attachment_kind', 'owner_generation'},
      'render_attachment_detached': {'attachment_kind', 'owner_generation'},
      'media_thumbnail': {
        'media_handle',
        'thumbnail_copy',
        'thumbnail_byte_length',
        'thumbnail_pixel_width',
        'thumbnail_pixel_height',
        'thumbnail_content_type',
        'thumbnail_orientation_degrees',
        'media_type',
        'poster_frame_millis',
      },
      'media_export_result': {
        'media_handle',
        'media_type',
        'content_type',
        'byte_length',
      },
    };
    const eventFieldIds = <String, Set<String>>{
      'session_ready': {
        'session_handle',
        'active_camera',
        'available_cameras',
        'switch_camera_supported',
        'supported_flash_modes',
        'focus_point_supported',
        'min_zoom_factor',
        'max_zoom_factor',
      },
      'session_failed': {'session_handle', 'terminal_failure_id'},
      'media_preview_ready': {
        'session_handle',
        'media_handle',
        'media_type',
        'pixel_width',
        'pixel_height',
        'duration_millis',
        'orientation_degrees',
        'byte_length',
      },
      'media_lease_expired': {'media_handle'},
      'media_read_revoked': {'media_handle'},
      'render_attachment_revoked': {'attachment_kind', 'owner_generation'},
    };
    final expectedFieldIds = switch (field) {
      'request' => requestFieldIds,
      'result' => resultFieldIds,
      'event' => eventFieldIds,
      _ => const <String, Set<String>>{},
    };
    for (final shape in shapes) {
      _validateCapabilityExactKeys(shape, const {
        'id',
        'description',
        'fieldIds',
      }, '$path $field entry');
      _addStableCapabilityId(ids, shape['id'], '$path $field');
      _validateCapabilityDescription(shape, '$path $field entry');
      final fieldIds = _capabilityStringSet(
        shape['fieldIds'],
        '$path $field.fieldIds',
      );
      if (fieldIds == null) {
        continue;
      }
      for (final fieldId in fieldIds) {
        _validateStableCapabilityId(fieldId, '$path $field.fieldIds');
        if (!definedFields.containsKey(fieldId)) {
          errors.add('$path 的 $field 引用了未知 field：$fieldId');
        }
      }
      final shapeId = shape['id'];
      final expectedShapeFields = shapeId is String
          ? expectedFieldIds[shapeId]
          : null;
      if (shapeId is String &&
          (expectedShapeFields == null ||
              !_sameStringSet(expectedShapeFields, fieldIds))) {
        errors.add('$path 的 $field.$shapeId fieldIds 与已批准 V4 快照不一致');
      }
    }
    if (!_sameStringSet(ids, expectedIds)) {
      errors.add('$path 的 $field ID 与已批准 V4 快照不一致');
    }
    return ids;
  }

  Set<String> _validateCapabilityOperations(
    Object? value,
    Set<String> requests,
    Set<String> results,
    Set<String> events,
    Set<String> failures,
    String path,
  ) {
    const expectedIds = {
      'start_session',
      'take_photo',
      'start_recording',
      'stop_recording',
      'switch_camera',
      'set_flash_mode',
      'set_focus_point',
      'set_zoom',
      'retake',
      'confirm',
      'cancel',
      'open_media_read',
      'release_media',
      'attach_live_preview',
      'detach_live_preview',
      'attach_unconfirmed_preview_render',
      'detach_unconfirmed_preview_render',
      'read_media_thumbnail',
      'copy_confirmed_media_to_sink',
    };
    const expectedRequestByOperation = {
      'start_session': 'start_session_request',
      'take_photo': 'session_action_request',
      'start_recording': 'session_action_request',
      'stop_recording': 'session_action_request',
      'switch_camera': 'session_action_request',
      'set_flash_mode': 'flash_mode_request',
      'set_focus_point': 'focus_point_request',
      'set_zoom': 'zoom_request',
      'retake': 'media_handle_request',
      'confirm': 'media_handle_request',
      'cancel': 'session_action_request',
      'open_media_read': 'media_handle_request',
      'release_media': 'media_handle_request',
      'attach_live_preview': 'live_preview_attachment_request',
      'detach_live_preview': 'live_preview_detach_request',
      'attach_unconfirmed_preview_render':
          'unconfirmed_preview_attachment_request',
      'detach_unconfirmed_preview_render': 'unconfirmed_preview_detach_request',
      'read_media_thumbnail': 'media_thumbnail_request',
      'copy_confirmed_media_to_sink': 'media_export_request',
    };
    const expectedResultByOperation = {
      'start_session': 'session_created',
      'take_photo': 'media_preview',
      'start_recording': 'recording_started',
      'stop_recording': 'media_preview',
      'switch_camera': 'control_applied',
      'set_flash_mode': 'control_applied',
      'set_focus_point': 'control_applied',
      'set_zoom': 'control_applied',
      'retake': 'retake_ready',
      'confirm': 'confirmed_media',
      'cancel': 'session_cancelled',
      'open_media_read': 'scoped_media_read',
      'release_media': 'media_released',
      'attach_live_preview': 'render_attachment_attached',
      'detach_live_preview': 'render_attachment_detached',
      'attach_unconfirmed_preview_render': 'render_attachment_attached',
      'detach_unconfirmed_preview_render': 'render_attachment_detached',
      'read_media_thumbnail': 'media_thumbnail',
      'copy_confirmed_media_to_sink': 'media_export_result',
    };
    const expectedScopesByOperation = <String, Set<String>>{
      'start_session': {'session'},
      'take_photo': {'session'},
      'start_recording': {'session'},
      'stop_recording': {'session'},
      'switch_camera': {'session'},
      'set_flash_mode': {'session'},
      'set_focus_point': {'session'},
      'set_zoom': {'session'},
      'retake': {'session', 'media'},
      'confirm': {'session', 'media'},
      'cancel': {'session'},
      'open_media_read': {'media'},
      'release_media': {'media'},
      'attach_live_preview': {'session'},
      'detach_live_preview': {'session'},
      'attach_unconfirmed_preview_render': {'media'},
      'detach_unconfirmed_preview_render': {'media'},
      'read_media_thumbnail': {'media'},
      'copy_confirmed_media_to_sink': {'media'},
    };
    const expectedResultScopeByOperation = <String, String>{
      'start_session': 'session',
      'take_photo': 'session',
      'start_recording': 'session',
      'stop_recording': 'session',
      'switch_camera': 'session',
      'set_flash_mode': 'session',
      'set_focus_point': 'session',
      'set_zoom': 'session',
      'retake': 'session',
      'confirm': 'session',
      'cancel': 'session',
      'open_media_read': 'media',
      'release_media': 'media',
      'attach_live_preview': 'session',
      'detach_live_preview': 'session',
      'attach_unconfirmed_preview_render': 'media',
      'detach_unconfirmed_preview_render': 'media',
      'read_media_thumbnail': 'media',
      'copy_confirmed_media_to_sink': 'media',
    };
    const expectedEventsByOperation = <String, Set<String>>{
      'start_session': {'session_ready', 'session_failed'},
      'take_photo': {'session_failed'},
      'start_recording': {'media_preview_ready', 'session_failed'},
      'stop_recording': {'session_failed'},
      'switch_camera': {'session_failed'},
      'set_flash_mode': {'session_failed'},
      'set_focus_point': {'session_failed'},
      'set_zoom': {'session_failed'},
      'retake': {},
      'confirm': {'media_lease_expired', 'media_read_revoked'},
      'cancel': {},
      'open_media_read': {'media_read_revoked'},
      'release_media': {'media_read_revoked'},
      'attach_live_preview': {'render_attachment_revoked'},
      'detach_live_preview': {},
      'attach_unconfirmed_preview_render': {'render_attachment_revoked'},
      'detach_unconfirmed_preview_render': {},
      'read_media_thumbnail': {},
      'copy_confirmed_media_to_sink': {},
    };
    const expectedFailuresByOperation = <String, Set<String>>{
      'start_session': {
        'invalid_argument',
        'permission_denied',
        'permission_restricted',
        'permission_permanently_denied',
        'resource_in_use',
        'storage_full',
        'unsupported_capability',
        'system_interrupted',
        'session_conflict',
      },
      'take_photo': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'storage_full',
        'encoding_failed',
        'unsupported_capability',
        'system_interrupted',
      },
      'start_recording': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'permission_denied',
        'permission_restricted',
        'permission_permanently_denied',
        'resource_in_use',
        'storage_full',
        'encoding_failed',
        'unsupported_capability',
        'system_interrupted',
      },
      'stop_recording': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'encoding_failed',
        'system_interrupted',
      },
      'switch_camera': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'resource_in_use',
        'unsupported_capability',
        'system_interrupted',
      },
      'set_flash_mode': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'unsupported_capability',
        'system_interrupted',
      },
      'set_focus_point': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'unsupported_capability',
        'system_interrupted',
      },
      'set_zoom': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'unsupported_capability',
        'system_interrupted',
      },
      'retake': {
        'session_invalid',
        'media_invalid',
        'invalid_state',
        'invalid_argument',
      },
      'confirm': {
        'session_invalid',
        'media_invalid',
        'invalid_state',
        'invalid_argument',
      },
      'cancel': {'session_invalid', 'invalid_state', 'invalid_argument'},
      'open_media_read': {'media_invalid', 'invalid_state', 'invalid_argument'},
      'release_media': {'media_invalid', 'invalid_state', 'invalid_argument'},
      'attach_live_preview': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
        'attachment_generation_retired',
        'attachment_target_conflict',
        'system_interrupted',
      },
      'detach_live_preview': {
        'session_invalid',
        'invalid_state',
        'invalid_argument',
      },
      'attach_unconfirmed_preview_render': {
        'media_invalid',
        'invalid_state',
        'invalid_argument',
        'attachment_generation_retired',
        'attachment_target_conflict',
        'system_interrupted',
      },
      'detach_unconfirmed_preview_render': {
        'media_invalid',
        'invalid_state',
        'invalid_argument',
      },
      'read_media_thumbnail': {
        'media_invalid',
        'invalid_state',
        'invalid_argument',
        'thumbnail_generation_failed',
        'thumbnail_generation_cancelled',
        'thumbnail_overloaded',
      },
      'copy_confirmed_media_to_sink': {
        'media_invalid',
        'invalid_state',
        'invalid_argument',
        'system_interrupted',
        'media_export_conflict',
        'media_export_overloaded',
        'media_export_too_large',
        'media_export_sink_rejected',
        'media_export_read_failed',
        'media_export_write_failed',
        'media_export_cancelled',
        'media_export_timed_out',
      },
    };
    final operations = _capabilityObjectList(value, '$path operation');
    final ids = <String>{};
    if (operations == null) {
      return ids;
    }
    for (final operation in operations) {
      _validateCapabilityExactKeys(operation, const {
        'id',
        'description',
        'requestId',
        'resultId',
        'resultScope',
        'eventIds',
        'failureIds',
        'scopes',
        'validFrom',
      }, '$path operation entry');
      _addStableCapabilityId(ids, operation['id'], '$path operation');
      _validateCapabilityDescription(operation, '$path operation entry');
      final operationId = operation['id'];
      if (!requests.contains(operation['requestId'])) {
        errors.add('$path operation 引用了未知 requestId：${operation['requestId']}');
      }
      if (!results.contains(operation['resultId'])) {
        errors.add('$path operation 引用了未知 resultId：${operation['resultId']}');
      }
      final eventIds = _capabilityStringSet(
        operation['eventIds'],
        '$path operation.eventIds',
      );
      final failureIds = _capabilityStringSet(
        operation['failureIds'],
        '$path operation.failureIds',
      );
      for (final eventId in eventIds ?? const <String>{}) {
        if (!events.contains(eventId)) {
          errors.add('$path operation 引用了未知 eventId：$eventId');
        }
      }
      for (final failureId in failureIds ?? const <String>{}) {
        if (!failures.contains(failureId)) {
          errors.add('$path operation 引用了未知 failureId：$failureId');
        }
      }
      final scopes = _capabilityStringSet(
        operation['scopes'],
        '$path operation.scopes',
      );
      if (scopes != null &&
          (scopes.isEmpty || !const {'session', 'media'}.containsAll(scopes))) {
        errors.add('$path operation.scopes 必须是非空 session/media 集合');
      }
      if (operationId is String &&
          (operation['requestId'] != expectedRequestByOperation[operationId] ||
              operation['resultId'] != expectedResultByOperation[operationId] ||
              operation['resultScope'] !=
                  expectedResultScopeByOperation[operationId] ||
              scopes == null ||
              !_sameStringSet(
                scopes,
                expectedScopesByOperation[operationId] ?? const <String>{},
              ) ||
              eventIds == null ||
              !_sameStringSet(
                eventIds,
                expectedEventsByOperation[operationId] ?? const <String>{},
              ) ||
              failureIds == null ||
              !_sameStringSet(
                failureIds,
                expectedFailuresByOperation[operationId] ?? const <String>{},
              ))) {
        errors.add(
          '$path operation $operationId 的 request/result/event/failure/scope 不正确',
        );
      }
      final validFrom = _capabilityObjectList(
        operation['validFrom'],
        '$path operation.validFrom',
      );
      final validFromScopes = <String>{};
      for (final entry in validFrom ?? const <Map<String, Object?>>[]) {
        _validateCapabilityExactKeys(entry, const {
          'scope',
          'states',
        }, '$path operation.validFrom entry');
        final scope = entry['scope'];
        if (scope is! String ||
            !const {'session', 'media'}.contains(scope) ||
            scopes == null ||
            !scopes.contains(scope)) {
          errors.add('$path operation.validFrom 使用未声明 scope：$scope');
        } else if (!validFromScopes.add(scope)) {
          errors.add('$path operation.validFrom 重复 scope：$scope');
        }
        final states = _capabilityStringSet(
          entry['states'],
          '$path operation.validFrom.states',
        );
        if (states != null && states.isEmpty) {
          errors.add('$path operation.validFrom.states 不得为空');
        }
        for (final state in states ?? const <String>{}) {
          _validateStableCapabilityId(state, '$path operation.validFrom');
        }
      }
      if (scopes != null && !_sameStringSet(validFromScopes, scopes)) {
        errors.add('$path operation 的 scopes 与 validFrom scopes 必须精确一致');
      }
      if (scopes != null && !scopes.contains(operation['resultScope'])) {
        errors.add('$path operation.resultScope 必须属于 scopes');
      }
    }
    if (!_sameStringSet(ids, expectedIds)) {
      errors.add('$path 的 operation ID 与已批准 V4 范围不一致');
    }
    return ids;
  }

  void _validateCapabilityTerminalFailureField(
    Object? fieldValue,
    Object? failureValue,
    String path,
  ) {
    final fields = _capabilityObjectList(fieldValue, '$path field');
    final failures = _capabilityObjectList(failureValue, '$path failure');
    if (fields == null || failures == null) {
      return;
    }
    final terminalField = fields.where(
      (field) => field['id'] == 'terminal_failure_id',
    );
    if (terminalField.length != 1) {
      return;
    }
    final declaredIds = _capabilityStringSet(
      terminalField.single['enumValues'],
      '$path terminal_failure_id.enumValues',
    );
    final terminalIds = <String>{};
    for (final failure in failures) {
      if (failure['terminal'] == true && failure['id'] is String) {
        terminalIds.add(failure['id'] as String);
      }
    }
    if (declaredIds != null && !_sameStringSet(declaredIds, terminalIds)) {
      errors.add('$path terminal_failure_id 必须精确枚举 terminal Failure ID');
    }
  }

  Set<String> _validateCapabilityStates(
    Object? value,
    Object? operationValue,
    Set<String> operations,
    Set<String> lifecycleRules,
    Set<String> results,
    Set<String> events,
    Set<String> failures,
    String path,
  ) {
    final machines = _capabilityObjectList(value, '$path stateMachines');
    if (machines == null) {
      return <String>{};
    }
    final machinesById = <String, Map<String, Object?>>{};
    final stateIds = <String>{};
    for (final machine in machines) {
      final id = machine['id'];
      if (id is! String || machinesById.containsKey(id)) {
        errors.add('$path stateMachines 必须声明唯一字符串 id');
      } else {
        machinesById[id] = machine;
      }
      final states = _capabilityObjectList(
        machine['items'],
        '$path stateMachines.items',
      );
      for (final state in states ?? const <Map<String, Object?>>[]) {
        final stateId = state['id'];
        if (stateId is String) {
          stateIds.add(stateId);
        }
      }
    }
    if (!_sameStringSet(machinesById.keys.toSet(), const {
      'session',
      'media',
    })) {
      errors.add('$path 的 Media Capture Profile 必须精确声明 session/media 状态机');
    }

    final operationScopes = <String, Set<String>>{};
    final operationValidFrom = <String, Map<String, Set<String>>>{};
    final operationResults = <String, String>{};
    final operationResultScopes = <String, String>{};
    final operationEvents = <String, Set<String>>{};
    final operationFailures = <String, Set<String>>{};
    final operationItems = _capabilityObjectList(
      operationValue,
      '$path operation',
    );
    for (final operation in operationItems ?? const <Map<String, Object?>>[]) {
      final id = operation['id'];
      if (id is! String) {
        continue;
      }
      operationScopes[id] =
          _capabilityStringSet(operation['scopes'], '$path operation.scopes') ??
          <String>{};
      if (operation['resultId'] is String) {
        operationResults[id] = operation['resultId'] as String;
      }
      if (operation['resultScope'] is String) {
        operationResultScopes[id] = operation['resultScope'] as String;
      }
      operationEvents[id] =
          _capabilityStringSet(
            operation['eventIds'],
            '$path operation.eventIds',
          ) ??
          <String>{};
      operationFailures[id] =
          _capabilityStringSet(
            operation['failureIds'],
            '$path operation.failureIds',
          ) ??
          <String>{};
      final byScope = <String, Set<String>>{};
      final validFrom = _capabilityObjectList(
        operation['validFrom'],
        '$path operation.validFrom',
      );
      for (final entry in validFrom ?? const <Map<String, Object?>>[]) {
        final scope = entry['scope'];
        if (scope is String) {
          byScope[scope] =
              _capabilityStringSet(
                entry['states'],
                '$path operation.validFrom.states',
              ) ??
              <String>{};
        }
      }
      operationValidFrom[id] = byScope;
    }

    _validateCapabilityStateMachine(
      machinesById['session'],
      scope: 'session',
      multiplicity: 'single_active',
      initial: 'idle',
      expectedStates: const {
        'idle',
        'requesting_permission',
        'preparing',
        'ready',
        'recording',
        'previewing',
        'completed',
        'cancelled',
        'failed',
      },
      expectedTerminals: const {'completed', 'cancelled', 'failed'},
      expectedLifecycleTriggers: const {
        'permission_resolved',
        'resources_ready',
        'video_duration_reached',
        'capability_failure',
        'preview_timed_out',
        'app_restarted',
      },
      operations: operations,
      operationScopes: operationScopes,
      operationValidFrom: operationValidFrom,
      operationResults: operationResults,
      operationResultScopes: operationResultScopes,
      operationEvents: operationEvents,
      operationFailures: operationFailures,
      lifecycleRules: lifecycleRules,
      results: results,
      events: events,
      failures: failures,
      path: path,
    );
    _validateCapabilityStateMachine(
      machinesById['media'],
      scope: 'media',
      multiplicity: 'per_handle_multiple',
      initial: 'preview',
      expectedStates: const {
        'preview',
        'leased',
        'release_grace',
        'expiry_grace',
        'discarded',
        'released',
        'expired',
      },
      expectedTerminals: const {'discarded', 'released', 'expired'},
      expectedLifecycleTriggers: const {
        'capability_failure',
        'session_cancelled',
        'preview_timed_out',
        'lease_expired',
        'release_read_grace_elapsed',
        'expiry_read_grace_elapsed',
        'app_restarted',
      },
      operations: operations,
      operationScopes: operationScopes,
      operationValidFrom: operationValidFrom,
      operationResults: operationResults,
      operationResultScopes: operationResultScopes,
      operationEvents: operationEvents,
      operationFailures: operationFailures,
      lifecycleRules: lifecycleRules,
      results: results,
      events: events,
      failures: failures,
      path: path,
    );
    return stateIds;
  }

  void _validateCapabilityStateMachine(
    Object? value, {
    required String scope,
    required String multiplicity,
    required String initial,
    required Set<String> expectedStates,
    required Set<String> expectedTerminals,
    required Set<String> expectedLifecycleTriggers,
    required Set<String> operations,
    required Map<String, Set<String>> operationScopes,
    required Map<String, Map<String, Set<String>>> operationValidFrom,
    required Map<String, String> operationResults,
    required Map<String, String> operationResultScopes,
    required Map<String, Set<String>> operationEvents,
    required Map<String, Set<String>> operationFailures,
    required Set<String> lifecycleRules,
    required Set<String> results,
    required Set<String> events,
    required Set<String> failures,
    required String path,
  }) {
    final machine = _capabilityObject(value, '$path state.$scope');
    if (machine == null) {
      return;
    }
    _validateCapabilityExactKeys(machine, const {
      'id',
      'description',
      'multiplicity',
      'initial',
      'terminal',
      'items',
      'transitions',
    }, '$path state.$scope');
    if (machine['id'] != scope || machine['multiplicity'] != multiplicity) {
      errors.add('$path 的 $scope 状态机 id/multiplicity 不正确');
    }
    _validateCapabilityDescription(machine, '$path stateMachines.$scope');
    if (machine['initial'] != initial) {
      errors.add('$path 的 $scope 初始 state 必须是 $initial');
    }

    final items = _capabilityObjectList(
      machine['items'],
      '$path state.$scope.items',
    );
    final ids = <String>{};
    final terminalFlags = <String, bool>{};
    for (final item in items ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(item, const {
        'id',
        'description',
        'terminal',
      }, '$path state.$scope item');
      _addStableCapabilityId(ids, item['id'], '$path state.$scope');
      _validateCapabilityDescription(item, '$path state.$scope item');
      if (item['id'] is String && item['terminal'] is bool) {
        terminalFlags[item['id'] as String] = item['terminal'] as bool;
      } else {
        errors.add('$path state.$scope item 的 terminal 必须是 bool');
      }
    }
    if (!_sameStringSet(ids, expectedStates)) {
      errors.add('$path 的 $scope state ID 与已批准 V2 状态机不一致');
    }
    final terminals = _capabilityStringSet(
      machine['terminal'],
      '$path state.$scope.terminal',
    );
    if (terminals != null && !_sameStringSet(terminals, expectedTerminals)) {
      errors.add('$path 的 $scope terminal state 与已批准生命周期不一致');
    }
    if (terminals != null) {
      for (final item in terminalFlags.entries) {
        if (item.value != terminals.contains(item.key)) {
          errors.add('$path 的 $scope state terminal 标记与列表不一致');
        }
      }
    }

    final transitions = _capabilityObjectList(
      machine['transitions'],
      '$path state.$scope.transitions',
    );
    final operationTransitionFrom = <String, Set<String>>{};
    final lifecycleTriggers = <String>{};
    final adjacency = <String, Set<String>>{};
    final transitionEdges = <String>{};
    for (final transition in transitions ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(transition, const {
        'triggerKind',
        'triggerId',
        'fromStates',
        'toState',
        'outcome',
        'emission',
      }, '$path state.$scope transition');
      final triggerKind = transition['triggerKind'];
      final triggerId = transition['triggerId'];
      if (triggerId is! String) {
        errors.add('$path state.$scope transition 必须声明 triggerId');
      } else {
        _validateStableCapabilityId(triggerId, '$path state.$scope trigger');
        if (triggerKind == 'operation') {
          if (!operations.contains(triggerId)) {
            errors.add('$path state.$scope 引用了未知 operation：$triggerId');
          }
          if (!(operationScopes[triggerId] ?? const <String>{}).contains(
            scope,
          )) {
            errors.add('$path operation $triggerId 未声明 $scope scope');
          }
        } else if (triggerKind == 'lifecycle') {
          lifecycleTriggers.add(triggerId);
          if (!lifecycleRules.contains(triggerId)) {
            errors.add(
              '$path state.$scope 引用了未在 lifecycle.rules 声明的 trigger：'
              '$triggerId',
            );
          }
        } else {
          errors.add('$path state.$scope transition triggerKind 无效');
        }
      }

      final fromStates = _capabilityStringSet(
        transition['fromStates'],
        '$path state.$scope transition.fromStates',
      );
      final toState = transition['toState'];
      final emission = _capabilityObject(
        transition['emission'],
        '$path state.$scope transition.emission',
      );
      String? emissionKind;
      String? emissionId;
      if (emission != null) {
        _validateCapabilityExactKeys(emission, const {
          'kind',
          'id',
        }, '$path state.$scope transition.emission');
        emissionKind = emission['kind'] as String?;
        emissionId = emission['id'] as String?;
        final validEmission = switch (emissionKind) {
          'result' => emissionId != null && results.contains(emissionId),
          'event' => emissionId != null && events.contains(emissionId),
          'failure' => emissionId != null && failures.contains(emissionId),
          'none' => emission['id'] == null,
          _ => false,
        };
        if (!validEmission) {
          errors.add('$path state.$scope transition emission 引用无效');
        }
        if (triggerKind == 'operation' && triggerId is String) {
          if (emissionKind == 'event' &&
              !(operationEvents[triggerId] ?? const <String>{}).contains(
                emissionId,
              )) {
            errors.add('$path operation $triggerId 交付了未声明 event');
          }
          if (emissionKind == 'failure' &&
              !(operationFailures[triggerId] ?? const <String>{}).contains(
                emissionId,
              )) {
            errors.add('$path operation $triggerId 交付了未声明 failure');
          }
          final isResultScope = operationResultScopes[triggerId] == scope;
          if (isResultScope &&
              (emissionKind != 'result' ||
                  emissionId != operationResults[triggerId])) {
            errors.add(
              '$path operation $triggerId 的 resultScope transition '
              '必须交付其声明 result',
            );
          }
          if (!isResultScope &&
              (emissionKind != 'none' || emission['id'] != null)) {
            errors.add(
              '$path operation $triggerId 的 companion scope transition '
              '不得重复交付 result',
            );
          }
        }
        if (triggerKind == 'lifecycle' && triggerId is String) {
          final expectedLifecycleEmissions = scope == 'session'
              ? const {
                  'permission_resolved': 'none:null',
                  'resources_ready': 'event:session_ready',
                  'video_duration_reached': 'event:media_preview_ready',
                  'capability_failure': 'event:session_failed',
                  'preview_timed_out': 'failure:session_timeout',
                  'app_restarted': 'none:null',
                }
              : const {
                  'session_cancelled': 'none:null',
                  'capability_failure': 'none:null',
                  'preview_timed_out': 'none:null',
                  'lease_expired': 'event:media_lease_expired',
                  'release_read_grace_elapsed': 'event:media_read_revoked',
                  'expiry_read_grace_elapsed': 'event:media_read_revoked',
                  'app_restarted': 'none:null',
                };
          if (expectedLifecycleEmissions[triggerId] !=
              '$emissionKind:${emission['id']}') {
            errors.add(
              '$path lifecycle $triggerId 的 emission 与 V1-preserved semantics 不一致',
            );
          }
        }
      }
      for (final from in fromStates ?? const <String>{}) {
        if (!ids.contains(from)) {
          errors.add('$path state.$scope 引用了未知 fromState：$from');
        }
        if (toState is String) {
          adjacency.putIfAbsent(from, () => <String>{}).add(toState);
          final signature =
              '$triggerKind:$triggerId:$from->$toState:${transition['outcome']}';
          if (!transitionEdges.add(signature)) {
            errors.add('$path state.$scope 包含重复 transition：$signature');
          }
        }
        if (triggerKind == 'operation' && triggerId is String) {
          operationTransitionFrom
              .putIfAbsent(triggerId, () => <String>{})
              .add(from);
        }
      }
      if (toState is! String || !ids.contains(toState)) {
        errors.add('$path state.$scope 引用了未知 toState：$toState');
      }
      if (!const {
        'success',
        'cancelled',
        'failure',
        'expired',
      }.contains(transition['outcome'])) {
        errors.add('$path state.$scope transition outcome 无效');
      }
    }
    if (!_sameStringSet(lifecycleTriggers, expectedLifecycleTriggers)) {
      errors.add('$path 的 $scope lifecycle transition 不完整');
    }
    final expectedEdges = scope == 'session'
        ? const {
            'operation:start_session:idle->requesting_permission:success',
            'lifecycle:permission_resolved:requesting_permission->preparing:success',
            'lifecycle:resources_ready:preparing->ready:success',
            'operation:take_photo:ready->previewing:success',
            'operation:start_recording:ready->recording:success',
            'lifecycle:video_duration_reached:recording->previewing:success',
            'operation:stop_recording:recording->previewing:success',
            'operation:stop_recording:previewing->previewing:success',
            'operation:switch_camera:ready->ready:success',
            'operation:set_flash_mode:ready->ready:success',
            'operation:set_flash_mode:recording->recording:success',
            'operation:set_focus_point:ready->ready:success',
            'operation:set_focus_point:recording->recording:success',
            'operation:set_zoom:ready->ready:success',
            'operation:set_zoom:recording->recording:success',
            'operation:attach_live_preview:ready->ready:success',
            'operation:attach_live_preview:recording->recording:success',
            'operation:detach_live_preview:requesting_permission->requesting_permission:success',
            'operation:detach_live_preview:preparing->preparing:success',
            'operation:detach_live_preview:ready->ready:success',
            'operation:detach_live_preview:recording->recording:success',
            'operation:detach_live_preview:previewing->previewing:success',
            'operation:detach_live_preview:completed->completed:success',
            'operation:detach_live_preview:cancelled->cancelled:success',
            'operation:detach_live_preview:failed->failed:success',
            'operation:retake:previewing->ready:success',
            'operation:confirm:previewing->completed:success',
            'operation:cancel:requesting_permission->cancelled:cancelled',
            'operation:cancel:preparing->cancelled:cancelled',
            'operation:cancel:ready->cancelled:cancelled',
            'operation:cancel:recording->cancelled:cancelled',
            'operation:cancel:previewing->cancelled:cancelled',
            'operation:cancel:cancelled->cancelled:cancelled',
            'lifecycle:capability_failure:requesting_permission->failed:failure',
            'lifecycle:capability_failure:preparing->failed:failure',
            'lifecycle:capability_failure:ready->failed:failure',
            'lifecycle:capability_failure:recording->failed:failure',
            'lifecycle:capability_failure:previewing->failed:failure',
            'lifecycle:preview_timed_out:previewing->failed:failure',
            'lifecycle:app_restarted:requesting_permission->failed:failure',
            'lifecycle:app_restarted:preparing->failed:failure',
            'lifecycle:app_restarted:ready->failed:failure',
            'lifecycle:app_restarted:recording->failed:failure',
            'lifecycle:app_restarted:previewing->failed:failure',
          }
        : const {
            'operation:retake:preview->discarded:success',
            'lifecycle:session_cancelled:preview->discarded:cancelled',
            'operation:confirm:preview->leased:success',
            'operation:open_media_read:leased->leased:success',
            'operation:attach_unconfirmed_preview_render:preview->preview:success',
            'operation:detach_unconfirmed_preview_render:preview->preview:success',
            'operation:detach_unconfirmed_preview_render:leased->leased:success',
            'operation:detach_unconfirmed_preview_render:release_grace->release_grace:success',
            'operation:detach_unconfirmed_preview_render:expiry_grace->expiry_grace:success',
            'operation:detach_unconfirmed_preview_render:discarded->discarded:success',
            'operation:detach_unconfirmed_preview_render:released->released:success',
            'operation:detach_unconfirmed_preview_render:expired->expired:success',
            'operation:read_media_thumbnail:leased->leased:success',
            'operation:copy_confirmed_media_to_sink:leased->leased:success',
            'operation:release_media:leased->release_grace:success',
            'operation:release_media:release_grace->release_grace:success',
            'operation:release_media:released->released:success',
            'lifecycle:capability_failure:preview->discarded:failure',
            'lifecycle:preview_timed_out:preview->discarded:failure',
            'lifecycle:lease_expired:leased->expiry_grace:expired',
            'lifecycle:release_read_grace_elapsed:release_grace->released:success',
            'lifecycle:expiry_read_grace_elapsed:expiry_grace->expired:expired',
            'lifecycle:app_restarted:preview->discarded:expired',
            'lifecycle:app_restarted:leased->expired:expired',
            'lifecycle:app_restarted:release_grace->expired:expired',
            'lifecycle:app_restarted:expiry_grace->expired:expired',
          };
    if (!_sameStringSet(transitionEdges, expectedEdges)) {
      errors.add('$path 的 $scope 状态转换与已批准 V4 快照不一致');
    }

    for (final operation in operationValidFrom.entries) {
      final declaredStates = operation.value[scope];
      if (declaredStates == null) {
        continue;
      }
      for (final declaredState in declaredStates) {
        if (!ids.contains(declaredState)) {
          errors.add(
            '$path operation ${operation.key} 的 $scope validFrom state 不存在：'
            '$declaredState',
          );
        }
      }
      final transitionStates =
          operationTransitionFrom[operation.key] ?? const <String>{};
      if (!_sameStringSet(transitionStates, declaredStates)) {
        errors.add(
          '$path operation ${operation.key} 的 $scope validFrom 与状态转换不一致',
        );
      }
    }

    final reachable = <String>{initial};
    final queue = <String>[initial];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final next in adjacency[current] ?? const <String>{}) {
        if (reachable.add(next)) {
          queue.add(next);
        }
      }
    }
    if (!reachable.containsAll(ids)) {
      errors.add(
        '$path 的 $scope 状态机包含不可达状态：${ids.difference(reachable).join(', ')}',
      );
    }

    final cancelTransitions = transitions
        ?.where(
          (item) =>
              item['triggerKind'] == 'operation' &&
              item['triggerId'] == 'cancel',
        )
        .toList();
    if (scope == 'session' &&
        (cancelTransitions == null ||
            cancelTransitions.isEmpty ||
            cancelTransitions.any(
              (item) =>
                  item['outcome'] != 'cancelled' ||
                  item['toState'] != 'cancelled',
            ))) {
      errors.add('$path 的用户 cancel 必须产生独立 session cancelled 状态');
    }
    final sessionCancelledTransitions = transitions
        ?.where(
          (item) =>
              item['triggerKind'] == 'lifecycle' &&
              item['triggerId'] == 'session_cancelled',
        )
        .toList();
    if (scope == 'media' &&
        (sessionCancelledTransitions == null ||
            sessionCancelledTransitions.length != 1 ||
            sessionCancelledTransitions.single['outcome'] != 'cancelled' ||
            sessionCancelledTransitions.single['toState'] != 'discarded')) {
      errors.add('$path 的用户 cancel 必须通过生命周期清理未确认 media');
    }

    final confirmTransitions = transitions
        ?.where(
          (item) =>
              item['triggerKind'] == 'operation' &&
              item['triggerId'] == 'confirm',
        )
        .toList();
    final expectedConfirmState = scope == 'session' ? 'completed' : 'leased';
    if (confirmTransitions == null ||
        confirmTransitions.length != 1 ||
        confirmTransitions.single['toState'] != expectedConfirmState) {
      errors.add('$path 的 confirm 必须结束 Session 并创建独立 Media lease');
    }
  }

  Set<String> _validateCapabilityFailures(Object? value, String path) {
    const expectedIds = {
      'permission_denied',
      'permission_restricted',
      'permission_permanently_denied',
      'resource_in_use',
      'storage_full',
      'encoding_failed',
      'media_invalid',
      'session_invalid',
      'unsupported_capability',
      'system_interrupted',
      'session_conflict',
      'invalid_state',
      'invalid_argument',
      'session_timeout',
      'thumbnail_generation_failed',
      'thumbnail_generation_cancelled',
      'thumbnail_overloaded',
      'attachment_generation_retired',
      'attachment_target_conflict',
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
    };
    const expectedBehavior = {
      'permission_denied': 'true|true',
      'permission_restricted': 'false|true',
      'permission_permanently_denied': 'false|true',
      'resource_in_use': 'true|true',
      'storage_full': 'true|true',
      'encoding_failed': 'true|true',
      'media_invalid': 'false|false',
      'session_invalid': 'false|false',
      'unsupported_capability': 'true|false',
      'system_interrupted': 'true|true',
      'session_conflict': 'true|false',
      'invalid_state': 'true|false',
      'invalid_argument': 'true|false',
      'session_timeout': 'true|true',
      'thumbnail_generation_failed': 'true|false',
      'thumbnail_generation_cancelled': 'true|false',
      'thumbnail_overloaded': 'true|false',
      'attachment_generation_retired': 'false|false',
      'attachment_target_conflict': 'true|false',
      'media_export_conflict': 'true|false',
      'media_export_overloaded': 'true|false',
      'media_export_too_large': 'true|false',
      'media_export_sink_rejected': 'true|false',
      'media_export_read_failed': 'true|false',
      'media_export_write_failed': 'true|false',
      'media_export_cancelled': 'true|false',
      'media_export_timed_out': 'true|false',
    };
    final failures = _capabilityObjectList(value, '$path failure');
    final ids = <String>{};
    if (failures == null) {
      return ids;
    }
    for (final failure in failures) {
      _validateCapabilityExactKeys(failure, const {
        'id',
        'description',
        'recoverable',
        'terminal',
      }, '$path failure entry');
      _addStableCapabilityId(ids, failure['id'], '$path failure');
      _validateCapabilityDescription(failure, '$path failure entry');
      if (failure['recoverable'] is! bool || failure['terminal'] is! bool) {
        errors.add('$path failure 的 recoverable/terminal 必须是 bool');
      }
      if (failure['id'] is String &&
          expectedBehavior[failure['id']] !=
              '${failure['recoverable']}|${failure['terminal']}') {
        errors.add('$path failure ${failure['id']} 的恢复/终止语义不正确');
      }
    }
    if (!_sameStringSet(ids, expectedIds)) {
      errors.add('$path 的 failure ID 与已批准 V4 语义不一致');
    }
    if (ids.contains('cancel') || ids.contains('session_cancelled')) {
      errors.add('$path 不得把用户取消定义为 failure');
    }
    return ids;
  }

  void _validateCapabilityPermissions(
    Object? value,
    Set<String> operations,
    String path,
  ) {
    final permission = _capabilityObject(value, '$path permission');
    if (permission == null) {
      return;
    }
    _validateCapabilityExactKeys(permission, const {
      'requestTrigger',
      'resources',
      'states',
    }, '$path permission');
    if (permission['requestTrigger'] != 'explicit_user_action') {
      errors.add('$path 的权限请求必须由明确用户操作触发');
    }
    final resources = _capabilityObjectList(
      permission['resources'],
      '$path permission.resources',
    );
    final resourceIds = <String>{};
    final policies = <String, String>{};
    final operationsByResource = <String, Set<String>>{};
    if (resources != null) {
      for (final resource in resources) {
        _validateCapabilityExactKeys(resource, const {
          'id',
          'description',
          'requiredForOperations',
          'requestPolicy',
        }, '$path permission resource');
        _addStableCapabilityId(
          resourceIds,
          resource['id'],
          '$path permission resource',
        );
        _validateCapabilityDescription(resource, '$path permission resource');
        if (resource['id'] is String && resource['requestPolicy'] is String) {
          policies[resource['id'] as String] =
              resource['requestPolicy'] as String;
        }
        final requiredOperations = _capabilityStringSet(
          resource['requiredForOperations'],
          '$path permission.requiredForOperations',
        );
        if (resource['id'] is String && requiredOperations != null) {
          operationsByResource[resource['id'] as String] = requiredOperations;
        }
        for (final operation in requiredOperations ?? const <String>{}) {
          if (!operations.contains(operation)) {
            errors.add('$path permission 引用了未知 operation：$operation');
          }
        }
      }
    }
    if (!_sameStringSet(resourceIds, const {
      'camera',
      'microphone',
      'photo_library',
    })) {
      errors.add('$path 必须分离 Camera、Microphone 与 Photo Library 权限');
    }
    if (policies['camera'] != 'request_when_user_starts_capture' ||
        policies['microphone'] != 'request_when_user_starts_audio_recording' ||
        policies['photo_library'] != 'never_request_non_target') {
      errors.add('$path 的权限按需请求或 Photo Library 非目标策略不完整');
    }
    const expectedPermissionOperations = <String, Set<String>>{
      'camera': {'start_session', 'take_photo', 'start_recording'},
      'microphone': {'start_recording'},
      'photo_library': {},
    };
    for (final entry in expectedPermissionOperations.entries) {
      final actual = operationsByResource[entry.key];
      if (actual == null || !_sameStringSet(actual, entry.value)) {
        errors.add('$path 的 ${entry.key} requiredForOperations 不正确');
      }
    }

    final states = _capabilityObjectList(
      permission['states'],
      '$path permission.states',
    );
    final stateIds = <String>{};
    if (states != null) {
      for (final state in states) {
        _validateCapabilityExactKeys(state, const {
          'id',
          'description',
        }, '$path permission state');
        _addStableCapabilityId(stateIds, state['id'], '$path permission state');
        _validateCapabilityDescription(state, '$path permission state');
      }
    }
    const expectedStates = {
      'not_determined',
      'granted',
      'denied',
      'restricted',
      'permanently_denied',
      'unsupported',
    };
    if (!_sameStringSet(stateIds, expectedStates)) {
      errors.add('$path 的 permission state 与已批准语义不一致');
    }
  }

  Set<String> _validateCapabilityLifecycle(Object? value, String path) {
    final lifecycle = _capabilityObject(value, '$path lifecycle');
    if (lifecycle == null) {
      return <String>{};
    }
    _validateCapabilityExactKeys(lifecycle, const {
      'owner',
      'concurrency',
      'rules',
    }, '$path lifecycle');
    if (lifecycle['owner'] != 'native_module' ||
        lifecycle['concurrency'] !=
            'single_active_session_per_module_instance') {
      errors.add('$path 的 Session owner 或并发策略不符合模块边界');
    }
    final ids = _capabilitySemanticEntryIds(
      lifecycle['rules'],
      '$path lifecycle.rules',
    );
    const expectedIds = {
      'explicit_user_start',
      'module_owned_session',
      'idempotent_close_operations',
      'platform_context_documented',
      'permission_resolved',
      'resources_ready',
      'video_duration_reached',
      'session_cancelled',
      'capability_failure',
      'lease_expired',
      'release_read_grace_elapsed',
      'expiry_read_grace_elapsed',
      'app_restarted',
      'preview_timed_out',
      'display_rotation_changed',
      'app_backgrounded',
      'preview_owner_destroyed',
      'session_terminal',
      'core_closed',
      'thumbnail_read_cancelled',
      'thumbnail_generation_aborted',
      'thumbnail_result_committed',
      'media_export_cancel_requested',
      'media_export_deadline_elapsed',
      'media_export_aborted',
      'media_export_committed',
    };
    if (ids != null && !_sameStringSet(ids, expectedIds)) {
      errors.add('$path 的 lifecycle rules 与已批准语义不一致');
    }
    return ids ?? <String>{};
  }

  void _validateCapabilityResourcePolicy(
    Object? value,
    Map<String, String> fields,
    Set<String> operations,
    Set<String> stateIds,
    Set<String> lifecycleRules,
    Set<String> failures,
    String path,
  ) {
    final policy = _capabilityObject(value, '$path resourcePolicy');
    if (policy == null) {
      return;
    }
    _validateCapabilityExactKeys(policy, const {
      'resources',
      'ownershipPhases',
      'handles',
      'leases',
      'attachments',
      'renderSurfaces',
      'boundedCopies',
      'streamingCopies',
      'cleanup',
      'privacy',
    }, '$path resourcePolicy');

    final resources = _capabilityObjectList(
      policy['resources'],
      '$path resourcePolicy.resources',
    );
    final resourceIds = <String>{};
    const expectedResources = {
      'capture_session': 'managed_session|native_module|memory_registry',
      'captured_media': 'managed_file|native_module|app_private_temporary',
      'live_preview_attachment':
          'callback_attachment|native_module|transient_memory',
      'unconfirmed_preview_render_attachment':
          'callback_attachment|native_module|transient_memory',
      'live_platform_render_surface':
          'module_defined_platform_surface|native_consumer|transient_ui',
      'unconfirmed_platform_render_surface':
          'module_defined_platform_surface|native_consumer|transient_ui',
      'thumbnail_generation_job': 'managed_job|native_module|transient_memory',
      'thumbnail_generation_buffer':
          'managed_buffer|native_module|transient_sensitive_memory',
      'thumbnail_copy': 'bounded_copy|caller|caller_memory',
      'media_export_job': 'managed_job|native_module|transient_memory',
      'media_export_buffer':
          'managed_buffer|native_module|transient_sensitive_memory',
    };
    for (final resource in resources ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(resource, const {
        'id',
        'description',
        'kind',
        'physicalOwner',
        'storageScope',
      }, '$path resourcePolicy resource');
      _addStableCapabilityId(
        resourceIds,
        resource['id'],
        '$path resourcePolicy resource',
      );
      _validateCapabilityDescription(resource, '$path resourcePolicy resource');
      if (resource['id'] is String &&
          expectedResources[resource['id']] !=
              '${resource['kind']}|${resource['physicalOwner']}|'
                  '${resource['storageScope']}') {
        errors.add('$path resource ${resource['id']} 与 V4 Profile 不一致');
      }
    }
    if (!_sameStringSet(resourceIds, expectedResources.keys.toSet())) {
      errors.add('$path resourcePolicy.resources 不完整');
    }

    final phases = _capabilityObjectList(
      policy['ownershipPhases'],
      '$path resourcePolicy.ownershipPhases',
    );
    final phaseSignatures = <String, String>{};
    for (final phase in phases ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(phase, const {
        'id',
        'description',
        'resourceId',
        'stateMachineId',
        'stateIds',
        'logicalOwner',
        'expiresAfterSeconds',
      }, '$path ownership phase');
      final id = phase['id'];
      final states = _capabilityStringSet(
        phase['stateIds'],
        '$path ownership phase stateIds',
      );
      if (id is String && states != null) {
        if (phaseSignatures.containsKey(id)) {
          errors.add('$path ownershipPhases 包含重复 id：$id');
        }
        final sortedStates = states.toList()..sort();
        phaseSignatures[id] =
            '${phase['resourceId']}|${phase['stateMachineId']}|'
            '${sortedStates.join(',')}|${phase['logicalOwner']}|'
            '${phase['expiresAfterSeconds']}';
      }
      _validateCapabilityDescription(phase, '$path ownership phase');
    }
    const expectedPhases = {
      'session_active':
          'capture_session|session|idle,preparing,previewing,ready,recording,'
          'requesting_permission|native_module|null',
      'session_tombstone':
          'capture_session|session|cancelled,completed,failed|module_registry|300',
      'media_preview': 'captured_media|media|preview|native_module|600',
      'media_consumer_lease':
          'captured_media|media|leased|consumer_logical_lease|86400',
      'media_read_grace':
          'captured_media|media|expiry_grace,release_grace|native_module|60',
      'media_tombstone':
          'captured_media|media|discarded,expired,released|module_registry|300',
      'live_preview_render_scope':
          'live_preview_attachment|session|ready,recording|'
          'native_ui_owner_generation|null',
      'unconfirmed_preview_render_scope':
          'unconfirmed_preview_render_attachment|media|preview|'
          'native_ui_owner_generation|null',
      'live_render_surface_owner_scope':
          'live_platform_render_surface|session|ready,recording|'
          'native_consumer_surface_owner|null',
      'unconfirmed_render_surface_owner_scope':
          'unconfirmed_platform_render_surface|media|preview|'
          'native_consumer_surface_owner|null',
      'thumbnail_generation_job_scope':
          'thumbnail_generation_job|media|leased|native_module|null',
      'thumbnail_generation_buffer_scope':
          'thumbnail_generation_buffer|media|leased|native_module|null',
      'media_export_job_scope':
          'media_export_job|media|leased|native_module|null',
      'media_export_buffer_scope':
          'media_export_buffer|media|leased|native_module|null',
    };
    if (!_sameStringSet(
      phaseSignatures.keys.toSet(),
      expectedPhases.keys.toSet(),
    )) {
      errors.add('$path ownershipPhases ID 不完整');
    }
    for (final expected in expectedPhases.entries) {
      if (phaseSignatures[expected.key] != expected.value) {
        errors.add('$path ownership phase ${expected.key} 与 V4 Profile 不一致');
      }
    }

    final handles = _capabilityObjectList(
      policy['handles'],
      '$path resourcePolicy.handles',
    );
    const expectedHandles = {
      'session_handle_policy':
          'capture_session|session_handle|module_instance|true|'
          'cryptographically_secure_random|128|128|true|'
          'true|false|false|300|session_invalid',
      'media_handle_policy':
          'captured_media|media_handle|module_instance|true|'
          'cryptographically_secure_random|128|128|true|'
          'true|false|false|300|media_invalid',
    };
    final handleSignatures = <String, String>{};
    for (final handle in handles ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(handle, const {
        'id',
        'description',
        'resourceId',
        'fieldId',
        'scope',
        'moduleInstanceScoped',
        'generationStrategy',
        'minimumEntropyBits',
        'maxLength',
        'nonReusable',
        'strictRegistryLookup',
        'pathDerived',
        'pathConcatenationAllowed',
        'tombstoneTtlSeconds',
        'expiredFailureId',
      }, '$path handle policy');
      final id = handle['id'];
      if (id is String) {
        if (handleSignatures.containsKey(id)) {
          errors.add('$path handles 包含重复 id：$id');
        }
        handleSignatures[id] =
            '${handle['resourceId']}|${handle['fieldId']}|${handle['scope']}|'
            '${handle['moduleInstanceScoped']}|${handle['generationStrategy']}|'
            '${handle['minimumEntropyBits']}|'
            '${handle['maxLength']}|${handle['nonReusable']}|'
            '${handle['strictRegistryLookup']}|${handle['pathDerived']}|'
            '${handle['pathConcatenationAllowed']}|'
            '${handle['tombstoneTtlSeconds']}|${handle['expiredFailureId']}';
      }
      final fieldId = handle['fieldId'];
      final fieldSignature = fieldId is String ? fields[fieldId] : null;
      if (fieldSignature == null ||
          !fieldSignature.startsWith('opaque_id|true|false|') ||
          !fieldSignature.contains('|opaque_handle|')) {
        errors.add('$path handle policy 必须绑定 opaque_handle field');
      }
      if (!failures.contains(handle['expiredFailureId'])) {
        errors.add('$path handle policy 引用了未知 expiredFailureId');
      }
      _validateCapabilityDescription(handle, '$path handle policy');
    }
    for (final expected in expectedHandles.entries) {
      if (handleSignatures[expected.key] != expected.value) {
        errors.add(
          '$path handle ${expected.key} 安全属性与 V1-preserved semantics 不一致',
        );
      }
    }
    if (!_sameStringSet(
      handleSignatures.keys.toSet(),
      expectedHandles.keys.toSet(),
    )) {
      errors.add('$path 的 handle policies 必须精确匹配 V1-preserved semantics');
    }

    final leases = _capabilityObjectList(
      policy['leases'],
      '$path resourcePolicy.leases',
    );
    if (leases == null || leases.length != 1) {
      errors.add('$path 必须声明一个 confirmed_media_lease');
    } else {
      final lease = leases.single;
      _validateCapabilityExactKeys(lease, const {
        'id',
        'description',
        'resourceId',
        'stateMachineId',
        'activeStateId',
        'ttlSeconds',
        'newReadsAfterEnd',
        'activeReadGraceSeconds',
        'graceExpiryAction',
        'deleteAfterGrace',
      }, '$path lease policy');
      const expectedLease =
          'confirmed_media_lease|captured_media|media|leased|86400|deny|60|'
          'force_revoke_close_delete|true';
      final actualLease =
          '${lease['id']}|${lease['resourceId']}|${lease['stateMachineId']}|'
          '${lease['activeStateId']}|${lease['ttlSeconds']}|'
          '${lease['newReadsAfterEnd']}|${lease['activeReadGraceSeconds']}|'
          '${lease['graceExpiryAction']}|${lease['deleteAfterGrace']}';
      if (actualLease != expectedLease) {
        errors.add('$path confirmed_media_lease 必须使用 86400s TTL 与 60s grace');
      }
      _validateCapabilityDescription(lease, '$path lease policy');
    }

    final privacyIds = _capabilitySemanticEntryIds(
      policy['privacy'],
      '$path resourcePolicy.privacy',
    );
    _validateCapabilityAttachments(
      policy['attachments'],
      fields,
      operations,
      lifecycleRules,
      resourceIds,
      path,
    );
    _validateCapabilityRenderSurfaces(
      policy['renderSurfaces'],
      fields,
      resourceIds,
      operations,
      stateIds,
      failures,
      policy['attachments'],
      policy['ownershipPhases'],
      path,
    );
    _validateCapabilityBoundedCopies(
      policy['boundedCopies'],
      fields,
      operations,
      lifecycleRules,
      failures,
      resourceIds,
      privacyIds ?? const <String>{},
      path,
    );
    _validateCapabilityStreamingCopies(
      policy['streamingCopies'],
      fields,
      operations,
      lifecycleRules,
      failures,
      resourceIds,
      privacyIds ?? const <String>{},
      path,
    );

    final cleanup = _capabilityObjectList(
      policy['cleanup'],
      '$path resourcePolicy.cleanup',
    );
    final cleanupSignatures = <String, String>{};
    for (final rule in cleanup ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(rule, const {
        'id',
        'description',
        'triggerKind',
        'triggerId',
        'resourceId',
        'action',
        'order',
      }, '$path cleanup rule');
      final id = rule['id'];
      if (id is String) {
        if (cleanupSignatures.containsKey(id)) {
          errors.add('$path cleanup 包含重复 id：$id');
        }
        cleanupSignatures[id] =
            '${rule['triggerKind']}|${rule['triggerId']}|'
            '${rule['resourceId']}|${rule['action']}|${rule['order']}';
      }
      if (rule['triggerKind'] == 'operation' &&
          !operations.contains(rule['triggerId'])) {
        errors.add('$path cleanup 引用了未知 operation trigger');
      }
      if (rule['triggerKind'] == 'lifecycle' &&
          !lifecycleRules.contains(rule['triggerId'])) {
        errors.add('$path cleanup 引用了未知 lifecycle trigger');
      }
      if (!resourceIds.contains(rule['resourceId'])) {
        errors.add('$path cleanup 引用了未知 resource');
      }
      _validateCapabilityDescription(rule, '$path cleanup rule');
    }
    const expectedCleanup = {
      'retake_cleanup':
          'operation|retake|captured_media|invalidate_delete|before_state_transition',
      'cancel_cleanup':
          'lifecycle|session_cancelled|captured_media|invalidate_delete|before_state_transition',
      'failure_cleanup':
          'lifecycle|capability_failure|captured_media|invalidate_delete|before_terminal_transition',
      'preview_timeout_cleanup':
          'lifecycle|preview_timed_out|captured_media|invalidate_delete|before_terminal_transition',
      'release_cleanup':
          'operation|release_media|captured_media|deny_new_reads_start_grace|before_state_transition',
      'lease_expiry_cleanup':
          'lifecycle|lease_expired|captured_media|deny_new_reads_start_grace|before_state_transition',
      'release_read_grace_cleanup':
          'lifecycle|release_read_grace_elapsed|captured_media|'
          'force_revoke_close_delete|before_terminal_transition',
      'expiry_read_grace_cleanup':
          'lifecycle|expiry_read_grace_elapsed|captured_media|'
          'force_revoke_close_delete|before_terminal_transition',
      'restart_cleanup':
          'lifecycle|app_restarted|captured_media|invalidate_delete|'
          'before_registry_invalidation',
      'live_preview_explicit_detach':
          'operation|detach_live_preview|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_result_commit',
      'live_preview_photo_revoke':
          'operation|take_photo|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_state_transition',
      'live_preview_stop_revoke':
          'operation|stop_recording|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_state_transition',
      'live_preview_duration_revoke':
          'lifecycle|video_duration_reached|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_state_transition',
      'live_preview_rotation_revoke':
          'lifecycle|display_rotation_changed|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_owner_replacement',
      'live_preview_background_revoke':
          'lifecycle|app_backgrounded|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_state_cleanup',
      'live_preview_owner_destroy_revoke':
          'lifecycle|preview_owner_destroyed|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_owner_destroy',
      'live_preview_terminal_revoke':
          'lifecycle|session_terminal|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_terminal_transition',
      'live_preview_core_close_revoke':
          'lifecycle|core_closed|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_core_resource_close',
      'live_preview_restart_revoke':
          'lifecycle|app_restarted|live_preview_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_registry_invalidation',
      'unconfirmed_preview_explicit_detach':
          'operation|detach_unconfirmed_preview_render|'
          'unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_result_commit',
      'unconfirmed_preview_retake_revoke':
          'operation|retake|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_media_cleanup',
      'unconfirmed_preview_confirm_revoke':
          'operation|confirm|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_media_transfer',
      'unconfirmed_preview_cancel_revoke':
          'lifecycle|session_cancelled|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_media_cleanup',
      'unconfirmed_preview_failure_revoke':
          'lifecycle|capability_failure|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_media_cleanup',
      'unconfirmed_preview_timeout_revoke':
          'lifecycle|preview_timed_out|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_media_cleanup',
      'unconfirmed_preview_rotation_revoke':
          'lifecycle|display_rotation_changed|'
          'unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_owner_replacement',
      'unconfirmed_preview_background_revoke':
          'lifecycle|app_backgrounded|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_state_cleanup',
      'unconfirmed_preview_owner_destroy_revoke':
          'lifecycle|preview_owner_destroyed|'
          'unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_owner_destroy',
      'unconfirmed_preview_core_close_revoke':
          'lifecycle|core_closed|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_core_resource_close',
      'unconfirmed_preview_restart_revoke':
          'lifecycle|app_restarted|unconfirmed_preview_render_attachment|'
          'invalidate_generation_stop_callbacks_detach|before_registry_invalidation',
      'thumbnail_release_cleanup':
          'operation|release_media|thumbnail_generation_job|'
          'run_thumbnail_generation_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'thumbnail_expiry_cleanup':
          'lifecycle|lease_expired|thumbnail_generation_job|'
          'run_thumbnail_generation_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'thumbnail_cancel_cleanup':
          'lifecycle|thumbnail_read_cancelled|thumbnail_generation_job|'
          'run_thumbnail_generation_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'thumbnail_failure_cleanup':
          'lifecycle|thumbnail_generation_aborted|thumbnail_generation_job|'
          'run_thumbnail_generation_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'thumbnail_restart_cleanup':
          'lifecycle|app_restarted|thumbnail_generation_job|'
          'run_thumbnail_generation_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'thumbnail_success_finalization':
          'lifecycle|thumbnail_result_committed|thumbnail_generation_job|'
          'run_thumbnail_success_finalization_sequence|'
          'after_atomic_transfer_before_result_delivery',
      'media_export_release_cleanup':
          'operation|release_media|media_export_job|'
          'run_media_export_failure_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'media_export_expiry_cleanup':
          'lifecycle|lease_expired|media_export_job|'
          'run_media_export_failure_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'media_export_cancel_cleanup':
          'lifecycle|media_export_cancel_requested|media_export_job|'
          'run_media_export_failure_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'media_export_timeout_cleanup':
          'lifecycle|media_export_deadline_elapsed|media_export_job|'
          'run_media_export_failure_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'media_export_failure_cleanup':
          'lifecycle|media_export_aborted|media_export_job|'
          'run_media_export_failure_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'media_export_core_close_cleanup':
          'lifecycle|core_closed|media_export_job|'
          'run_media_export_failure_cleanup_sequence|'
          'after_atomic_winner_before_outcome_delivery',
      'media_export_success_finalization':
          'lifecycle|media_export_committed|media_export_job|'
          'run_media_export_success_finalization_sequence|'
          'after_atomic_winner_before_result_delivery',
    };
    if (!_sameStringSet(
      cleanupSignatures.keys.toSet(),
      expectedCleanup.keys.toSet(),
    )) {
      errors.add('$path 的 cleanup rules 不完整');
    }
    for (final expected in expectedCleanup.entries) {
      if (cleanupSignatures[expected.key] != expected.value) {
        errors.add('$path cleanup ${expected.key} 与 V2 Profile 不一致');
      }
    }

    const expectedPrivacy = {
      'strip_location_metadata',
      'minimize_embedded_metadata',
      'redact_logs',
      'no_arbitrary_paths',
      'strip_thumbnail_exif',
      'strip_thumbnail_source_filename',
      'sanitize_thumbnail_encoding',
      'strip_non_display_thumbnail_metadata',
      'no_sensitive_thumbnail_cache_key',
      'no_thumbnail_source_export',
      'native_render_surface_not_data_payload',
      'no_render_surface_cross_runtime_projection',
      'render_internals_module_private',
      'render_surface_structured_logs_only',
      'media_export_sink_native_only',
      'media_export_no_storage_identity',
      'media_export_redacted_diagnostics',
    };
    if (privacyIds != null && !_sameStringSet(privacyIds, expectedPrivacy)) {
      errors.add('$path 的 resource privacy 策略不完整');
    }
  }

  void _validateCapabilityAttachments(
    Object? value,
    Map<String, String> fields,
    Set<String> operations,
    Set<String> lifecycleRules,
    Set<String> resourceIds,
    String path,
  ) {
    final attachments = _capabilityObjectList(
      value,
      '$path resourcePolicy.attachments',
    );
    final signatures = <String, String>{};
    final seenAttachmentPolicyIds = <String>{};
    const expected = <String, String>{
      'live_preview_attachment_policy':
          'live_preview_attachment|attach_live_preview,detach_live_preview|'
          'session|ready,recording|'
          'app_backgrounded,app_restarted,core_closed,'
          'display_rotation_changed,preview_owner_destroyed,session_terminal,'
          'stop_recording,'
          'take_photo,video_duration_reached|'
          'invalidate_generation_stop_callbacks_detach_before_state_cleanup',
      'unconfirmed_preview_render_attachment_policy':
          'unconfirmed_preview_render_attachment|'
          'attach_unconfirmed_preview_render,detach_unconfirmed_preview_render|'
          'media|preview|app_backgrounded,app_restarted,capability_failure,'
          'confirm,core_closed,display_rotation_changed,preview_owner_destroyed,'
          'preview_timed_out,retake,session_cancelled|'
          'invalidate_generation_stop_callbacks_detach_before_media_cleanup_or_transfer',
    };
    for (final attachment in attachments ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(attachment, const {
        'id',
        'description',
        'resourceId',
        'operationIds',
        'targetFieldId',
        'ownerGenerationFieldId',
        'stateMachineId',
        'allowedStateIds',
        'consumerScope',
        'maxConcurrentAttachments',
        'generationHighWatermark',
        'generationLinearization',
        'highWatermarkRetention',
        'retiredGenerationPolicy',
        'freshGenerationPolicy',
        'sameGenerationSameTarget',
        'sameGenerationDifferentTarget',
        'sameGenerationDifferentTargetFailureId',
        'staleAttachFailureId',
        'staleAttachEffect',
        'staleDetachBehavior',
        'mismatchedDetachBehavior',
        'detachMatchPolicy',
        'currentBindingIdentity',
        'replacementSequenceIds',
        'revokeTriggerIds',
        'callbackThread',
        'callbackValidation',
        'cleanupOrder',
        'resumePolicy',
        'forbiddenRepresentationIds',
      }, '$path attachment policy');
      final id = attachment['id'];
      if (id is! String) {
        errors.add('$path attachment policy 必须声明字符串 id');
        continue;
      }
      if (!seenAttachmentPolicyIds.add(id)) {
        errors.add('$path attachment policy 包含重复 id：$id');
        continue;
      }
      final operationIds = _capabilityStringSet(
        attachment['operationIds'],
        '$path attachment.operationIds',
      );
      final allowedStates = _capabilityStringSet(
        attachment['allowedStateIds'],
        '$path attachment.allowedStateIds',
      );
      final revokeTriggers = _capabilityStringSet(
        attachment['revokeTriggerIds'],
        '$path attachment.revokeTriggerIds',
      );
      final forbidden = _capabilityStringSet(
        attachment['forbiddenRepresentationIds'],
        '$path attachment.forbiddenRepresentationIds',
      );
      const replacementSequence = <String>[
        'compare_and_advance_high_watermark',
        'revoke_old_callbacks',
        'detach_old_target',
        'attach_new_target',
        'commit_result',
      ];
      final replacement = attachment['replacementSequenceIds'];
      final replacementMatches =
          replacement is List<Object?> &&
          replacement.length == replacementSequence.length &&
          List.generate(
            replacement.length,
            (index) => index,
          ).every((index) => replacement[index] == replacementSequence[index]);
      for (final operationId in operationIds ?? const <String>{}) {
        if (!operations.contains(operationId)) {
          errors.add('$path attachment 引用了未知 operation：$operationId');
        }
      }
      for (final trigger in revokeTriggers ?? const <String>{}) {
        if (!operations.contains(trigger) &&
            !lifecycleRules.contains(trigger)) {
          errors.add('$path attachment 引用了未知 revoke trigger：$trigger');
        }
      }
      if (!resourceIds.contains(attachment['resourceId']) ||
          attachment['targetFieldId'] != 'render_target_adapter' ||
          attachment['ownerGenerationFieldId'] != 'owner_generation' ||
          !(fields['render_target_adapter'] ?? '').startsWith(
            'callback_resource|true|false|',
          ) ||
          !(fields['owner_generation'] ?? '').startsWith(
            'integer|true|false|',
          )) {
        errors.add(
          '$path attachment 必须绑定受约束的 RenderTarget Adapter 与 owner generation',
        );
      }
      const expectedForbidden = {
        'media_bytes',
        'path',
        'uri',
        'file_descriptor',
        'capture_session_object',
        'ui_object',
        'platform_sdk_type',
      };
      if (attachment['consumerScope'] != 'native_consumer_only' ||
          attachment['maxConcurrentAttachments'] != 1 ||
          attachment['generationHighWatermark'] !=
              'per_scope_monotonic_high_watermark' ||
          attachment['generationLinearization'] !=
              'compare_and_advance_before_binding_mutation' ||
          attachment['highWatermarkRetention'] !=
              'until_scope_terminal_or_registry_invalidation' ||
          attachment['retiredGenerationPolicy'] !=
              'never_accept_below_high_watermark_or_detached_at_high_watermark' ||
          attachment['freshGenerationPolicy'] !=
              'strictly_greater_than_high_watermark' ||
          attachment['sameGenerationSameTarget'] !=
              'idempotent_only_while_current_binding_matches' ||
          attachment['sameGenerationDifferentTarget'] !=
              'reject_without_binding_change' ||
          attachment['sameGenerationDifferentTargetFailureId'] !=
              'attachment_target_conflict' ||
          attachment['staleAttachFailureId'] !=
              'attachment_generation_retired' ||
          attachment['staleAttachEffect'] !=
              'reject_without_revoke_detach_callback_or_binding_change' ||
          attachment['staleDetachBehavior'] !=
              'no_op_preserve_current_binding' ||
          attachment['mismatchedDetachBehavior'] !=
              'no_op_preserve_current_binding' ||
          attachment['detachMatchPolicy'] !=
              'require_owner_generation_and_adapter_instance_identity' ||
          attachment['currentBindingIdentity'] !=
              'owner_generation_and_adapter_instance_identity' ||
          !replacementMatches ||
          attachment['callbackThread'] != 'owner_ui_thread' ||
          attachment['callbackValidation'] !=
              'active_scope_and_owner_generation_required' ||
          attachment['resumePolicy'] !=
              'explicit_attach_with_new_owner_generation' ||
          forbidden == null ||
          !_sameStringSet(forbidden, expectedForbidden)) {
        errors.add(
          '$path attachment 缺少 native-only、generation high-watermark、generation+adapter detach match、有序 replacement、stale no-op、thread 或禁止暴露语义',
        );
      }
      if (operationIds != null &&
          allowedStates != null &&
          revokeTriggers != null) {
        final sortedOperations = operationIds.toList()..sort();
        final sortedStates = allowedStates.toList()..sort();
        final sortedTriggers = revokeTriggers.toList()..sort();
        signatures[id] =
            '${attachment['resourceId']}|${sortedOperations.join(',')}|'
            '${attachment['stateMachineId']}|${sortedStates.join(',')}|'
            '${sortedTriggers.join(',')}|${attachment['cleanupOrder']}';
      }
      _validateCapabilityDescription(attachment, '$path attachment policy');
    }
    if (!_sameStringSet(signatures.keys.toSet(), expected.keys.toSet()) ||
        expected.entries.any((entry) => signatures[entry.key] != entry.value)) {
      errors.add('$path 的 Render attachment policies 与 V2 Profile 不一致');
    }
  }

  void _validateCapabilityRenderSurfaces(
    Object? value,
    Map<String, String> fields,
    Set<String> resourceIds,
    Set<String> operationIds,
    Set<String> stateIds,
    Set<String> failureIds,
    Object? attachmentValue,
    Object? ownershipPhaseValue,
    String path,
  ) {
    final surfaces = _capabilityObjectList(
      value,
      '$path resourcePolicy.renderSurfaces',
    );
    final attachments = _capabilityObjectList(
      attachmentValue,
      '$path resourcePolicy.attachments',
    );
    final attachmentIdCounts = <String, int>{};
    for (final attachment in attachments ?? const <Map<String, Object?>>[]) {
      final attachmentId = attachment['id'];
      if (attachmentId is String) {
        attachmentIdCounts.update(
          attachmentId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final attachmentIds = attachmentIdCounts.keys.toSet();
    final ownershipPhases = _capabilityObjectList(
      ownershipPhaseValue,
      '$path resourcePolicy.ownershipPhases',
    );
    final ownershipPhaseIds =
        ownershipPhases
            ?.map((phase) => phase['id'])
            .whereType<String>()
            .toSet() ??
        <String>{};
    const installSequence = <String>[
      'validate_active_scope',
      'validate_target_identity',
      'validate_owner_generation',
      'validate_lifecycle_gate',
      'connect_private_source_to_module_renderer',
      'mount_renderer_into_surface',
      'commit_binding',
    ];
    const revokeSequence = <String>[
      'invalidate_callback_gate',
      'disconnect_source_session_or_player',
      'remove_module_renderer_or_content',
      'clear_module_renderer_or_content',
      'detach_surface',
      'cleanup_binding_registry_and_state',
    ];
    const replacementSequence = <String>[
      'compare_and_advance_high_watermark',
      'invalidate_callback_gate',
      'disconnect_source_session_or_player',
      'remove_module_renderer_or_content',
      'clear_module_renderer_or_content',
      'detach_surface',
      'cleanup_old_binding_state_preserve_generation_high_watermark',
      'validate_active_scope',
      'validate_target_identity',
      'validate_owner_generation',
      'validate_lifecycle_gate',
      'connect_private_source_to_module_renderer',
      'mount_renderer_into_surface',
      'commit_binding',
    ];
    const forbiddenRepresentations = {
      'arbitrary_ui_object',
      'platform_sdk_source',
      'capture_session_object',
      'preview_layer',
      'player_layer',
      'surface_provider',
      'sample_buffer',
      'pixel_frame',
      'media_bytes',
      'path',
      'uri',
      'file_descriptor',
      'untyped_map',
      'any_object',
      'opaque_token',
      'identity_only_marker',
      'empty_factory',
      'cross_runtime_encoding',
    };
    const expectedSurfaceSignatures = {
      'live_platform_render_surface_policy':
          'live_platform_render_surface|live_preview_attachment_policy|'
          'live_preview|live_camera_source',
      'unconfirmed_platform_render_surface_policy':
          'unconfirmed_platform_render_surface|'
          'unconfirmed_preview_render_attachment_policy|'
          'unconfirmed_preview|unconfirmed_photo_source,unconfirmed_video_source',
    };
    const expectedDiagnosticPolicyIds = {
      'live_platform_render_surface_policy':
          'live_render_surface_diagnostic_policy',
      'unconfirmed_platform_render_surface_policy':
          'unconfirmed_render_surface_diagnostic_policy',
    };
    const allowedDiagnosticRecordKinds = {
      'attachment_rejected',
      'mount_failed',
      'revoke_completed',
      'stale_mutation_dropped',
    };
    const allowedDiagnosticFields = {
      'record_kind',
      'operation_id',
      'lifecycle_state',
      'redacted_status',
      'stable_failure_id',
    };
    const allowedDiagnosticStatuses = {
      'success',
      'rejected',
      'revoked',
      'dropped',
      'redacted_failure',
    };
    const forbiddenDiagnosticData = {
      'surface_instance',
      'surface_description',
      'target_instance',
      'target_description',
      'owner_generation',
      'source_instance',
      'renderer_instance',
      'binding_instance',
      'mount_endpoint_instance',
      'platform_sdk_object',
      'platform_sdk_description',
      'path',
      'raw_exception',
      'media_bytes',
      'opaque_token',
    };
    const expectedFactorySignatures = {
      'live_platform_render_surface_policy':
          'native_module|owner_generation:field:owner_generation:true,'
          'surface_lifecycle_owner:ownership_phase:'
          'live_render_surface_owner_scope:true|surface_instance:'
          'live_platform_render_surface:platform_closed_target_conformance:'
          'false:true:concrete_instance_identity|'
          'reject_before_attachment_mutation',
      'unconfirmed_platform_render_surface_policy':
          'native_module|owner_generation:field:owner_generation:true,'
          'surface_lifecycle_owner:ownership_phase:'
          'unconfirmed_render_surface_owner_scope:true|surface_instance:'
          'unconfirmed_platform_render_surface:'
          'platform_closed_target_conformance:false:true:'
          'concrete_instance_identity|reject_before_attachment_mutation',
    };
    const expectedPlatformSignatures = {
      'live_platform_render_surface_policy|android':
          'media_capture_android|MediaCaptureRenderView|'
          'MediaCaptureRenderSurfaceOwner|MediaCaptureRenderView|'
          'android_live_render_target_conformance|'
          'android_preview_view,android_surface_provider|'
          'android_live_source,android_preview_renderer,android_render_binding',
      'live_platform_render_surface_policy|ios':
          'MediaCaptureAppleRendering|MediaCaptureRenderView|'
          'MediaCaptureRenderSurfaceOwner|MediaCaptureRenderView|'
          'ios_live_render_target_conformance|'
          'ios_capture_video_preview_layer,ios_surface_backing_target|'
          'ios_live_source,ios_preview_renderer,ios_render_binding',
      'unconfirmed_platform_render_surface_policy|android':
          'media_capture_android|MediaCaptureRenderView|'
          'MediaCaptureRenderSurfaceOwner|MediaCaptureRenderView|'
          'android_unconfirmed_render_target_conformance|'
          'android_photo_content_target,android_video_player_surface|'
          'android_file_source,android_photo_renderer,android_render_binding,'
          'android_video_player',
      'unconfirmed_platform_render_surface_policy|ios':
          'MediaCaptureAppleRendering|MediaCaptureRenderView|'
          'MediaCaptureRenderSurfaceOwner|MediaCaptureRenderView|'
          'ios_unconfirmed_render_target_conformance|'
          'ios_photo_content_target,ios_player_layer|'
          'ios_file_source,ios_photo_renderer,ios_render_binding,'
          'ios_video_player',
    };
    const expectedConformanceSignatures = {
      'live_platform_render_surface_policy|android':
          'android_live_render_target_conformance|true|'
          'MediaCaptureRenderView|android_preview_view,'
          'android_surface_provider|MediaCaptureRenderMountEndpoint|'
          'native_module|reject',
      'live_platform_render_surface_policy|ios':
          'ios_live_render_target_conformance|true|MediaCaptureRenderView|'
          'ios_capture_video_preview_layer,ios_surface_backing_target|'
          'MediaCaptureRenderMountEndpoint|native_module|reject',
      'unconfirmed_platform_render_surface_policy|android':
          'android_unconfirmed_render_target_conformance|true|'
          'MediaCaptureRenderView|android_photo_content_target,'
          'android_video_player_surface|MediaCaptureRenderMountEndpoint|'
          'native_module|reject',
      'unconfirmed_platform_render_surface_policy|ios':
          'ios_unconfirmed_render_target_conformance|true|'
          'MediaCaptureRenderView|ios_photo_content_target,ios_player_layer|'
          'MediaCaptureRenderMountEndpoint|native_module|reject',
    };
    const expectedMountBindingSignatures = {
      'live_platform_render_surface_policy|android':
          'MediaCaptureRenderMountEndpoint|module_internal|native_module|'
          'native_module|native_module|native_module|native_module|'
          'live_platform_render_surface|live_preview_attachment_policy|'
          'surface_instance|android_live_render_target_conformance|'
          'live_render_surface_owner_scope|owner_generation|'
          'validate_gate_before_endpoint_mutation',
      'live_platform_render_surface_policy|ios':
          'MediaCaptureRenderMountEndpoint|module_internal|native_module|'
          'native_module|native_module|native_module|native_module|'
          'live_platform_render_surface|live_preview_attachment_policy|'
          'surface_instance|ios_live_render_target_conformance|'
          'live_render_surface_owner_scope|owner_generation|'
          'validate_gate_before_endpoint_mutation',
      'unconfirmed_platform_render_surface_policy|android':
          'MediaCaptureRenderMountEndpoint|module_internal|native_module|'
          'native_module|native_module|native_module|native_module|'
          'unconfirmed_platform_render_surface|'
          'unconfirmed_preview_render_attachment_policy|surface_instance|'
          'android_unconfirmed_render_target_conformance|'
          'unconfirmed_render_surface_owner_scope|owner_generation|'
          'validate_gate_before_endpoint_mutation',
      'unconfirmed_platform_render_surface_policy|ios':
          'MediaCaptureRenderMountEndpoint|module_internal|native_module|'
          'native_module|native_module|native_module|native_module|'
          'unconfirmed_platform_render_surface|'
          'unconfirmed_preview_render_attachment_policy|surface_instance|'
          'ios_unconfirmed_render_target_conformance|'
          'unconfirmed_render_surface_owner_scope|owner_generation|'
          'validate_gate_before_endpoint_mutation',
    };
    final surfaceSignatures = <String, String>{};
    final factorySignatures = <String, String>{};
    final diagnosticPolicyIds = <String, String>{};
    final platformSignatures = <String, String>{};
    final conformanceSignatures = <String, String>{};
    final mountBindingSignatures = <String, String>{};
    final seenSurfacePolicyIds = <String>{};
    final seenAttachmentPolicyReferences = <String>{};

    bool matchesSequence(Object? actual, List<String> expected) =>
        actual is List<Object?> &&
        actual.length == expected.length &&
        List.generate(
          expected.length,
          (index) => index,
        ).every((index) => actual[index] == expected[index]);

    for (final surface in surfaces ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(surface, const {
        'id',
        'description',
        'resourceId',
        'attachmentPolicyId',
        'targetFieldId',
        'ownerGenerationFieldId',
        'consumerScope',
        'surfaceKind',
        'actualMountRequired',
        'actualMountCapability',
        'factoryPolicy',
        'identityPolicy',
        'surfaceOwner',
        'sourceOwner',
        'rendererOwner',
        'bindingOwner',
        'cleanupOwner',
        'ownerAccessPolicy',
        'factoryContract',
        'diagnosticPolicy',
        'platformImplementations',
        'mountSourceKindIds',
        'installSequenceIds',
        'mutationGate',
        'passiveFramePolicy',
        'revokeSequenceIds',
        'replacementSequenceIds',
        'cleanupExecution',
        'staleMutationPolicy',
        'replacementPolicy',
        'crossRuntimeProjection',
        'forbiddenRepresentationIds',
      }, '$path render surface policy');
      final id = surface['id'];
      if (id is! String) {
        errors.add('$path render surface policy 必须声明字符串 id');
        continue;
      }
      if (!seenSurfacePolicyIds.add(id)) {
        errors.add('$path render surface policy 包含重复 id：$id');
        continue;
      }
      final attachmentPolicyId = surface['attachmentPolicyId'];
      if (attachmentPolicyId is! String ||
          attachmentIdCounts[attachmentPolicyId] != 1) {
        errors.add(
          '$path render surface attachmentPolicyId 必须唯一引用一个 attachment policy',
        );
      } else if (!seenAttachmentPolicyReferences.add(attachmentPolicyId)) {
        errors.add(
          '$path 多个 render surface policy 不得引用同一 attachment policy：$attachmentPolicyId',
        );
      }
      final sourceKinds = _capabilityStringSet(
        surface['mountSourceKindIds'],
        '$path render surface mountSourceKindIds',
      );
      final forbidden = _capabilityStringSet(
        surface['forbiddenRepresentationIds'],
        '$path render surface forbiddenRepresentationIds',
      );
      final factory = _capabilityObject(
        surface['factoryContract'],
        '$path render surface factoryContract',
      );
      String? factoryOutputRoleId;
      String? factoryLifecyclePhaseId;
      if (factory != null) {
        _validateCapabilityExactKeys(factory, const {
          'ownerRoleId',
          'inputBindings',
          'output',
          'emptyOutputPolicy',
        }, '$path render surface factoryContract');
        final inputBindings = _capabilityObjectList(
          factory['inputBindings'],
          '$path render surface factoryContract.inputBindings',
        );
        final inputSignatures = <String>[];
        for (final input in inputBindings ?? const <Map<String, Object?>>[]) {
          _validateCapabilityExactKeys(input, const {
            'roleId',
            'bindingKind',
            'bindingId',
            'required',
          }, '$path render surface factory input');
          final roleId = input['roleId'];
          final bindingKind = input['bindingKind'];
          final bindingId = input['bindingId'];
          if (roleId is String &&
              bindingKind is String &&
              bindingId is String) {
            inputSignatures.add(
              '$roleId:$bindingKind:$bindingId:${input['required']}',
            );
            if (roleId == 'surface_lifecycle_owner') {
              factoryLifecyclePhaseId = bindingId;
            }
          }
          final bindingExists = switch (bindingKind) {
            'field' => bindingId is String && fields.containsKey(bindingId),
            'resource' =>
              bindingId is String && resourceIds.contains(bindingId),
            'ownership_phase' =>
              bindingId is String && ownershipPhaseIds.contains(bindingId),
            _ => false,
          };
          if (!bindingExists || input['required'] != true) {
            errors.add(
              '$path render surface factory input 必须绑定已声明且必需的 field/resource/ownership phase',
            );
          }
        }
        inputSignatures.sort();
        final output = _capabilityObject(
          factory['output'],
          '$path render surface factoryContract.output',
        );
        if (output != null) {
          _validateCapabilityExactKeys(output, const {
            'roleId',
            'resourceId',
            'platformConformanceRoleId',
            'nullable',
            'freshInstancePerInvocation',
            'identityPolicy',
          }, '$path render surface factory output');
          factoryOutputRoleId = output['roleId'] is String
              ? output['roleId'] as String
              : null;
          if (!resourceIds.contains(output['resourceId']) ||
              output['resourceId'] != surface['resourceId'] ||
              output['nullable'] != false ||
              output['freshInstancePerInvocation'] != true) {
            errors.add(
              '$path render surface factory 必须输出 non-null fresh concrete surface resource',
            );
          }
          factorySignatures[id] =
              '${factory['ownerRoleId']}|${inputSignatures.join(',')}|'
              '${output['roleId']}:${output['resourceId']}:'
              '${output['platformConformanceRoleId']}:'
              '${output['nullable']}:${output['freshInstancePerInvocation']}:'
              '${output['identityPolicy']}|${factory['emptyOutputPolicy']}';
        }
      }
      final diagnosticPolicy = _capabilityObject(
        surface['diagnosticPolicy'],
        '$path render surface diagnosticPolicy',
      );
      if (diagnosticPolicy != null) {
        _validateCapabilityExactKeys(diagnosticPolicy, const {
          'id',
          'allowedRecordKindIds',
          'allowedFieldIds',
          'allowedStatusIds',
          'fieldValueSources',
          'valuePolicy',
          'redactionPolicy',
          'forbiddenDataIds',
          'exceptionPolicy',
        }, '$path render surface diagnosticPolicy');
        final recordKinds = _capabilityStringSet(
          diagnosticPolicy['allowedRecordKindIds'],
          '$path render surface diagnostic allowedRecordKindIds',
        );
        final allowedFields = _capabilityStringSet(
          diagnosticPolicy['allowedFieldIds'],
          '$path render surface diagnostic allowedFieldIds',
        );
        final allowedStatuses = _capabilityStringSet(
          diagnosticPolicy['allowedStatusIds'],
          '$path render surface diagnostic allowedStatusIds',
        );
        final fieldValueSources = _capabilityObjectList(
          diagnosticPolicy['fieldValueSources'],
          '$path render surface diagnostic fieldValueSources',
        );
        final forbiddenData = _capabilityStringSet(
          diagnosticPolicy['forbiddenDataIds'],
          '$path render surface diagnostic forbiddenDataIds',
        );
        if (diagnosticPolicy['id'] is String) {
          diagnosticPolicyIds[id] = diagnosticPolicy['id'] as String;
        }
        final seenValueSourceFields = <String>{};
        var valueSourcesValid = fieldValueSources != null;
        for (final source
            in fieldValueSources ?? const <Map<String, Object?>>[]) {
          _validateCapabilityExactKeys(source, const {
            'fieldId',
            'sourceKind',
            'reference',
            'allowedValueIds',
          }, '$path render surface diagnostic field value source');
          final fieldId = source['fieldId'];
          if (fieldId is! String || !seenValueSourceFields.add(fieldId)) {
            valueSourcesValid = false;
            continue;
          }
          final reference = _capabilityObject(
            source['reference'],
            '$path render surface diagnostic value reference',
          );
          if (reference != null) {
            _validateCapabilityExactKeys(reference, const {
              'scopeId',
              'collectionId',
              'valueMemberId',
            }, '$path render surface diagnostic value reference');
          }
          final allowedValues = _capabilityStringSet(
            source['allowedValueIds'],
            '$path render surface diagnostic allowedValueIds',
          );
          String? expectedSourceKind;
          String? expectedScopeId;
          String? expectedCollectionId;
          String? expectedValueMemberId;
          Set<String>? expectedAllowedValues;
          switch (fieldId) {
            case 'record_kind':
              expectedSourceKind = 'declared_enum';
              expectedScopeId = 'diagnostic_policy';
              expectedCollectionId = 'allowed_record_kind_ids';
              expectedValueMemberId = 'item';
              expectedAllowedValues = recordKinds;
            case 'operation_id':
              expectedSourceKind = 'capability_collection';
              expectedScopeId = 'capability_contract';
              expectedCollectionId = 'operation';
              expectedValueMemberId = 'id';
              expectedAllowedValues = operationIds;
            case 'lifecycle_state':
              expectedSourceKind = 'capability_collection';
              expectedScopeId = 'capability_contract';
              expectedCollectionId = 'state_machines';
              expectedValueMemberId = 'state_id';
              expectedAllowedValues = stateIds;
            case 'redacted_status':
              expectedSourceKind = 'declared_enum';
              expectedScopeId = 'diagnostic_policy';
              expectedCollectionId = 'allowed_status_ids';
              expectedValueMemberId = 'item';
              expectedAllowedValues = allowedStatuses;
            case 'stable_failure_id':
              expectedSourceKind = 'capability_collection';
              expectedScopeId = 'capability_contract';
              expectedCollectionId = 'failure';
              expectedValueMemberId = 'id';
              expectedAllowedValues = failureIds;
          }
          if (expectedAllowedValues == null ||
              source['sourceKind'] != expectedSourceKind ||
              reference == null ||
              reference['scopeId'] != expectedScopeId ||
              reference['collectionId'] != expectedCollectionId ||
              reference['valueMemberId'] != expectedValueMemberId ||
              allowedValues == null ||
              !_sameStringSet(allowedValues, expectedAllowedValues)) {
            valueSourcesValid = false;
          }
        }
        if (!_sameStringSet(
              seenValueSourceFields,
              allowedFields ?? const <String>{},
            ) ||
            !valueSourcesValid) {
          errors.add(
            '$path render surface diagnostic value source 必须逐字段绑定实际 Capability operation/state/failure 或声明 enum',
          );
        }
        if (recordKinds == null ||
            !_sameStringSet(recordKinds, allowedDiagnosticRecordKinds) ||
            allowedFields == null ||
            !_sameStringSet(allowedFields, allowedDiagnosticFields) ||
            allowedStatuses == null ||
            !_sameStringSet(allowedStatuses, allowedDiagnosticStatuses) ||
            diagnosticPolicy['valuePolicy'] !=
                'stable_enum_or_redacted_status_only' ||
            diagnosticPolicy['redactionPolicy'] !=
                'redact_before_record_creation' ||
            forbiddenData == null ||
            !_sameStringSet(forbiddenData, forbiddenDiagnosticData) ||
            diagnosticPolicy['exceptionPolicy'] !=
                'stable_failure_id_only_no_raw_exception') {
          errors.add(
            '$path render surface 日志只能包含稳定 enum/脱敏 status，且必须禁止实例、generation、内部资源、SDK 描述、路径与 raw exception',
          );
        }
      }
      if (sourceKinds != null) {
        final sortedSources = sourceKinds.toList()..sort();
        surfaceSignatures[id] =
            '${surface['resourceId']}|${surface['attachmentPolicyId']}|'
            '${surface['surfaceKind']}|${sortedSources.join(',')}';
      }
      if (!resourceIds.contains(surface['resourceId']) ||
          !attachmentIds.contains(surface['attachmentPolicyId']) ||
          surface['targetFieldId'] != 'render_target_adapter' ||
          surface['ownerGenerationFieldId'] != 'owner_generation' ||
          !(fields['render_target_adapter'] ?? '').startsWith(
            'callback_resource|true|false|',
          ) ||
          !(fields['owner_generation'] ?? '').startsWith(
            'integer|true|false|',
          )) {
        errors.add(
          '$path render surface 必须绑定既有 V2 attachment、目标 identity 与 owner generation',
        );
      }
      if (surface['consumerScope'] != 'native_consumer_only' ||
          surface['actualMountRequired'] != true ||
          surface['actualMountCapability'] !=
              'module_accesses_private_source_and_backing_target' ||
          surface['factoryPolicy'] !=
              'module_defined_concrete_surface_factory_non_empty' ||
          surface['identityPolicy'] !=
              'concrete_surface_instance_identity_not_token' ||
          surface['surfaceOwner'] != 'native_consumer' ||
          surface['sourceOwner'] != 'native_module' ||
          surface['rendererOwner'] != 'native_module' ||
          surface['bindingOwner'] != 'native_module' ||
          surface['cleanupOwner'] != 'native_module' ||
          surface['ownerAccessPolicy'] !=
              'outer_surface_lifecycle_only_no_backing_source_renderer_or_binding_access' ||
          !matchesSequence(surface['installSequenceIds'], installSequence) ||
          surface['mutationGate'] !=
              'validate_active_scope_target_identity_owner_generation_and_lifecycle_before_install_mutation_observer_or_player_callback' ||
          surface['passiveFramePolicy'] !=
              'framework_pipeline_without_synthetic_per_hardware_frame_callback' ||
          !matchesSequence(surface['revokeSequenceIds'], revokeSequence) ||
          !matchesSequence(
            surface['replacementSequenceIds'],
            replacementSequence,
          ) ||
          surface['cleanupExecution'] != 'exactly_once_per_active_binding' ||
          surface['staleMutationPolicy'] != 'drop_without_surface_mutation' ||
          surface['replacementPolicy'] !=
              'fresh_surface_binding_for_strictly_new_owner_generation' ||
          surface['crossRuntimeProjection'] != 'forbidden_native_only' ||
          forbidden == null ||
          !_sameStringSet(forbidden, forbiddenRepresentations)) {
        errors.add(
          '$path render surface 缺少 actual mount、owner/module 隔离、lifecycle gate、有序 revoke、stale generation 或 Native-only 约束',
        );
      }

      final implementations = _capabilityObjectList(
        surface['platformImplementations'],
        '$path render surface platformImplementations',
      );
      final seenPlatforms = <String>{};
      for (final implementation
          in implementations ?? const <Map<String, Object?>>[]) {
        _validateCapabilityExactKeys(implementation, const {
          'platform',
          'moduleProduct',
          'publicSurfaceType',
          'factoryInputType',
          'factoryOutputType',
          'factoryOutputConformanceId',
          'concreteSurfaceRequired',
          'actualMountTargetIds',
          'moduleOwnedRendererIds',
          'ownerAccessibleIds',
          'sourceAccessPolicy',
          'rendererAccessPolicy',
          'targetConformance',
          'mountBinding',
        }, '$path platform render surface implementation');
        final platform = implementation['platform'];
        if (platform is! String) {
          errors.add('$path platform render surface 必须声明 platform');
          continue;
        }
        if (!seenPlatforms.add(platform)) {
          errors.add('$path render surface policy $id 包含重复 platform：$platform');
          continue;
        }
        final mountTargets = _capabilityStringSet(
          implementation['actualMountTargetIds'],
          '$path render surface actualMountTargetIds',
        );
        final renderers = _capabilityStringSet(
          implementation['moduleOwnedRendererIds'],
          '$path render surface moduleOwnedRendererIds',
        );
        final ownerAccessible = _capabilityStringSet(
          implementation['ownerAccessibleIds'],
          '$path render surface ownerAccessibleIds',
        );
        final conformance = _capabilityObject(
          implementation['targetConformance'],
          '$path render surface targetConformance',
        );
        Set<String>? acceptedTargets;
        if (conformance != null) {
          _validateCapabilityExactKeys(conformance, const {
            'id',
            'closed',
            'factoryOutputType',
            'acceptedTargetKindIds',
            'requiredMountEndpointType',
            'targetOwnerRoleId',
            'arbitraryTargetPolicy',
          }, '$path render target conformance');
          acceptedTargets = _capabilityStringSet(
            conformance['acceptedTargetKindIds'],
            '$path render target acceptedTargetKindIds',
          );
        }
        final mountBinding = _capabilityObject(
          implementation['mountBinding'],
          '$path render surface mountBinding',
        );
        if (mountBinding != null) {
          _validateCapabilityExactKeys(mountBinding, const {
            'endpointType',
            'endpointVisibility',
            'endpointOwnerRoleId',
            'backingTargetOwnerRoleId',
            'sourceOwnerRoleId',
            'rendererOwnerRoleId',
            'bindingOwnerRoleId',
            'surfaceResourceId',
            'attachmentPolicyId',
            'factoryOutputRoleId',
            'targetConformanceId',
            'lifecycleOwnershipPhaseId',
            'ownerGenerationFieldId',
            'mountMutationPolicy',
          }, '$path render mount binding');
        }
        if (mountTargets != null && renderers != null) {
          final sortedTargets = mountTargets.toList()..sort();
          final sortedRenderers = renderers.toList()..sort();
          platformSignatures['$id|$platform'] =
              '${implementation['moduleProduct']}|'
              '${implementation['publicSurfaceType']}|'
              '${implementation['factoryInputType']}|'
              '${implementation['factoryOutputType']}|'
              '${implementation['factoryOutputConformanceId']}|'
              '${sortedTargets.join(',')}|${sortedRenderers.join(',')}';
        }
        final key = '$id|$platform';
        if (conformance != null && acceptedTargets != null) {
          final sortedAcceptedTargets = acceptedTargets.toList()..sort();
          conformanceSignatures[key] =
              '${conformance['id']}|${conformance['closed']}|'
              '${conformance['factoryOutputType']}|'
              '${sortedAcceptedTargets.join(',')}|'
              '${conformance['requiredMountEndpointType']}|'
              '${conformance['targetOwnerRoleId']}|'
              '${conformance['arbitraryTargetPolicy']}';
        }
        if (mountBinding != null) {
          mountBindingSignatures[key] =
              '${mountBinding['endpointType']}|'
              '${mountBinding['endpointVisibility']}|'
              '${mountBinding['endpointOwnerRoleId']}|'
              '${mountBinding['backingTargetOwnerRoleId']}|'
              '${mountBinding['sourceOwnerRoleId']}|'
              '${mountBinding['rendererOwnerRoleId']}|'
              '${mountBinding['bindingOwnerRoleId']}|'
              '${mountBinding['surfaceResourceId']}|'
              '${mountBinding['attachmentPolicyId']}|'
              '${mountBinding['factoryOutputRoleId']}|'
              '${mountBinding['targetConformanceId']}|'
              '${mountBinding['lifecycleOwnershipPhaseId']}|'
              '${mountBinding['ownerGenerationFieldId']}|'
              '${mountBinding['mountMutationPolicy']}';
        }
        final targetRelationshipValid =
            conformance != null &&
            mountBinding != null &&
            acceptedTargets != null &&
            mountTargets != null &&
            _sameStringSet(acceptedTargets, mountTargets) &&
            conformance['closed'] == true &&
            conformance['factoryOutputType'] ==
                implementation['factoryOutputType'] &&
            implementation['factoryOutputType'] ==
                implementation['publicSurfaceType'] &&
            conformance['id'] == implementation['factoryOutputConformanceId'] &&
            conformance['requiredMountEndpointType'] ==
                mountBinding['endpointType'] &&
            conformance['targetOwnerRoleId'] == 'native_module' &&
            conformance['arbitraryTargetPolicy'] == 'reject' &&
            mountBinding['endpointVisibility'] == 'module_internal' &&
            mountBinding['endpointOwnerRoleId'] == 'native_module' &&
            mountBinding['backingTargetOwnerRoleId'] == 'native_module' &&
            mountBinding['sourceOwnerRoleId'] == surface['sourceOwner'] &&
            mountBinding['rendererOwnerRoleId'] == surface['rendererOwner'] &&
            mountBinding['bindingOwnerRoleId'] == surface['bindingOwner'] &&
            mountBinding['surfaceResourceId'] == surface['resourceId'] &&
            mountBinding['attachmentPolicyId'] ==
                surface['attachmentPolicyId'] &&
            mountBinding['factoryOutputRoleId'] == factoryOutputRoleId &&
            mountBinding['targetConformanceId'] == conformance['id'] &&
            mountBinding['lifecycleOwnershipPhaseId'] ==
                factoryLifecyclePhaseId &&
            ownershipPhaseIds.contains(
              mountBinding['lifecycleOwnershipPhaseId'],
            ) &&
            mountBinding['ownerGenerationFieldId'] ==
                surface['ownerGenerationFieldId'] &&
            mountBinding['mountMutationPolicy'] ==
                'validate_gate_before_endpoint_mutation';
        if (implementation['concreteSurfaceRequired'] != true ||
            ownerAccessible == null ||
            !_sameStringSet(ownerAccessible, const {
              'concrete_outer_surface',
              'surface_lifecycle',
            }) ||
            implementation['sourceAccessPolicy'] != 'module_internal_only' ||
            implementation['rendererAccessPolicy'] != 'module_internal_only' ||
            !targetRelationshipValid) {
          errors.add(
            '$path 平台 render surface 必须通过 closed conformance 与 module-only endpoint 绑定 factory output、target、ownership 和 lifecycle',
          );
        }
      }
      if (!_sameStringSet(seenPlatforms, const {'android', 'ios'})) {
        errors.add('$path 每类 render surface 必须同时实现 Android 与 iOS');
      }
      _validateCapabilityDescription(surface, '$path render surface policy');
    }
    if (!_sameStringSet(
          surfaceSignatures.keys.toSet(),
          expectedSurfaceSignatures.keys.toSet(),
        ) ||
        expectedSurfaceSignatures.entries.any(
          (entry) => surfaceSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path 必须精确声明 live/unconfirmed 两类 V3 render surface');
    }
    if (!_sameStringSet(
          platformSignatures.keys.toSet(),
          expectedPlatformSignatures.keys.toSet(),
        ) ||
        expectedPlatformSignatures.entries.any(
          (entry) => platformSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path V3 render surface 的双平台 concrete renderer 组成不完整');
    }
    if (!_sameStringSet(
          factorySignatures.keys.toSet(),
          expectedFactorySignatures.keys.toSet(),
        ) ||
        expectedFactorySignatures.entries.any(
          (entry) => factorySignatures[entry.key] != entry.value,
        )) {
      errors.add(
        '$path V3 render surface factory 必须有受约束 input 与 non-null fresh concrete output',
      );
    }
    if (!_sameStringSet(
          diagnosticPolicyIds.keys.toSet(),
          expectedDiagnosticPolicyIds.keys.toSet(),
        ) ||
        expectedDiagnosticPolicyIds.entries.any(
          (entry) => diagnosticPolicyIds[entry.key] != entry.value,
        )) {
      errors.add('$path 每类 V3 render surface 必须声明唯一结构化脱敏日志策略');
    }
    if (!_sameStringSet(
          conformanceSignatures.keys.toSet(),
          expectedConformanceSignatures.keys.toSet(),
        ) ||
        expectedConformanceSignatures.entries.any(
          (entry) => conformanceSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path V3 render target conformance 必须是双平台闭合集合');
    }
    if (!_sameStringSet(
          mountBindingSignatures.keys.toSet(),
          expectedMountBindingSignatures.keys.toSet(),
        ) ||
        expectedMountBindingSignatures.entries.any(
          (entry) => mountBindingSignatures[entry.key] != entry.value,
        )) {
      errors.add(
        '$path V3 mount binding 必须由 Module endpoint 绑定 backing target、factory output、ownership 与 lifecycle',
      );
    }
  }

  void _validateCapabilityBoundedCopies(
    Object? value,
    Map<String, String> fields,
    Set<String> operations,
    Set<String> lifecycleRules,
    Set<String> failures,
    Set<String> resourceIds,
    Set<String> privacyIds,
    String path,
  ) {
    final copies = _capabilityObjectList(
      value,
      '$path resourcePolicy.boundedCopies',
    );
    if (copies == null || copies.length != 1) {
      errors.add('$path 必须精确声明一个 confirmed_media_thumbnail_policy');
      return;
    }
    final copy = copies.single;
    _validateCapabilityExactKeys(copy, const {
      'id',
      'description',
      'operationId',
      'roleBindings',
      'preconditions',
      'bounds',
      'transforms',
      'ownershipTransfer',
      'execution',
      'raceArbitration',
      'privacyPolicyIds',
      'forbiddenRepresentationIds',
      'backendDetailsPolicy',
    }, '$path bounded copy policy');
    final roleItems = _capabilityObjectList(
      copy['roleBindings'],
      '$path boundedCopy.roleBindings',
    );
    final roles = <String, String>{};
    for (final role in roleItems ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(role, const {
        'roleId',
        'bindingKind',
        'bindingId',
      }, '$path boundedCopy role binding');
      final roleId = role['roleId'];
      final bindingKind = role['bindingKind'];
      final bindingId = role['bindingId'];
      if (roleId is! String ||
          bindingKind is! String ||
          bindingId is! String ||
          roles.containsKey(roleId)) {
        errors.add('$path boundedCopy role binding 必须唯一且完整');
        continue;
      }
      roles[roleId] = '$bindingKind|$bindingId';
      if (bindingKind == 'field' && !fields.containsKey(bindingId)) {
        errors.add('$path boundedCopy role 引用了未知 field：$bindingId');
      }
      if (bindingKind == 'resource' && !resourceIds.contains(bindingId)) {
        errors.add('$path boundedCopy role 引用了未知 resource：$bindingId');
      }
    }
    const expectedRoles = {
      'source_resource': 'resource|captured_media',
      'source_state': 'state_machine|media',
      'source_scope': 'field|media_handle',
      'module_scope': 'scope|module_instance',
      'in_flight_job': 'resource|thumbnail_generation_job',
      'generation_buffer': 'resource|thumbnail_generation_buffer',
      'result_copy': 'resource|thumbnail_copy',
      'result_shape': 'result|media_thumbnail',
      'request_bound': 'field|max_pixel_edge',
      'copy_value': 'field|thumbnail_copy',
      'copy_byte_length': 'field|thumbnail_byte_length',
      'copy_width': 'field|thumbnail_pixel_width',
      'copy_height': 'field|thumbnail_pixel_height',
      'copy_content_type': 'field|thumbnail_content_type',
      'copy_orientation': 'field|thumbnail_orientation_degrees',
      'source_type': 'field|media_type',
      'sample_time': 'field|poster_frame_millis',
    };
    final privacy = _capabilityStringSet(
      copy['privacyPolicyIds'],
      '$path boundedCopy.privacyPolicyIds',
    );
    final forbidden = _capabilityStringSet(
      copy['forbiddenRepresentationIds'],
      '$path boundedCopy.forbiddenRepresentationIds',
    );
    const expectedPrivacy = {
      'sanitize_thumbnail_encoding',
      'strip_thumbnail_exif',
      'strip_location_metadata',
      'minimize_embedded_metadata',
      'strip_thumbnail_source_filename',
      'strip_non_display_thumbnail_metadata',
    };
    const expectedForbidden = {
      'source_media_bytes',
      'path',
      'uri',
      'file_descriptor',
      'untyped_map',
      'platform_sdk_type',
    };
    if (copy['id'] != 'confirmed_media_thumbnail_policy' ||
        copy['operationId'] != 'read_media_thumbnail' ||
        !operations.contains(copy['operationId']) ||
        !_sameStringSet(roles.keys.toSet(), expectedRoles.keys.toSet()) ||
        expectedRoles.entries.any((entry) => roles[entry.key] != entry.value) ||
        copy['backendDetailsPolicy'] != 'redact_backend_decoder_details') {
      errors.add('$path 的 confirmed thumbnail role binding 与 V2 Profile 不一致');
    }
    if (privacy == null ||
        !_sameStringSet(privacy, expectedPrivacy) ||
        !privacyIds.containsAll(privacy)) {
      errors.add('$path thumbnail privacyPolicyIds 必须完整引用 privacy 条目');
    }
    if (forbidden == null || !_sameStringSet(forbidden, expectedForbidden)) {
      errors.add('$path thumbnail 必须禁止原图、路径、URI、descriptor、Map 与 SDK 类型');
    }

    final preconditions = _capabilityObjectList(
      copy['preconditions'],
      '$path boundedCopy.preconditions',
    );
    if (preconditions == null || preconditions.length != 1) {
      errors.add('$path thumbnail 必须声明唯一 leased source precondition');
    } else {
      final condition = preconditions.single;
      _validateCapabilityExactKeys(condition, const {
        'roleId',
        'predicateId',
        'acceptedValueIds',
        'rejectedValueIds',
        'failureId',
      }, '$path boundedCopy precondition');
      final accepted = _capabilityStringSet(
        condition['acceptedValueIds'],
        '$path boundedCopy accepted values',
      );
      final rejected = _capabilityStringSet(
        condition['rejectedValueIds'],
        '$path boundedCopy rejected values',
      );
      if (condition['roleId'] != 'source_state' ||
          condition['predicateId'] != 'current_state' ||
          accepted == null ||
          !_sameStringSet(accepted, const {'leased'}) ||
          rejected == null ||
          !_sameStringSet(rejected, const {
            'preview',
            'release_grace',
            'expiry_grace',
            'discarded',
            'released',
            'expired',
          }) ||
          condition['failureId'] != 'invalid_state') {
        errors.add('$path thumbnail source state precondition 不完整');
      }
    }

    final bounds = _capabilityObjectList(
      copy['bounds'],
      '$path boundedCopy.bounds',
    );
    final boundSignatures = <String, String>{};
    for (final bound in bounds ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(bound, const {
        'id',
        'roleId',
        'minimum',
        'maximum',
        'boundaryRoleId',
        'enforcement',
      }, '$path boundedCopy bound');
      if (bound['id'] is String) {
        boundSignatures[bound['id'] as String] =
            '${bound['roleId']}|${bound['minimum']}|${bound['maximum']}|'
            '${bound['boundaryRoleId']}|${bound['enforcement']}';
      }
    }
    const expectedBounds = {
      'request_edge_bound':
          'request_bound|64|512|null|reject_before_source_access',
      'copy_byte_bound':
          'copy_byte_length|1|524288|null|verify_before_result_commit',
      'copy_width_bound':
          'copy_width|1|512|request_bound|verify_not_above_boundary_or_global_max',
      'copy_height_bound':
          'copy_height|1|512|request_bound|verify_not_above_boundary_or_global_max',
      'copy_orientation_bound': 'copy_orientation|0|0|null|verify_exact',
    };
    if (!_sameStringSet(
          boundSignatures.keys.toSet(),
          expectedBounds.keys.toSet(),
        ) ||
        expectedBounds.entries.any(
          (entry) => boundSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path thumbnail generic bounds 与 V2 Profile 不一致');
    }

    final transforms = _capabilityObjectList(
      copy['transforms'],
      '$path boundedCopy.transforms',
    );
    final transformGuarantees = <String, Set<String>>{};
    final transformRoleSignatures = <String, String>{};
    for (final transform in transforms ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(transform, const {
        'id',
        'inputRoleIds',
        'outputRoleIds',
        'guaranteeIds',
      }, '$path boundedCopy transform');
      final id = transform['id'];
      final guarantees = _capabilityStringSet(
        transform['guaranteeIds'],
        '$path boundedCopy transform guarantees',
      );
      final inputRoles = _capabilityStringSet(
        transform['inputRoleIds'],
        '$path boundedCopy transform input roles',
      );
      final outputRoles = _capabilityStringSet(
        transform['outputRoleIds'],
        '$path boundedCopy transform output roles',
      );
      if (id is String &&
          guarantees != null &&
          inputRoles != null &&
          outputRoles != null) {
        transformGuarantees[id] = guarantees;
        final sortedInputs = inputRoles.toList()..sort();
        final sortedOutputs = outputRoles.toList()..sort();
        transformRoleSignatures[id] =
            '${sortedInputs.join(',')}|${sortedOutputs.join(',')}';
      }
    }
    const expectedTransformRoles = {
      'sanitize_and_encode':
          'source_resource|copy_content_type,copy_value,generation_buffer',
      'normalize_display_orientation':
          'source_resource|copy_height,copy_orientation,copy_value,copy_width',
      'verify_copy_length': 'copy_value|copy_byte_length',
      'select_video_sample':
          'source_resource,source_type|generation_buffer,sample_time',
    };
    const expectedTransformGuarantees = <String, Set<String>>{
      'sanitize_and_encode': {
        'image_jpeg_only',
        'reencode_or_equivalent_sanitize',
        'strip_exif_location_device_filename_and_non_display_metadata',
        'source_lease_ttl_grace_tombstone_unchanged',
      },
      'normalize_display_orientation': {
        'physically_upright_pixels',
        'orientation_zero',
      },
      'verify_copy_length': {'declared_length_equals_actual_copy_length'},
      'select_video_sample': {
        'photo_sample_time_null',
        'video_target_minimum_of_1000_and_floor_duration_divided_by_2',
        'target_then_nearest_after_else_nearest_before',
        'equal_distance_earlier_frame',
        'actual_sample_time_returned',
      },
    };
    if (!_sameStringSet(
          transformGuarantees.keys.toSet(),
          expectedTransformGuarantees.keys.toSet(),
        ) ||
        !_sameStringSet(
          transformRoleSignatures.keys.toSet(),
          expectedTransformRoles.keys.toSet(),
        ) ||
        expectedTransformRoles.entries.any(
          (entry) => transformRoleSignatures[entry.key] != entry.value,
        ) ||
        expectedTransformGuarantees.entries.any(
          (entry) =>
              transformGuarantees[entry.key] == null ||
              !_sameStringSet(transformGuarantees[entry.key]!, entry.value),
        )) {
      errors.add('$path thumbnail transform guarantees 不完整');
    }

    _validateCapabilityBoundedCopyOwnership(copy['ownershipTransfer'], path);
    _validateCapabilityBoundedCopyExecution(copy['execution'], failures, path);
    _validateCapabilityBoundedCopyRace(
      copy['raceArbitration'],
      operations,
      lifecycleRules,
      failures,
      path,
    );
    if (!(fields['max_pixel_edge'] ?? '').contains('|64|512|') ||
        !(fields['thumbnail_byte_length'] ?? '').contains('|1|524288|') ||
        !(fields['thumbnail_pixel_width'] ?? '').contains('|1|512|') ||
        !(fields['thumbnail_pixel_height'] ?? '').contains('|1|512|') ||
        !(fields['thumbnail_orientation_degrees'] ?? '').contains('|0|') ||
        !(fields['thumbnail_copy'] ?? '').startsWith(
          'bounded_copy|true|false|',
        )) {
      errors.add('$path thumbnail policy 未绑定结构化字段边界');
    }
    _validateCapabilityDescription(copy, '$path bounded copy policy');
  }

  void _validateCapabilityBoundedCopyOwnership(Object? value, String path) {
    final ownership = _capabilityObject(
      value,
      '$path boundedCopy.ownershipTransfer',
    );
    if (ownership == null) {
      return;
    }
    _validateCapabilityExactKeys(ownership, const {
      'initialOwnerRoleId',
      'transferAtId',
      'transferredOwnerRoleId',
      'atomic',
      'postTransferPolicy',
    }, '$path boundedCopy ownership transfer');
    if (ownership['initialOwnerRoleId'] != 'generation_buffer' ||
        ownership['transferAtId'] != 'atomic_result_commit' ||
        ownership['transferredOwnerRoleId'] != 'result_copy' ||
        ownership['atomic'] != true ||
        ownership['postTransferPolicy'] !=
            'caller_owned_independent_copy_not_revoked_by_source_release_expiry_restart_or_cleanup') {
      errors.add(
        '$path thumbnail 必须从 module generation buffer 原子转移为独立 caller copy',
      );
    }
  }

  void _validateCapabilityBoundedCopyExecution(
    Object? value,
    Set<String> failures,
    String path,
  ) {
    final execution = _capabilityObject(value, '$path boundedCopy.execution');
    if (execution == null) {
      return;
    }
    _validateCapabilityExactKeys(execution, const {
      'preAccessRegistration',
      'concurrencyBounds',
      'workBudgets',
      'sourceReductionPolicy',
      'overloadFailureId',
    }, '$path boundedCopy execution');
    final registration = _capabilityObject(
      execution['preAccessRegistration'],
      '$path boundedCopy pre-access registration',
    );
    if (registration != null) {
      _validateCapabilityExactKeys(registration, const {
        'managedRoleId',
        'beforeAccessRoleId',
        'required',
      }, '$path boundedCopy pre-access registration');
      if (registration['managedRoleId'] != 'in_flight_job' ||
          registration['beforeAccessRoleId'] != 'source_resource' ||
          registration['required'] != true) {
        errors.add(
          '$path thumbnail in-flight managed job 必须在 source access 前登记',
        );
      }
    }

    final concurrency = _capabilityObjectList(
      execution['concurrencyBounds'],
      '$path boundedCopy concurrency bounds',
    );
    final concurrencyByScope = <String, int>{};
    for (final bound in concurrency ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(bound, const {
        'scopeRoleId',
        'maximum',
      }, '$path boundedCopy concurrency bound');
      if (bound['scopeRoleId'] is String && bound['maximum'] is int) {
        concurrencyByScope[bound['scopeRoleId'] as String] =
            bound['maximum'] as int;
      }
    }
    if (concurrencyByScope.length != 2 ||
        concurrencyByScope['source_scope'] != 1 ||
        concurrencyByScope['module_scope'] != 2) {
      errors.add('$path thumbnail 必须固定每 Media 1、每 Module 2 个 in-flight job');
    }

    final budgets = _capabilityObjectList(
      execution['workBudgets'],
      '$path boundedCopy work budgets',
    );
    final budgetSignatures = <String, String>{};
    for (final budget in budgets ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(budget, const {
        'id',
        'scopeRoleId',
        'unitId',
        'maximum',
        'enforcement',
      }, '$path boundedCopy work budget');
      if (budget['id'] is String) {
        budgetSignatures[budget['id'] as String] =
            '${budget['scopeRoleId']}|${budget['unitId']}|'
            '${budget['maximum']}|${budget['enforcement']}';
      }
    }
    const expectedBudgets = {
      'decoded_pixel_budget':
          'in_flight_job|pixel|1048576|reject_or_subsample_before_allocation',
      'job_working_memory_budget':
          'in_flight_job|byte|8388608|reject_before_budget_exceeded',
      'module_working_memory_budget':
          'module_scope|byte|16777216|reject_before_budget_exceeded',
    };
    if (!_sameStringSet(
          budgetSignatures.keys.toSet(),
          expectedBudgets.keys.toSet(),
        ) ||
        expectedBudgets.entries.any(
          (entry) => budgetSignatures[entry.key] != entry.value,
        ) ||
        execution['sourceReductionPolicy'] !=
            'decode_time_subsample_before_full_resolution_allocation' ||
        execution['overloadFailureId'] != 'thumbnail_overloaded' ||
        !failures.contains(execution['overloadFailureId'])) {
      errors.add(
        '$path thumbnail decoded-pixel、working-memory、subsampling 或 overload 预算不完整',
      );
    }
  }

  void _validateCapabilityBoundedCopyRace(
    Object? value,
    Set<String> operations,
    Set<String> lifecycleRules,
    Set<String> failures,
    String path,
  ) {
    final race = _capabilityObject(value, '$path boundedCopy.raceArbitration');
    if (race == null) {
      return;
    }
    _validateCapabilityExactKeys(race, const {
      'linearizationPoint',
      'winnerPolicy',
      'outcomeDelivery',
      'cleanupExecution',
      'successFinalizationExecution',
      'successCommitEffect',
      'failureCleanupSequenceIds',
      'successFinalizationSequenceIds',
      'triggerPolicies',
    }, '$path boundedCopy race arbitration');
    const cleanupSequence = <String>[
      'revoke_source_access',
      'cancel_and_await_decoder',
      'close_source_handles',
      'wipe_decoded_pixels',
      'wipe_generation_buffer',
      'discard_partial_copy',
      'unregister_managed_job',
    ];
    const successFinalizationSequence = <String>[
      'close_source_access',
      'finish_and_close_decoder',
      'close_source_handles',
      'wipe_decoded_pixels',
      'wipe_generation_buffer',
      'unregister_managed_job',
    ];
    bool matchesSequence(Object? candidate, List<String> expected) {
      if (candidate is! List<Object?> ||
          candidate.any((item) => item is! String)) {
        return false;
      }
      final actual = candidate.cast<String>();
      return actual.length == expected.length &&
          List.generate(
            actual.length,
            (index) => index,
          ).every((index) => actual[index] == expected[index]);
    }

    if (race['linearizationPoint'] != 'atomic_terminal_outcome_commit' ||
        race['winnerPolicy'] != 'first_terminal_trigger_wins' ||
        race['outcomeDelivery'] != 'exactly_once' ||
        race['cleanupExecution'] != 'exactly_once_for_non_success_winner' ||
        race['successFinalizationExecution'] !=
            'exactly_once_after_atomic_transfer_before_result_delivery' ||
        race['successCommitEffect'] !=
            'caller_copy_independent_and_never_revoked_by_later_source_state' ||
        !matchesSequence(race['failureCleanupSequenceIds'], cleanupSequence) ||
        !matchesSequence(
          race['successFinalizationSequenceIds'],
          successFinalizationSequence,
        )) {
      errors.add(
        '$path thumbnail race 必须使用原子 linearization、first winner、exactly-once failure cleanup 与 success finalization',
      );
    }

    const expectedTriggers = {
      'lifecycle|thumbnail_result_committed|result|media_thumbnail|success_finalization',
      'operation|release_media|failure|invalid_state|failure_cleanup',
      'lifecycle|lease_expired|failure|invalid_state|failure_cleanup',
      'lifecycle|app_restarted|failure|media_invalid|failure_cleanup',
      'lifecycle|thumbnail_read_cancelled|failure|thumbnail_generation_cancelled|failure_cleanup',
      'lifecycle|thumbnail_generation_aborted|failure|thumbnail_generation_failed|failure_cleanup',
    };
    final triggerItems = _capabilityObjectList(
      race['triggerPolicies'],
      '$path boundedCopy race triggers',
    );
    final triggerSignatures = <String>{};
    for (final trigger in triggerItems ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(trigger, const {
        'triggerKind',
        'triggerId',
        'outcomeKind',
        'outcomeId',
        'sequenceKind',
        'sequenceIds',
      }, '$path boundedCopy race trigger');
      final kind = trigger['triggerKind'];
      final id = trigger['triggerId'];
      final outcomeKind = trigger['outcomeKind'];
      final outcomeId = trigger['outcomeId'];
      final sequenceKind = trigger['sequenceKind'];
      final success = outcomeKind == 'result';
      if (kind == 'operation' && !operations.contains(id)) {
        errors.add('$path thumbnail race 引用了未知 operation trigger');
      }
      if (kind == 'lifecycle' && !lifecycleRules.contains(id)) {
        errors.add('$path thumbnail race 引用了未知 lifecycle trigger');
      }
      if (outcomeKind == 'failure' && !failures.contains(outcomeId)) {
        errors.add('$path thumbnail race 引用了未知 Failure outcome');
      }
      final expectedSequence = success
          ? successFinalizationSequence
          : cleanupSequence;
      if (sequenceKind !=
              (success ? 'success_finalization' : 'failure_cleanup') ||
          !matchesSequence(trigger['sequenceIds'], expectedSequence)) {
        errors.add('$path thumbnail race trigger cleanup/finalization 顺序不一致');
      }
      if (!triggerSignatures.add(
        '$kind|$id|$outcomeKind|$outcomeId|$sequenceKind',
      )) {
        errors.add('$path thumbnail race 不得重复 terminal trigger outcome');
      }
    }
    if (triggerItems?.length != expectedTriggers.length ||
        !_sameStringSet(triggerSignatures, expectedTriggers)) {
      errors.add('$path thumbnail terminal trigger 集合或唯一 outcome 不完整');
    }
  }

  void _validateCapabilityStreamingCopies(
    Object? value,
    Map<String, String> fields,
    Set<String> operations,
    Set<String> lifecycleRules,
    Set<String> failures,
    Set<String> resources,
    Set<String> privacyIds,
    String path,
  ) {
    final copies = _capabilityObjectList(
      value,
      '$path resourcePolicy.streamingCopies',
    );
    if (copies == null || copies.length != 1) {
      errors.add('$path 必须声明一个 confirmed_media_export_policy');
      return;
    }
    final copy = copies.single;
    _validateCapabilityExactKeys(copy, const {
      'id',
      'description',
      'operationId',
      'roleBindings',
      'preconditions',
      'sourceRepresentations',
      'bounds',
      'sinkProtocol',
      'execution',
      'terminalPolicy',
      'failureBehaviors',
      'successResultId',
      'successResultFieldIds',
      'sourceLeasePolicy',
      'privacyPolicyIds',
      'forbiddenRepresentationIds',
      'backendDetailsPolicy',
    }, '$path streaming copy policy');
    _validateCapabilityDescription(copy, '$path streaming copy policy');
    if (copy['id'] != 'confirmed_media_export_policy' ||
        copy['operationId'] != 'copy_confirmed_media_to_sink' ||
        !operations.contains(copy['operationId']) ||
        copy['successResultId'] != 'media_export_result') {
      errors.add('$path export policy 必须绑定 V4 operation/result');
    }

    List<String>? orderedIds(Object? raw, String label) {
      if (raw is! List<Object?> || raw.any((item) => item is! String)) {
        errors.add('$label 必须是字符串数组');
        return null;
      }
      final ids = raw.cast<String>();
      if (ids.toSet().length != ids.length) {
        errors.add('$label 不得重复');
      }
      for (final id in ids) {
        _validateStableCapabilityId(id, label);
      }
      return ids;
    }

    final roleBindings = _capabilityObjectList(
      copy['roleBindings'],
      '$path export roleBindings',
    );
    final roleSignatures = <String, String>{};
    for (final role in roleBindings ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(role, const {
        'roleId',
        'bindingKind',
        'bindingId',
      }, '$path export role binding');
      final roleId = role['roleId'];
      final bindingId = role['bindingId'];
      if (roleId is String && bindingId is String) {
        if (roleSignatures.containsKey(roleId)) {
          errors.add('$path export roleBindings 包含重复 roleId：$roleId');
        }
        roleSignatures[roleId] = '${role['bindingKind']}|$bindingId';
        if (role['bindingKind'] == 'field' && !fields.containsKey(bindingId)) {
          errors.add('$path export role $roleId 引用了未知 field');
        }
        if (role['bindingKind'] == 'resource' &&
            !resources.contains(bindingId)) {
          errors.add('$path export role $roleId 引用了未知 resource');
        }
      }
    }
    const expectedRoles = {
      'source_resource': 'resource|captured_media',
      'source_state': 'state_machine|media',
      'source_scope': 'field|media_handle',
      'source_type': 'field|media_type',
      'source_content_type': 'field|content_type',
      'source_declared_length': 'field|byte_length',
      'requested_max_length': 'field|media_export_max_length',
      'actual_length': 'field|byte_length',
      'sink_capability': 'field|media_copy_sink',
      'module_scope': 'scope|module_instance',
      'export_job': 'resource|media_export_job',
      'chunk_buffer': 'resource|media_export_buffer',
      'success_result': 'result|media_export_result',
    };
    if (roleSignatures.length != expectedRoles.length ||
        expectedRoles.entries.any(
          (entry) => roleSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path export roleBindings 与 V4 source/sink/job/buffer 不一致');
    }
    if (!(fields['media_copy_sink'] ?? '').startsWith(
          'sink_capability|true|false|',
        ) ||
        !(fields['media_export_max_length'] ?? '').contains('|1|52428800|')) {
      errors.add('$path export request 必须使用 typed sink 与 50 MiB 结构化上限');
    }

    final preconditions = _capabilityObjectList(
      copy['preconditions'],
      '$path export preconditions',
    );
    final preconditionSignatures = <String>{};
    for (final condition in preconditions ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(condition, const {
        'roleId',
        'predicateId',
        'acceptedValueIds',
        'rejectedValueIds',
        'failureId',
      }, '$path export precondition');
      final accepted = _capabilityStringSet(
        condition['acceptedValueIds'],
        '$path export accepted values',
      );
      final rejected = _capabilityStringSet(
        condition['rejectedValueIds'],
        '$path export rejected values',
      );
      final acceptedSorted = (accepted ?? const <String>{}).toList()..sort();
      final rejectedSorted = (rejected ?? const <String>{}).toList()..sort();
      preconditionSignatures.add(
        '${condition['roleId']}|${condition['predicateId']}|'
        '${acceptedSorted.join(',')}|${rejectedSorted.join(',')}|'
        '${condition['failureId']}',
      );
    }
    const expectedPreconditions = {
      'source_state|current_state|leased|discarded,expired,expiry_grace,'
          'preview,release_grace,released|invalid_state',
      'source_type|closed_source_type|photo,video||invalid_state',
      'source_content_type|closed_source_content_type|image_jpeg,video_mp4||'
          'invalid_state',
    };
    if (!_sameStringSet(preconditionSignatures, expectedPreconditions)) {
      errors.add('$path export 必须只接受 active lease 与 JPEG/MP4 source');
    }

    final sourceRepresentations = _capabilityObjectList(
      copy['sourceRepresentations'],
      '$path export sourceRepresentations',
    );
    final sourceRepresentationSignatures = <String>{};
    for (final representation
        in sourceRepresentations ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(representation, const {
        'sourceValueId',
        'formatId',
        'contentType',
      }, '$path export source representation');
      final sourceValueId = representation['sourceValueId'];
      final formatId = representation['formatId'];
      final contentType = representation['contentType'];
      if (sourceValueId is String &&
          formatId is String &&
          contentType is String) {
        sourceRepresentationSignatures.add(
          '$sourceValueId|$formatId|$contentType',
        );
      }
    }
    if (!_sameStringSet(sourceRepresentationSignatures, const {
      'photo|image_jpeg|image/jpeg',
      'video|video_mp4|video/mp4',
    })) {
      errors.add('$path export source type/format/content type 映射必须精确闭合');
    }

    final bounds = _capabilityObjectList(copy['bounds'], '$path export bounds');
    final boundSignatures = <String, String>{};
    for (final bound in bounds ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(bound, const {
        'id',
        'roleId',
        'minimum',
        'maximum',
        'boundaryRoleId',
        'enforcement',
      }, '$path export bound');
      if (bound['id'] is String) {
        boundSignatures[bound['id'] as String] =
            '${bound['roleId']}|${bound['minimum']}|${bound['maximum']}|'
            '${bound['boundaryRoleId']}|${bound['enforcement']}';
      }
    }
    const expectedBounds = {
      'requested_export_length_bound':
          'requested_max_length|1|52428800|null|reject_before_reservation',
      'declared_source_length_bound':
          'source_declared_length|1|52428800|requested_max_length|'
          'verify_before_source_or_sink_open',
      'chunk_buffer_bound':
          'chunk_buffer|1|262144|null|verify_before_each_sink_write',
      'actual_export_length_bound':
          'actual_length|1|52428800|source_declared_length|'
          'verify_equal_before_sink_commit',
    };
    if (boundSignatures.length != expectedBounds.length ||
        expectedBounds.entries.any(
          (entry) => boundSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path export 必须固定 50 MiB source 与 256 KiB chunk 边界');
    }

    final sink = _capabilityObject(
      copy['sinkProtocol'],
      '$path export sinkProtocol',
    );
    if (sink != null) {
      _validateCapabilityExactKeys(sink, const {
        'sinkRoleId',
        'consumerScope',
        'serializationPolicy',
        'registryStoragePolicy',
        'methods',
        'invocationOrderIds',
        'sequentialWrites',
        'terminalExclusivity',
        'cancellationAware',
        'cancellationConvergenceSeconds',
      }, '$path export sinkProtocol');
      if (sink['sinkRoleId'] != 'sink_capability' ||
          sink['consumerScope'] != 'native_consumer_call_only' ||
          sink['serializationPolicy'] != 'forbidden' ||
          sink['registryStoragePolicy'] != 'forbidden' ||
          sink['sequentialWrites'] != true ||
          sink['terminalExclusivity'] != 'commit_xor_abort' ||
          sink['cancellationAware'] != true ||
          sink['cancellationConvergenceSeconds'] != 5) {
        errors.add('$path export sink 必须是调用域 Native-only 且 5 秒内响应取消');
      }
      final methodSignatures = <String, String>{};
      for (final method
          in _capabilityObjectList(
                sink['methods'],
                '$path export sink methods',
              ) ??
              const <Map<String, Object?>>[]) {
        _validateCapabilityExactKeys(method, const {
          'id',
          'phase',
          'cardinality',
          'payloadRoleIds',
        }, '$path export sink method');
        final payloads = _capabilityStringSet(
          method['payloadRoleIds'],
          '$path export sink payload roles',
        );
        final sorted = (payloads ?? const <String>{}).toList()..sort();
        if (method['id'] is String) {
          methodSignatures[method['id'] as String] =
              '${method['phase']}|${method['cardinality']}|${sorted.join(',')}';
        }
      }
      const expectedMethods = {
        'begin_sink':
            'begin|exactly_once_before_first_write|source_content_type,'
            'source_declared_length,source_type',
        'write_sink_chunk':
            'write|zero_or_more_sequential_bounded_calls|chunk_buffer',
        'commit_sink': 'commit|exactly_once_on_success|actual_length',
        'abort_sink': 'abort|exactly_once_after_begin_on_non_success|',
      };
      if (methodSignatures.length != expectedMethods.length ||
          expectedMethods.entries.any(
            (entry) => methodSignatures[entry.key] != entry.value,
          )) {
        errors.add('$path export sink 必须闭合 begin/write/commit/abort 协议');
      }
      final order = orderedIds(
        sink['invocationOrderIds'],
        '$path export sink invocation order',
      );
      if (order?.join('|') !=
          'begin_sink|write_zero_or_more_chunks|commit_sink_or_abort_sink') {
        errors.add('$path export sink 调用顺序不正确');
      }
    }

    final execution = _capabilityObject(
      copy['execution'],
      '$path export execution',
    );
    if (execution != null) {
      _validateCapabilityExactKeys(execution, const {
        'reservationRoleIds',
        'beforeAccessRoleIds',
        'atomicReservation',
        'capacityPolicy',
        'concurrencyBounds',
        'workBudgets',
        'deadlineSeconds',
        'deadlineStartId',
        'cancellationPolicy',
        'lateResultPolicy',
        'lengthCheckIds',
        'fullBufferingPolicy',
        'overloadFailureId',
      }, '$path export execution');
      final reservations = _capabilityStringSet(
        execution['reservationRoleIds'],
        '$path export reservation roles',
      );
      final beforeAccess = _capabilityStringSet(
        execution['beforeAccessRoleIds'],
        '$path export before-access roles',
      );
      final lengthChecks = orderedIds(
        execution['lengthCheckIds'],
        '$path export length checks',
      );
      if (reservations == null ||
          !_sameStringSet(reservations, const {'export_job', 'chunk_buffer'}) ||
          beforeAccess == null ||
          !_sameStringSet(beforeAccess, const {
            'source_resource',
            'sink_capability',
          }) ||
          execution['atomicReservation'] != true ||
          execution['capacityPolicy'] !=
              'reject_without_sink_call_source_open_wait_or_existing_job_eviction' ||
          execution['deadlineSeconds'] != 120 ||
          execution['deadlineStartId'] != 'registry_reservation_committed' ||
          execution['cancellationPolicy'] !=
              'close_gate_cancel_task_and_sink_then_converge_within_sink_bound' ||
          execution['lateResultPolicy'] !=
              'drop_without_commit_abort_or_second_outcome' ||
          lengthChecks?.join('|') !=
              'declared_length_before_copy|cumulative_length_before_each_write|actual_equals_declared_before_commit' ||
          execution['fullBufferingPolicy'] !=
              'forbidden_stream_bounded_chunks_only' ||
          execution['overloadFailureId'] != 'media_export_overloaded') {
        errors.add('$path export 预留/deadline/取消/长度/流式策略不完整');
      }
      final concurrency = <String, int>{};
      for (final bound
          in _capabilityObjectList(
                execution['concurrencyBounds'],
                '$path export concurrencyBounds',
              ) ??
              const <Map<String, Object?>>[]) {
        _validateCapabilityExactKeys(bound, const {
          'scopeRoleId',
          'maximum',
        }, '$path export concurrency bound');
        if (bound['scopeRoleId'] is String && bound['maximum'] is int) {
          concurrency[bound['scopeRoleId'] as String] = bound['maximum'] as int;
        }
      }
      if (concurrency.length != 2 ||
          concurrency['source_scope'] != 1 ||
          concurrency['module_scope'] != 4) {
        errors.add('$path export 必须固定每媒体 1 job、每 Module 4 job');
      }
      final budgets = <String, String>{};
      for (final budget
          in _capabilityObjectList(
                execution['workBudgets'],
                '$path export workBudgets',
              ) ??
              const <Map<String, Object?>>[]) {
        _validateCapabilityExactKeys(budget, const {
          'id',
          'scopeRoleId',
          'unitId',
          'maximum',
          'enforcement',
        }, '$path export work budget');
        if (budget['id'] is String) {
          budgets[budget['id'] as String] =
              '${budget['scopeRoleId']}|${budget['unitId']}|'
              '${budget['maximum']}|${budget['enforcement']}';
        }
      }
      const expectedBudgets = {
        'export_job_buffer_budget':
            'export_job|byte|262144|reject_before_allocation_or_write',
        'export_module_buffer_budget':
            'module_scope|byte|1048576|reject_before_reservation',
      };
      if (budgets.length != expectedBudgets.length ||
          expectedBudgets.entries.any(
            (entry) => budgets[entry.key] != entry.value,
          )) {
        errors.add('$path export 必须固定 256 KiB job 与 1 MiB Module buffer 预算');
      }
    }

    final terminal = _capabilityObject(
      copy['terminalPolicy'],
      '$path export terminalPolicy',
    );
    if (terminal != null) {
      _validateCapabilityExactKeys(terminal, const {
        'linearizationPoint',
        'winnerPolicy',
        'outcomeDelivery',
        'successSinkActionId',
        'failureSinkActionId',
        'successSinkActionCardinality',
        'failureSinkActionCardinality',
        'terminalExclusivity',
        'failureCleanupSequenceIds',
        'successFinalizationSequenceIds',
      }, '$path export terminal policy');
      final failureSequence = orderedIds(
        terminal['failureCleanupSequenceIds'],
        '$path export failure cleanup sequence',
      );
      final successSequence = orderedIds(
        terminal['successFinalizationSequenceIds'],
        '$path export success finalization sequence',
      );
      if (terminal['linearizationPoint'] !=
              'media_export_terminal_outcome_commit' ||
          terminal['winnerPolicy'] != 'first_terminal_trigger_wins' ||
          terminal['outcomeDelivery'] != 'exactly_once' ||
          terminal['successSinkActionId'] != 'commit_sink' ||
          terminal['failureSinkActionId'] != 'abort_sink_if_begin_succeeded' ||
          terminal['successSinkActionCardinality'] != 'exactly_once' ||
          terminal['failureSinkActionCardinality'] !=
              'exactly_once_after_begin' ||
          terminal['terminalExclusivity'] != 'commit_xor_abort' ||
          failureSequence?.join('|') !=
              'close_callback_gate|cancel_export_task_and_sink|abort_sink_once_if_begun|close_source_access|wipe_export_buffer|release_export_buffer_reservation|unregister_export_job' ||
          successSequence?.join('|') !=
              'commit_sink_once|close_callback_gate|close_source_access|wipe_export_buffer|release_export_buffer_reservation|unregister_export_job') {
        errors.add('$path export 必须保证 commit/abort 唯一终态并最后释放 registry');
      }
    }

    final behaviorEntries = _capabilityObjectList(
      copy['failureBehaviors'],
      '$path export failureBehaviors',
    );
    final behaviorSignatures = <String, String>{};
    for (final behavior in behaviorEntries ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(behavior, const {
        'failureId',
        'recoverable',
        'terminal',
        'triggerIds',
        'raceWinnerId',
        'sinkActionId',
        'sourceLeaseEffect',
        'detailsPolicy',
      }, '$path export failure behavior');
      final failureId = behavior['failureId'];
      final triggerIds = _capabilityStringSet(
        behavior['triggerIds'],
        '$path export failure triggers',
      );
      final sortedTriggers = (triggerIds ?? const <String>{}).toList()..sort();
      if (failureId is String) {
        if (!failures.contains(failureId)) {
          errors.add('$path export failure behavior 引用了未知 Failure：$failureId');
        }
        behaviorSignatures[failureId] =
            '${behavior['recoverable']}|${behavior['terminal']}|'
            '${sortedTriggers.join(',')}|${behavior['raceWinnerId']}|'
            '${behavior['sinkActionId']}|${behavior['sourceLeaseEffect']}|'
            '${behavior['detailsPolicy']}';
      }
    }
    const expectedBehavior = {
      'media_export_conflict':
          'true|false|per_source_job_capacity_precheck|pre_access_rejection|'
          'not_invoked|active_lease_unchanged|empty_or_length_only_redacted',
      'media_export_overloaded':
          'true|false|module_capacity_precheck|pre_access_rejection|'
          'not_invoked|active_lease_unchanged|empty_or_length_only_redacted',
      'media_export_too_large':
          'true|false|actual_length_check,cumulative_length_check,'
          'declared_length_check|length_guard|abort_once_if_begin_succeeded|'
          'active_lease_unchanged|empty_or_length_only_redacted',
      'media_export_sink_rejected':
          'true|false|sink_begin_rejected,sink_commit_rejected|sink_rejection|'
          'abort_once_if_begin_succeeded|active_lease_unchanged|'
          'empty_or_length_only_redacted',
      'media_export_read_failed':
          'true|false|source_read_failed|source_failure|'
          'abort_once_if_begin_succeeded|active_lease_unchanged|'
          'empty_or_length_only_redacted',
      'media_export_write_failed':
          'true|false|sink_write_failed|sink_failure|'
          'abort_once_if_begin_succeeded|active_lease_unchanged|'
          'empty_or_length_only_redacted',
      'media_export_cancelled':
          'true|false|media_export_cancel_requested|caller_cancellation|'
          'abort_once_if_begin_succeeded|active_lease_unchanged|'
          'empty_or_length_only_redacted',
      'media_export_timed_out':
          'true|false|media_export_deadline_elapsed|deadline|'
          'abort_once_if_begin_succeeded|active_lease_unchanged|'
          'empty_or_length_only_redacted',
      'media_invalid':
          'false|false|strict_registry_lookup_failed|pre_access_rejection|'
          'not_invoked|no_active_lease|empty_or_length_only_redacted',
      'invalid_state':
          'true|false|active_lease_validation_failed,lease_expired,'
          'release_media|source_state_change|abort_once_if_begin_succeeded|'
          'winner_preserves_defined_source_state_transition|'
          'empty_or_length_only_redacted',
      'invalid_argument':
          'true|false|request_validation_failed|pre_access_rejection|'
          'not_invoked|active_lease_unchanged|empty_or_length_only_redacted',
      'system_interrupted':
          'true|true|core_closed|core_close|abort_once_if_begin_succeeded|'
          'core_close_invalidates_module_resources|'
          'empty_or_length_only_redacted',
    };
    if (behaviorSignatures.length != expectedBehavior.length ||
        expectedBehavior.entries.any(
          (entry) => behaviorSignatures[entry.key] != entry.value,
        )) {
      errors.add('$path export Failure taxonomy、race winner 或 sink abort 行为漂移');
    }

    final successFields = _capabilityStringSet(
      copy['successResultFieldIds'],
      '$path export success result fields',
    );
    final policyPrivacy = _capabilityStringSet(
      copy['privacyPolicyIds'],
      '$path export privacy policies',
    );
    final forbidden = _capabilityStringSet(
      copy['forbiddenRepresentationIds'],
      '$path export forbidden representations',
    );
    const expectedPolicyPrivacy = {
      'media_export_sink_native_only',
      'media_export_no_storage_identity',
      'media_export_redacted_diagnostics',
    };
    const expectedForbidden = {
      'path',
      'uri',
      'file_descriptor',
      'platform_sdk_type',
      'untyped_map',
      'raw_source_bytes_result',
      'full_source_memory_buffer',
    };
    if (successFields == null ||
        !_sameStringSet(successFields, const {
          'media_handle',
          'media_type',
          'content_type',
          'byte_length',
        }) ||
        copy['sourceLeasePolicy'] !=
            'caller_retains_active_lease_no_release_ttl_refresh_grace_or_tombstone_change' ||
        policyPrivacy == null ||
        !_sameStringSet(policyPrivacy, expectedPolicyPrivacy) ||
        !privacyIds.containsAll(expectedPolicyPrivacy) ||
        forbidden == null ||
        !_sameStringSet(forbidden, expectedForbidden) ||
        copy['backendDetailsPolicy'] !=
            'redact_sink_source_os_and_exception_details') {
      errors.add('$path export result/lease/privacy/representation 策略不完整');
    }

    for (final lifecycleId in const {
      'media_export_cancel_requested',
      'media_export_deadline_elapsed',
      'media_export_aborted',
      'media_export_committed',
      'core_closed',
      'lease_expired',
    }) {
      if (!lifecycleRules.contains(lifecycleId)) {
        errors.add('$path export 缺少 lifecycle rule：$lifecycleId');
      }
    }
  }

  Set<String>? _capabilitySemanticEntryIds(Object? value, String label) {
    final entries = _capabilityObjectList(value, label);
    if (entries == null) {
      return null;
    }
    final ids = <String>{};
    for (final entry in entries) {
      _validateCapabilityExactKeys(entry, const {'id', 'description'}, label);
      _addStableCapabilityId(ids, entry['id'], label);
      _validateCapabilityDescription(entry, label);
    }
    return ids;
  }

  Map<String, Object?>? _capabilityObject(Object? value, String label) {
    if (value is! Map<String, Object?>) {
      errors.add('$label 必须是 JSON Object');
      return null;
    }
    return value;
  }

  List<Map<String, Object?>>? _capabilityObjectList(
    Object? value,
    String label,
  ) {
    if (value is! List<Object?>) {
      errors.add('$label 必须是 JSON Array');
      return null;
    }
    final result = <Map<String, Object?>>[];
    for (final item in value) {
      if (item is! Map<String, Object?>) {
        errors.add('$label 的元素必须是 JSON Object');
      } else {
        result.add(item);
      }
    }
    return result;
  }

  Set<String>? _capabilityStringSet(Object? value, String label) {
    if (value is! List<Object?> || value.any((item) => item is! String)) {
      errors.add('$label 必须是字符串数组');
      return null;
    }
    final result = value.cast<String>().toSet();
    if (result.length != value.length) {
      errors.add('$label 不得包含重复值');
    }
    return result;
  }

  bool _sameStringSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  void _validateCapabilityExactKeys(
    Map<String, Object?> value,
    Set<String> expected,
    String label,
  ) {
    final actual = value.keys.toSet();
    for (final key in expected.difference(actual)) {
      errors.add('$label 缺少字段：$key');
    }
    for (final key in actual.difference(expected)) {
      errors.add('$label 包含未知字段：$key');
    }
  }

  void _addStableCapabilityId(Set<String> ids, Object? value, String label) {
    if (value is! String) {
      errors.add('$label 必须声明字符串 id');
      return;
    }
    _validateStableCapabilityId(value, label);
    if (!ids.add(value)) {
      errors.add('$label 包含重复 id：$value');
    }
  }

  void _validateStableCapabilityId(String value, String label) {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
      errors.add('$label 包含不稳定语义 ID：$value');
    }
  }

  void _validateCapabilityDescription(
    Map<String, Object?> value,
    String label,
  ) {
    final description = value['description'];
    if (description is! String || description.trim().isEmpty) {
      errors.add('$label 必须声明非空 description');
    }
  }

  void _validateWireContracts() {
    const schemaPath = 'docs/bridge/contracts/wire.schema.json';
    const contractPath = 'docs/bridge/contracts/media-capture.wire.json';
    const capabilityPath =
        'docs/infrastructure/contracts/media-capture.capability.json';
    const detailPath = 'docs/bridge/media-capture.md';
    const goldenPath =
        'app/packages/app_media_capture_bridge/test/contracts/'
        'media-capture-v4-v3.golden.json';

    final schema = _readJsonObject(schemaPath, 'Wire JSON Schema');
    final contract = _readJsonObject(
      contractPath,
      'Media Capture Wire Contract',
    );
    final capability = _readJsonObject(
      capabilityPath,
      'Media Capture Capability Contract',
    );
    final golden = _readJsonObject(
      goldenPath,
      'Media Capture cross-runtime golden vectors',
    );
    final detail = _file(detailPath);

    if (!detail.existsSync()) {
      errors.add('缺少 Media Capture Bridge 文档：$detailPath');
    } else {
      for (final target in [
        _file(schemaPath),
        _file(contractPath),
        _file(capabilityPath),
        _file('docs/infrastructure/media-capture.md'),
        _file('docs/native-architecture.md'),
        _file('docs/bridge/README.md'),
      ]) {
        if (!_linksTo(detail, target)) {
          errors.add('$detailPath 必须链接 ${_relative(target)}');
        }
      }
    }

    if (schema != null) {
      _validateWireSchema(schema, schemaPath);
    }
    if (contract != null && capability != null) {
      _validateMediaCaptureWire(contract, capability, contractPath);
      final methods = _wireObjectsById(
        contract['methods'],
        'id',
        '$contractPath methods',
      );
      if (detail.existsSync() &&
          !detail.readAsStringSync().contains('${methods.length} 个 method')) {
        errors.add('$detailPath 的平台一致性 method 数量必须与 Wire current shape 一致');
      }
      if (golden != null) {
        _validateMediaCaptureCrossRuntimeGolden(
          golden,
          contract,
          capability,
          goldenPath,
        );
      }
    }
    _validateMediaCaptureIntegrationHost();
  }

  void _validateMediaCaptureCrossRuntimeGolden(
    Map<String, Object?> golden,
    Map<String, Object?> wire,
    Map<String, Object?> capability,
    String path,
  ) {
    _validateCapabilityExactKeys(golden, const {
      'schemaVersion',
      'contractId',
      'consumerBindings',
      'current',
      'history',
      'transfer',
      'lifecycle',
      'redaction',
    }, '$path 根节点');
    if (golden['schemaVersion'] != 1 ||
        golden['contractId'] != 'media_capture_cross_runtime_golden') {
      errors.add('$path 必须声明稳定 Schema 与 Contract ID');
    }

    final current = _capabilityObject(golden['current'], '$path current');
    _validateCapabilityExactKeys(current ?? const {}, const {
      'capabilityVersion',
      'wireVersion',
      'compatibleCapabilityVersions',
      'capabilityOperationIds',
      'capabilityEventIds',
      'capabilityFailureIds',
      'methodIds',
      'eventIds',
      'failureIds',
      'mappedCapabilityFailureIds',
      'wireProtocolFailureIds',
    }, '$path current');
    final methodIds = _capabilityStringSet(
      current?['methodIds'],
      '$path current.methodIds',
    );
    final eventIds = _capabilityStringSet(
      current?['eventIds'],
      '$path current.eventIds',
    );
    final failureIds = _capabilityStringSet(
      current?['failureIds'],
      '$path current.failureIds',
    );
    final capabilityOperationIds = _capabilityStringSet(
      current?['capabilityOperationIds'],
      '$path current.capabilityOperationIds',
    );
    final capabilityEventIds = _capabilityStringSet(
      current?['capabilityEventIds'],
      '$path current.capabilityEventIds',
    );
    final capabilityFailureIds = _capabilityStringSet(
      current?['capabilityFailureIds'],
      '$path current.capabilityFailureIds',
    );
    final mappedCapabilityFailureIds = _capabilityStringSet(
      current?['mappedCapabilityFailureIds'],
      '$path current.mappedCapabilityFailureIds',
    );
    final wireProtocolFailureIds = _capabilityStringSet(
      current?['wireProtocolFailureIds'],
      '$path current.wireProtocolFailureIds',
    );
    final wireMethodIds = _wireObjectsById(
      wire['methods'],
      'id',
      '$path Wire methods',
    ).keys.toSet();
    final wireEventIds = _wireObjectsById(
      wire['events'],
      'id',
      '$path Wire events',
    ).keys.toSet();
    final wireFailures = _wireObjectsById(
      wire['errors'],
      'code',
      '$path Wire failures',
    );
    final wireFailureIds = wireFailures.keys.toSet();
    final expectedMappedCapabilityFailures = wireFailures.entries
        .where((entry) => entry.value['source'] == 'capability_failure')
        .map((entry) => entry.key)
        .toSet();
    final expectedWireProtocolFailures = wireFailures.entries
        .where((entry) => entry.value['source'] == 'wire_protocol')
        .map((entry) => entry.key)
        .toSet();
    final nativeCapabilityOperationIds = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operations',
    ).keys.toSet();
    final nativeCapabilityEventIds = _wireObjectsById(
      capability['event'],
      'id',
      '$path Capability events',
    ).keys.toSet();
    final nativeCapabilityFailureIds = _wireObjectsById(
      capability['failure'],
      'id',
      '$path Capability failures',
    ).keys.toSet();
    if (current?['capabilityVersion'] != capability['capabilityVersion'] ||
        current?['wireVersion'] != wire['wireVersion'] ||
        !_wireJsonEquals(
          current?['compatibleCapabilityVersions'],
          wire['capability'] is Map<String, Object?>
              ? (wire['capability']
                    as Map<String, Object?>)['compatibleCapabilityVersions']
              : null,
        ) ||
        methodIds == null ||
        !_sameStringSet(methodIds, wireMethodIds) ||
        eventIds == null ||
        !_sameStringSet(eventIds, wireEventIds) ||
        failureIds == null ||
        !_sameStringSet(failureIds, wireFailureIds) ||
        capabilityOperationIds == null ||
        !_sameStringSet(capabilityOperationIds, nativeCapabilityOperationIds) ||
        capabilityEventIds == null ||
        !_sameStringSet(capabilityEventIds, nativeCapabilityEventIds) ||
        capabilityFailureIds == null ||
        !_sameStringSet(capabilityFailureIds, nativeCapabilityFailureIds) ||
        mappedCapabilityFailureIds == null ||
        !_sameStringSet(
          mappedCapabilityFailureIds,
          expectedMappedCapabilityFailures,
        ) ||
        wireProtocolFailureIds == null ||
        !_sameStringSet(wireProtocolFailureIds, expectedWireProtocolFailures)) {
      errors.add('$path current 必须精确绑定 Capability V4 与 Wire V3 shape');
    }

    final consumerBindings = _capabilityObjectList(
      golden['consumerBindings'],
      '$path consumerBindings',
    );
    const expectedConsumerPaths = {
      'app/packages/app_media_capture_bridge/test/media_capture_transfer_test.dart',
      'app/native/android/media_capture_gate/src/adapterTest/kotlin/com/example/media_capture/AndroidContractVectorGateTest.kt',
      'app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/Tests/MediaCaptureBridgeCoreTests/MediaCaptureWireCodecTests.swift',
      'app/packages/app_media_capture_bridge/ios/tool/verify-core-tests.sh',
    };
    final boundConsumerPaths = <String>{};
    for (final binding in consumerBindings ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(binding, const {
        'path',
        'implementationDigest',
      }, '$path consumer binding');
      final consumerPath = binding['path'];
      final digest = binding['implementationDigest'];
      if (consumerPath is! String ||
          !expectedConsumerPaths.contains(consumerPath)) {
        errors.add('$path consumer binding 包含未知路径：$consumerPath');
        continue;
      }
      if (!boundConsumerPaths.add(consumerPath)) {
        errors.add('$path consumer binding 重复声明：$consumerPath');
        continue;
      }
      if (digest is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
        errors.add('$path consumer binding 必须声明小写 SHA-256：$consumerPath');
        continue;
      }
      try {
        final actual = calculateImplementationDigest(root, [consumerPath]);
        if (actual != digest) {
          errors.add('$consumerPath 与跨 Runtime golden 的 consumer binding 不一致');
        }
      } on FileSystemException {
        errors.add('$consumerPath 必须存在并直接消费跨 Runtime golden vectors');
      } on FormatException catch (error) {
        errors.add('$path consumer binding 无效：${error.message}');
      }
    }
    if (!_sameStringSet(boundConsumerPaths, expectedConsumerPaths)) {
      errors.add('$path consumerBindings 必须精确绑定三端消费者与 iOS loader');
    }

    final history = _capabilityObject(golden['history'], '$path history');
    final capabilityHistory = _capabilityObjectList(
      history?['capability'],
      '$path history.capability',
    );
    final wireHistory = _capabilityObjectList(
      history?['wire'],
      '$path history.wire',
    );
    const expectedCapabilityHistory = <Object?>[
      {
        'version': 1,
        'operationCount': 13,
        'eventCount': 5,
        'nativeReadScope': true,
        'nativeRenderScope': 'none',
        'boundedExport': false,
      },
      {
        'version': 2,
        'operationCount': 18,
        'eventCount': 6,
        'nativeReadScope': true,
        'nativeRenderScope': 'callback_adapter',
        'boundedExport': false,
      },
      {
        'version': 3,
        'operationCount': 18,
        'eventCount': 6,
        'nativeReadScope': true,
        'nativeRenderScope': 'module_concrete_surface',
        'boundedExport': false,
      },
      {
        'version': 4,
        'operationCount': 19,
        'eventCount': 6,
        'nativeReadScope': true,
        'nativeRenderScope': 'module_concrete_surface',
        'boundedExport': true,
      },
    ];
    const expectedWireHistory = <Object?>[
      {
        'version': 1,
        'compatibleCapabilityVersions': [1],
        'methodCount': 12,
        'eventCount': 5,
        'exposesNativeRead': false,
        'exposesNativeRender': false,
        'exposesTransfer': false,
      },
      {
        'version': 2,
        'compatibleCapabilityVersions': [2, 3],
        'methodCount': 14,
        'eventCount': 5,
        'exposesNativeRead': false,
        'exposesNativeRender': false,
        'exposesTransfer': false,
      },
      {
        'version': 3,
        'compatibleCapabilityVersions': [4],
        'methodCount': 17,
        'eventCount': 5,
        'exposesNativeRead': false,
        'exposesNativeRender': false,
        'exposesTransfer': true,
      },
    ];
    if (!_wireJsonEquals(capabilityHistory, expectedCapabilityHistory) ||
        !_wireJsonEquals(wireHistory, expectedWireHistory)) {
      errors.add('$path history 必须固定 V1-V4 Capability 与 V1-V3 Wire 投影边界');
    }

    final transfer = _capabilityObject(golden['transfer'], '$path transfer');
    final goldenLimits = _capabilityObject(
      transfer?['limits'],
      '$path transfer.limits',
    );
    final wireTransfer = _capabilityObject(
      wire['transferStore'],
      '$path Wire transferStore',
    );
    final wireLimits = _capabilityObject(
      wireTransfer?['limits'],
      '$path Wire transferStore.limits',
    );
    if (!_wireJsonEquals(transfer?['mimeCases'], const <Object?>[
          {'mediaType': 'photo', 'contentType': 'image/jpeg', 'valid': true},
          {'mediaType': 'photo', 'contentType': 'video/mp4', 'valid': false},
          {'mediaType': 'video', 'contentType': 'video/mp4', 'valid': true},
          {
            'mediaType': 'video',
            'contentType': 'video/quicktime',
            'valid': false,
          },
        ]) ||
        !_wireJsonEquals(transfer?['signed64Cases'], const <Object?>[
          {'decimal': '-9223372036854775808', 'valid': true},
          {'decimal': '9223372036854775807', 'valid': true},
          {'decimal': '-9223372036854775809', 'valid': false},
          {'decimal': '9223372036854775808', 'valid': false},
        ])) {
      errors.add('$path transfer 必须固定 MIME 与 signed-64 边界 vectors');
    }
    for (final key in const {
      'maxFileBytes',
      'ttlSeconds',
      'maxActiveExportsPerEngineAttachment',
      'maxActiveBytesPerEngineAttachment',
      'releaseTombstoneSeconds',
      'maxReleaseTombstones',
    }) {
      if (goldenLimits?[key] != wireLimits?[key]) {
        errors.add('$path transfer limit $key 与 Wire Contract 漂移');
      }
    }

    List<Object?> normalizedUriCases(Object? value, String label) => <Object?>[
      for (final item
          in _capabilityObjectList(value, label) ??
              const <Map<String, Object?>>[])
        {'id': item['id'], 'uri': item['uri'], 'valid': item['valid']},
    ];
    final goldenUriCases = normalizedUriCases(
      transfer?['fileUriCases'],
      '$path transfer.fileUriCases',
    );
    final contractUriCases = normalizedUriCases(
      wireTransfer?['fileUriGoldenVectors'],
      '$path Wire fileUriGoldenVectors',
    );
    if (!_wireJsonEquals(goldenUriCases, contractUriCases) ||
        !_wireJsonEquals(transfer?['fileUriLengthCases'], const <Object?>[
          {'totalLength': 4096, 'valid': true},
          {'totalLength': 4097, 'valid': false},
        ])) {
      errors.add('$path file URI vectors 必须与 Wire Contract 和 4096 边界一致');
    }

    final lifecycle = _capabilityObject(golden['lifecycle'], '$path lifecycle');
    if (!_wireJsonEquals(lifecycle?['cleanupOrder'], const [
          'import_store_commit',
          'release_transfer',
          'release_source_lease',
        ]) ||
        lifecycle?['lateCompletion'] != 'cleanup_without_delivery' ||
        lifecycle?['engineDetach'] !=
            'delete_transfer_before_boundary_completion' ||
        lifecycle?['releaseAfterTombstone'] != 'idempotent_success') {
      errors.add('$path lifecycle 必须固定 Store commit 后 transfer/source 清理顺序');
    }
    final redaction = _capabilityObject(golden['redaction'], '$path redaction');
    final forbiddenKeys = _capabilityStringSet(
      redaction?['forbiddenPersistentKeys'],
      '$path redaction.forbiddenPersistentKeys',
    );
    if (forbiddenKeys == null ||
        !_sameStringSet(forbiddenKeys, const {
          'fileUri',
          'mediaHandle',
          'exportHandle',
          'absolutePath',
        }) ||
        redaction?['failureDetailsMayContainLocator'] != false ||
        redaction?['logsMayContainLocator'] != false) {
      errors.add('$path redaction 必须拒绝 locator/handle 持久化与日志泄漏');
    }
  }

  void _validateMediaCaptureIntegrationHost() {
    const pubspecPath = 'app/apps/demo/pubspec.yaml';
    const plistPath = 'app/apps/demo/ios/Runner/Info.plist';
    const projectPath = 'app/apps/demo/ios/Runner.xcodeproj/project.pbxproj';
    const appDelegatePath = 'app/apps/demo/ios/Runner/AppDelegate.swift';
    const ignorePath = 'app/apps/demo/ios/.gitignore';
    const androidManifestPath =
        'app/apps/demo/android/app/src/main/AndroidManifest.xml';
    const androidActivityPath =
        'app/apps/demo/android/app/src/main/kotlin/com/example/demo_app/MainActivity.kt';

    final pubspec = _file(pubspecPath);
    if (!pubspec.existsSync()) {
      errors.add('缺少 Demo Host pubspec：$pubspecPath');
    } else {
      try {
        final value = loadYaml(pubspec.readAsStringSync());
        if (value is! YamlMap ||
            value['flutter'] is! YamlMap ||
            (value['flutter'] as YamlMap)['config'] is! YamlMap ||
            ((value['flutter'] as YamlMap)['config']
                    as YamlMap)['enable-swift-package-manager'] !=
                true) {
          errors.add('$pubspecPath 必须启用项目级 Flutter Swift Package Manager');
        }
      } on YamlException catch (error) {
        errors.add('$pubspecPath YAML 无效：${error.message}');
      }
    }

    final plist = _file(plistPath);
    if (!plist.existsSync()) {
      errors.add('缺少 Demo Host Info.plist：$plistPath');
    } else {
      try {
        final document = XmlDocument.parse(plist.readAsStringSync());
        final plistElements = document.findAllElements('plist').toList();
        final dictionaries = plistElements.length == 1
            ? plistElements.single.children
                  .whereType<XmlElement>()
                  .where((element) => element.name.local == 'dict')
                  .toList()
            : const <XmlElement>[];
        if (dictionaries.length != 1) {
          errors.add('$plistPath 必须包含唯一的 plist/dict 根节点');
        } else {
          final entries = dictionaries.single.children
              .whereType<XmlElement>()
              .toList();
          for (final key in const [
            'NSCameraUsageDescription',
            'NSMicrophoneUsageDescription',
          ]) {
            final indexes = <int>[
              for (var index = 0; index < entries.length; index += 1)
                if (entries[index].name.local == 'key' &&
                    entries[index].innerText == key)
                  index,
            ];
            final valid =
                indexes.length == 1 &&
                indexes.single + 1 < entries.length &&
                entries[indexes.single + 1].name.local == 'string' &&
                entries[indexes.single + 1].innerText.trim().isNotEmpty;
            if (!valid) {
              errors.add('$plistPath 必须精确声明一个非空 String $key');
            }
          }
        }
      } on XmlParserException catch (error) {
        errors.add('$plistPath XML 无效：${error.message}');
      }
    }

    final project = _file(projectPath);
    final projectContent = project.existsSync()
        ? project.readAsStringSync()
        : '';
    for (final required in const [
      'FlutterGeneratedPluginSwiftPackage in Frameworks',
      'XCLocalSwiftPackageReference "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"',
      'productName = FlutterGeneratedPluginSwiftPackage;',
    ]) {
      if (!projectContent.contains(required)) {
        errors.add('$projectPath 缺少真实 Runner SwiftPM 接线：$required');
      }
    }
    if (RegExp(
      r'/(Users|home)/|Flutter\.xcframework',
    ).hasMatch(projectContent)) {
      errors.add('$projectPath 不得包含本机绝对路径或 Flutter binary 手工接线');
    }

    final appDelegate = _file(appDelegatePath);
    final appDelegateContent = appDelegate.existsSync()
        ? appDelegate.readAsStringSync()
        : '';
    if (RegExp(
          r'GeneratedPluginRegistrant\.register\(with: self\)',
        ).allMatches(appDelegateContent).length !=
        1) {
      errors.add('$appDelegatePath 必须只使用标准 GeneratedPluginRegistrant 装配');
    }
    for (final forbidden in const [
      'MethodChannel',
      'fileUri',
      'mediaHandle',
      'exportHandle',
      'MediaCaptureCore',
    ]) {
      if (appDelegateContent.contains(forbidden)) {
        errors.add('$appDelegatePath 不得处理 Media Capture 状态、Wire 或 locator');
      }
    }

    final ignore = _file(ignorePath);
    if (!ignore.existsSync() ||
        !ignore.readAsStringSync().contains('Flutter/ephemeral/')) {
      errors.add('$ignorePath 必须排除 Flutter ephemeral package');
    }

    final androidManifest = _file(androidManifestPath);
    final androidManifestContent = androidManifest.existsSync()
        ? androidManifest.readAsStringSync()
        : '';
    for (final permission in const [
      'android.permission.CAMERA',
      'android.permission.RECORD_AUDIO',
    ]) {
      if (RegExp(
            RegExp.escape(permission),
          ).allMatches(androidManifestContent).length !=
          1) {
        errors.add('$androidManifestPath 必须精确声明一个 $permission');
      }
    }
    if (RegExp(
      r'READ_EXTERNAL_STORAGE|WRITE_EXTERNAL_STORAGE|READ_MEDIA_',
    ).hasMatch(androidManifestContent)) {
      errors.add('$androidManifestPath 不得为 Media Capture 增加共享存储权限');
    }
    final androidActivity = _file(androidActivityPath);
    final activityContent = androidActivity.existsSync()
        ? androidActivity.readAsStringSync()
        : '';
    if (!activityContent.contains('class MainActivity : FlutterActivity()') ||
        RegExp(
          r'MethodChannel|fileUri|mediaHandle|exportHandle|MediaCapture',
        ).hasMatch(activityContent)) {
      errors.add('$androidActivityPath 必须保持纯 FlutterActivity Host 装配边界');
    }

    final makefile = _file('Makefile');
    final makefileContent = makefile.existsSync()
        ? makefile.readAsStringSync()
        : '';
    for (final required in const [
      'media-capture-android:\n\tbash scripts/quality/media-capture-android.sh',
      'media-capture-ios:\n\tbash scripts/quality/media-capture-ios.sh',
    ]) {
      if (!makefileContent.contains(required)) {
        errors.add('Makefile 缺少独立 Media Capture 平台门禁');
      }
    }
  }

  void _validateWireSchema(Map<String, Object?> schema, String path) {
    const expectedDigest =
        '36aed12b1c066d05e4434736cc90a6828c5cfc2e65459f718567ccd55ed11e49';
    if (calculateImplementationDigest(root, [path]) != expectedDigest) {
      errors.add('$path 的完整 Version 3 Schema 摘要不匹配');
    }
    _validateCapabilityExactKeys(schema, const {
      r'$schema',
      r'$id',
      'title',
      'description',
      'type',
      'additionalProperties',
      'required',
      'properties',
      r'$defs',
    }, '$path 根节点');
    if (schema[r'$schema'] != 'https://json-schema.org/draft/2020-12/schema' ||
        schema[r'$id'] != 'urn:flutter-ai-harness:schema:bridge-wire:2') {
      errors.add('$path 必须使用固定 Draft 2020-12 Schema 与稳定 \$id');
    }
    if (schema['type'] != 'object' || schema['additionalProperties'] != false) {
      errors.add('$path 根节点必须拒绝未知字段');
    }
    const fields = {
      r'$schema',
      'contractId',
      'wireVersion',
      'capability',
      'payloadKeyStyle',
      'channels',
      'fieldMappings',
      'transportConstraints',
      'payloads',
      'failurePayloads',
      'methods',
      'failureDelivery',
      'events',
      'asyncFailures',
      'errors',
      'errorDetailFields',
      'coverage',
      'platform',
      'lifecycle',
      'security',
      'changeLog',
    };
    const propertiesFields = {...fields, 'transferStore'};
    final required = _capabilityStringSet(schema['required'], '$path required');
    final properties = _capabilityObject(
      schema['properties'],
      '$path properties',
    );
    if (required != null && !_sameStringSet(required, fields)) {
      errors.add('$path required 必须精确声明 Wire 顶层字段');
    }
    if (properties != null &&
        !_sameStringSet(properties.keys.toSet(), propertiesFields)) {
      errors.add('$path properties 必须精确声明 Wire 顶层字段');
    }
    final definitions = _capabilityObject(schema[r'$defs'], '$path \$defs');
    final fieldMapping = definitions == null
        ? null
        : _capabilityObject(definitions['fieldMapping'], '$path fieldMapping');
    final fieldMappingProperties = _capabilityObject(
      fieldMapping?['properties'],
      '$path fieldMapping.properties',
    );
    final wireType = _capabilityObject(
      fieldMappingProperties?['wireType'],
      '$path fieldMapping.wireType',
    );
    final wireTypes = _capabilityStringSet(
      wireType?['enum'],
      '$path fieldMapping.wireType.enum',
    );
    if (wireTypes == null ||
        !_sameStringSet(wireTypes, const {
          'bool',
          'bytes',
          'double',
          'int',
          'string',
          'list_bool',
          'list_double',
          'list_int',
          'list_string',
        })) {
      errors.add('$path Base field mapping 必须声明受支持的 Channel bytes 类型');
    }
    final method = definitions == null
        ? null
        : _capabilityObject(definitions['method'], '$path method');
    final methodVariants = _capabilityObjectList(
      method?['oneOf'],
      '$path method.oneOf',
    );
    final variantRefs = methodVariants
        ?.map((entry) => entry[r'$ref'])
        .whereType<String>()
        .toSet();
    if (variantRefs == null ||
        !_sameStringSet(variantRefs, const {
          '#/\$defs/directMethod',
          '#/\$defs/adapterMethod',
          '#/\$defs/presentationMethod',
        }) ||
        definitions?['directMethod'] is! Map<String, Object?> ||
        definitions?['adapterMethod'] is! Map<String, Object?> ||
        definitions?['presentationMethod'] is! Map<String, Object?> ||
        definitions?['presentationPolicy'] is! Map<String, Object?> ||
        definitions?['presentationSlotPolicy'] is! Map<String, Object?> ||
        definitions?['ownerLifecyclePolicy'] is! Map<String, Object?> ||
        definitions?['presentationTerminalOutcome'] is! Map<String, Object?>) {
      errors.add(
        '$path Base method 必须通用地区分 direct、adapter operation 与 presentation',
      );
    }
    final coverage = definitions == null
        ? null
        : _capabilityObject(definitions['coverage'], '$path coverage');
    final coverageRequired = _capabilityStringSet(
      coverage?['required'],
      '$path coverage.required',
    );
    if (coverageRequired != null &&
        !_sameStringSet(coverageRequired, const {
          'operations',
          'results',
          'events',
          'failures',
          'resources',
          'ownershipScopes',
          'nativeInputs',
          'nativeArtifacts',
        })) {
      errors.add(
        '$path Base coverage 必须包含 resource、ownership scope 与 Native artifact 类别',
      );
    }
    final nativeArtifactCoverage = definitions == null
        ? null
        : _capabilityObject(
            definitions['nativeArtifactCoverageEntry'],
            '$path nativeArtifactCoverageEntry',
          );
    final nativeInputCoverage = definitions == null
        ? null
        : _capabilityObject(
            definitions['nativeInputCoverageEntry'],
            '$path nativeInputCoverageEntry',
          );
    if (nativeInputCoverage == null) {
      errors.add('$path Base coverage 必须结构化描述 Native-only input binding');
    }
    if (nativeArtifactCoverage == null) {
      errors.add('$path Base coverage 必须用领域中立结构描述 Native-only artifact');
    } else {
      _validateCapabilityExactKeys(nativeArtifactCoverage, const {
        'type',
        'additionalProperties',
        'required',
        'properties',
      }, '$path nativeArtifactCoverageEntry');
      final required = _capabilityStringSet(
        nativeArtifactCoverage['required'],
        '$path nativeArtifactCoverageEntry.required',
      );
      final properties = _capabilityObject(
        nativeArtifactCoverage['properties'],
        '$path nativeArtifactCoverageEntry.properties',
      );
      const expectedFields = {
        'capabilityId',
        'artifactKind',
        'ownerPolicyId',
        'platform',
        'disposition',
        'wireId',
        'reason',
      };
      if (nativeArtifactCoverage['type'] != 'object' ||
          nativeArtifactCoverage['additionalProperties'] != false ||
          required == null ||
          !_sameStringSet(required, expectedFields) ||
          properties == null ||
          !_sameStringSet(properties.keys.toSet(), expectedFields)) {
        errors.add('$path Base Native artifact coverage 字段必须闭合');
      }
      final wireIdSchema = _capabilityObject(
        properties?['wireId'],
        '$path nativeArtifactCoverageEntry.wireId',
      );
      if (!_wireJsonEquals(wireIdSchema, const {'type': 'null'})) {
        errors.add('$path Base Native artifact wireId 必须固定为 null');
      }
      final reasonSchema = _capabilityObject(
        properties?['reason'],
        '$path nativeArtifactCoverageEntry.reason',
      );
      if (!_wireJsonEquals(reasonSchema, const {
        r'$ref': r'#/$defs/nonEmptyString',
      })) {
        errors.add('$path Base Native artifact reason 必须引用 nonEmptyString');
      }
    }
    final lifecycle = definitions == null
        ? null
        : _capabilityObject(
            definitions['lifecycleContract'],
            '$path lifecycleContract',
          );
    final lifecycleRequired = _capabilityStringSet(
      lifecycle?['required'],
      '$path lifecycleContract.required',
    );
    if (lifecycleRequired != null &&
        !_sameStringSet(lifecycleRequired, const {
          'requestEnvelope',
          'resultEnvelope',
          'methodCompletion',
          'callbackThread',
        })) {
      errors.add('$path Base lifecycle 不得强制 Event/Failure/Session/资源边界');
    }
    final boundary = definitions == null
        ? null
        : _capabilityObject(
            definitions['boundaryPolicy'],
            '$path boundaryPolicy',
          );
    final boundaryRequired = _capabilityStringSet(
      boundary?['required'],
      '$path boundaryPolicy.required',
    );
    if (boundaryRequired != null &&
        !_sameStringSet(boundaryRequired, const {
          'id',
          'description',
          'actions',
        })) {
      errors.add('$path Base boundary 只能要求通用 ID、说明和 action 集合');
    }
  }

  void _validateMediaCaptureWire(
    Map<String, Object?> wire,
    Map<String, Object?> capability,
    String path,
  ) {
    _validateCapabilityExactKeys(wire, const {
      r'$schema',
      'contractId',
      'wireVersion',
      'capability',
      'payloadKeyStyle',
      'channels',
      'fieldMappings',
      'transportConstraints',
      'payloads',
      'failurePayloads',
      'methods',
      'failureDelivery',
      'events',
      'asyncFailures',
      'errors',
      'errorDetailFields',
      'coverage',
      'platform',
      'lifecycle',
      'transferStore',
      'security',
      'changeLog',
    }, '$path 根节点');
    if (wire[r'$schema'] != './wire.schema.json' ||
        wire['contractId'] != 'media_capture_wire') {
      errors.add('$path 必须引用固定 Wire Schema 并声明 media_capture_wire');
    }
    if (wire['wireVersion'] != 3 || wire.containsKey('capabilityVersion')) {
      errors.add('$path 必须独立声明 wireVersion 3，且不得用 capabilityVersion 替代');
    }
    if (wire['payloadKeyStyle'] != 'lower_camel_case') {
      errors.add('$path Payload key 必须统一使用 lowerCamelCase');
    }
    final wireCapability = _validateWireCapabilityReference(
      wire['capability'],
      wire['wireVersion'],
      capability,
      path,
    );
    _validateWireChannels(wire['channels'], path);

    final v3Transport = _validateMediaCaptureWireTransportProjection(
      wire,
      wireCapability,
      '$path Capability V4 transfer projection',
    );
    _validateWireTransferStore(wire['transferStore'], path);
    final v3Capability = _buildMediaCaptureV3TransportProjection(
      wireCapability,
      path,
    );
    _validateMediaCaptureV3ProjectionIsolation(v3Capability, path);
    final v2Projection = _buildMediaCaptureV2TransportProjection(
      wire,
      v3Capability,
      path,
    );
    _validateMediaCaptureWireTransportProjection(
      v2Projection.wire,
      v2Projection.capability,
      '$path Capability V2 transport projection',
    );
    _validateWirePlatform(wire['platform'], path);
    _validateWireLifecycle(
      wire['lifecycle'],
      wireCapability,
      v3Transport.methods,
      path,
    );
    _validateWireSecurity(wire['security'], v3Transport.fieldMappings, path);
    _validateWireChangeLog(wire['changeLog'], path);
  }

  Map<String, Object?> _buildMediaCaptureV3TransportProjection(
    Map<String, Object?> capability,
    String path,
  ) {
    final projection =
        jsonDecode(jsonEncode(capability)) as Map<String, Object?>;

    void removeIds(Map<String, Object?> owner, String key, Set<String> ids) {
      final entries = _capabilityObjectList(
        owner[key],
        '$path Capability V4 additive transport delta $key',
      );
      owner[key] = <Object?>[
        for (final entry in entries ?? const <Map<String, Object?>>[])
          if (!ids.contains(entry['id'])) entry,
      ];
    }

    removeIds(projection, 'operation', const {'copy_confirmed_media_to_sink'});
    removeIds(projection, 'field', const {
      'media_copy_sink',
      'media_export_max_length',
    });
    removeIds(projection, 'request', const {'media_export_request'});
    removeIds(projection, 'result', const {'media_export_result'});
    removeIds(projection, 'failure', const {
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
    });
    final lifecycle = _capabilityObject(
      projection['lifecycle'],
      '$path Capability V4 additive transport delta lifecycle',
    );
    removeIds(lifecycle ?? <String, Object?>{}, 'rules', const {
      'media_export_cancel_requested',
      'media_export_deadline_elapsed',
      'media_export_aborted',
      'media_export_committed',
    });
    final stateMachines = _capabilityObjectList(
      projection['stateMachines'],
      '$path Capability V4 additive transport delta stateMachines',
    );
    for (final machine in stateMachines ?? const <Map<String, Object?>>[]) {
      final transitions = _capabilityObjectList(
        machine['transitions'],
        '$path Capability V4 additive transport delta transitions',
      );
      machine['transitions'] = <Object?>[
        for (final transition in transitions ?? const <Map<String, Object?>>[])
          if (transition['triggerId'] != 'copy_confirmed_media_to_sink')
            transition,
      ];
    }
    final resourcePolicy = _capabilityObject(
      projection['resourcePolicy'],
      '$path Capability V4 additive transport delta resourcePolicy',
    );
    removeIds(resourcePolicy ?? <String, Object?>{}, 'resources', const {
      'media_export_job',
      'media_export_buffer',
    });
    removeIds(resourcePolicy ?? <String, Object?>{}, 'ownershipPhases', const {
      'media_export_job_scope',
      'media_export_buffer_scope',
    });
    removeIds(resourcePolicy ?? <String, Object?>{}, 'cleanup', const {
      'media_export_release_cleanup',
      'media_export_expiry_cleanup',
      'media_export_cancel_cleanup',
      'media_export_timeout_cleanup',
      'media_export_failure_cleanup',
      'media_export_core_close_cleanup',
      'media_export_success_finalization',
    });
    removeIds(resourcePolicy ?? <String, Object?>{}, 'privacy', const {
      'media_export_sink_native_only',
      'media_export_no_storage_identity',
      'media_export_redacted_diagnostics',
    });
    resourcePolicy?['streamingCopies'] = <Object?>[];
    projection['capabilityVersion'] = 3;
    final history = _capabilityObjectList(
      projection['versionHistory'],
      '$path Capability V4 additive transport delta versionHistory',
    );
    projection['versionHistory'] = <Object?>[
      for (final entry in history ?? const <Map<String, Object?>>[])
        if (entry['version'] != 4) entry,
    ];
    return projection;
  }

  void _validateMediaCaptureV3ProjectionIsolation(
    Map<String, Object?> projection,
    String path,
  ) {
    final projectionPath = '$path Capability V3 transport projection';

    Set<String> ids(Object? value, String label) =>
        (_capabilityObjectList(value, '$projectionPath $label') ??
                const <Map<String, Object?>>[])
            .map((entry) => entry['id'])
            .whereType<String>()
            .toSet();

    void rejectIds(Object? value, Set<String> forbidden, String label) {
      final leaked = ids(value, label).intersection(forbidden);
      if (leaked.isNotEmpty) {
        errors.add(
          '$projectionPath 泄漏 V4-only $label：${(leaked.toList()..sort()).join(', ')}',
        );
      }
    }

    if (projection['capabilityVersion'] != 3) {
      errors.add('$projectionPath 必须降投影为 capabilityVersion 3');
    }
    rejectIds(projection['operation'], const {
      'copy_confirmed_media_to_sink',
    }, 'operation');
    rejectIds(projection['field'], const {
      'media_copy_sink',
      'media_export_max_length',
    }, 'field');
    rejectIds(projection['request'], const {'media_export_request'}, 'request');
    rejectIds(projection['result'], const {'media_export_result'}, 'result');
    rejectIds(projection['failure'], const {
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
    }, 'failure');

    final lifecycle = _capabilityObject(
      projection['lifecycle'],
      '$projectionPath lifecycle',
    );
    rejectIds(lifecycle?['rules'], const {
      'media_export_cancel_requested',
      'media_export_deadline_elapsed',
      'media_export_aborted',
      'media_export_committed',
    }, 'lifecycle rule');

    for (final machine
        in _capabilityObjectList(
              projection['stateMachines'],
              '$projectionPath stateMachines',
            ) ??
            const <Map<String, Object?>>[]) {
      final transitions = _capabilityObjectList(
        machine['transitions'],
        '$projectionPath transitions',
      );
      if ((transitions ?? const <Map<String, Object?>>[]).any(
        (transition) =>
            transition['triggerId'] == 'copy_confirmed_media_to_sink',
      )) {
        errors.add('$projectionPath 泄漏 V4-only transition');
      }
    }

    final resourcePolicy = _capabilityObject(
      projection['resourcePolicy'],
      '$projectionPath resourcePolicy',
    );
    rejectIds(resourcePolicy?['resources'], const {
      'media_export_job',
      'media_export_buffer',
    }, 'resource');
    rejectIds(resourcePolicy?['ownershipPhases'], const {
      'media_export_job_scope',
      'media_export_buffer_scope',
    }, 'ownership phase');
    rejectIds(resourcePolicy?['cleanup'], const {
      'media_export_release_cleanup',
      'media_export_expiry_cleanup',
      'media_export_cancel_cleanup',
      'media_export_timeout_cleanup',
      'media_export_failure_cleanup',
      'media_export_core_close_cleanup',
      'media_export_success_finalization',
    }, 'cleanup');
    rejectIds(resourcePolicy?['privacy'], const {
      'media_export_sink_native_only',
      'media_export_no_storage_identity',
      'media_export_redacted_diagnostics',
    }, 'privacy policy');
    final streamingCopies = _capabilityObjectList(
      resourcePolicy?['streamingCopies'],
      '$projectionPath streamingCopies',
    );
    if (streamingCopies != null && streamingCopies.isNotEmpty) {
      errors.add('$projectionPath 泄漏 V4-only streaming copy policy');
    }

    final history = _capabilityObjectList(
      projection['versionHistory'],
      '$projectionPath versionHistory',
    );
    if ((history ?? const <Map<String, Object?>>[]).any(
      (entry) => entry['version'] == 4,
    )) {
      errors.add('$projectionPath 泄漏 V4 history');
    }
  }

  ({
    Map<String, Map<String, Object?>> fieldMappings,
    Map<String, Map<String, Object?>> methods,
  })
  _validateMediaCaptureWireTransportProjection(
    Map<String, Object?> wire,
    Map<String, Object?> capability,
    String path,
  ) {
    final capabilityFields = _wireObjectsById(
      capability['field'],
      'id',
      '$path Capability field',
    );
    final fieldMappings = _validateWireFieldMappings(
      wire['fieldMappings'],
      capabilityFields,
      path,
    );
    _validateWireTransportConstraints(
      wire['transportConstraints'],
      capability,
      path,
    );
    final payloads = _validateWirePayloads(
      wire['payloads'],
      capability,
      fieldMappings,
      path,
    );
    final failurePayloads = _validateWireFailurePayloads(
      wire['failurePayloads'],
      capability,
      fieldMappings,
      path,
    );
    final failureDelivery = _validateWireFailureDelivery(
      wire['failureDelivery'],
      capability,
      path,
    );
    final methods = _validateWireMethods(
      wire['methods'],
      capability,
      payloads,
      failureDelivery,
      path,
    );
    final events = _validateWireEvents(
      wire['events'],
      capability,
      payloads,
      path,
    );
    _validateWireAsyncFailures(
      wire['asyncFailures'],
      capability,
      failurePayloads,
      path,
    );
    final errorDetailFields = _validateWireErrorDetailFields(
      wire['errorDetailFields'],
      capability,
      fieldMappings,
      methods,
      path,
    );
    final wireErrors = _validateWireErrors(
      wire['errors'],
      capability,
      errorDetailFields,
      path,
    );
    _validateWireCoverage(
      wire['coverage'],
      capability,
      methods,
      events,
      payloads,
      wireErrors,
      path,
    );
    return (fieldMappings: fieldMappings, methods: methods);
  }

  ({Map<String, Object?> wire, Map<String, Object?> capability})
  _buildMediaCaptureV2TransportProjection(
    Map<String, Object?> wire,
    Map<String, Object?> capability,
    String path,
  ) {
    const surfacePolicyIds = {
      'live_platform_render_surface_policy',
      'unconfirmed_platform_render_surface_policy',
    };
    const surfaceResourceIds = {
      'live_platform_render_surface',
      'unconfirmed_platform_render_surface',
    };
    const surfaceOwnerScopeIds = {
      'live_render_surface_owner_scope',
      'unconfirmed_render_surface_owner_scope',
    };
    const nativeArtifactCount = 53;

    final capabilityProjection =
        jsonDecode(jsonEncode(capability)) as Map<String, Object?>;
    final wireProjection = jsonDecode(jsonEncode(wire)) as Map<String, Object?>;
    void removeWireEntries(String key, String idKey, Set<String> removedIds) {
      final entries = _capabilityObjectList(
        wireProjection[key],
        '$path Wire V3 transfer projection $key',
      );
      wireProjection[key] = <Object?>[
        for (final entry in entries ?? const <Map<String, Object?>>[])
          if (!removedIds.contains(entry[idKey])) entry,
      ];
    }

    wireProjection['wireVersion'] = 2;
    final wireCapability = _capabilityObject(
      wireProjection['capability'],
      '$path Wire V2 history projection capability',
    );
    wireCapability?['compatibleCapabilityVersions'] = <Object?>[2, 3];
    wireProjection.remove('transferStore');
    removeWireEntries('fieldMappings', 'capabilityFieldId', const {
      'content_type',
      'export_handle',
      'file_uri',
      'expires_at',
      'integrity_sha256',
      'presentation_request_id',
    });
    final transportConstraints = _capabilityObject(
      wireProjection['transportConstraints'],
      '$path Wire V2 history projection transportConstraints',
    );
    final opaqueHandles = _capabilityObjectList(
      transportConstraints?['opaqueHandles'],
      '$path Wire V2 history projection opaqueHandles',
    );
    transportConstraints?['opaqueHandles'] = <Object?>[
      for (final entry in opaqueHandles ?? const <Map<String, Object?>>[])
        if (entry['capabilityFieldId'] != 'export_handle') entry,
    ];
    removeWireEntries('payloads', 'id', const {
      'materialize_media_resource_request_payload',
      'materialized_media_result_payload',
      'release_materialized_media_request_payload',
      'materialized_media_released_result_payload',
      'dismiss_capture_flow_request_payload',
      'capture_flow_dismissed_result_payload',
    });
    removeWireEntries('methods', 'id', const {
      'materialize_media_resource',
      'release_materialized_media',
      'dismiss_capture_flow',
    });
    removeWireEntries('failureDelivery', 'capabilityOperationId', const {
      'copy_confirmed_media_to_sink',
    });
    removeWireEntries('errors', 'code', const {
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
      'transfer_store_overloaded',
      'transfer_store_unavailable',
      'materialized_media_invalid',
    });
    final wireLifecycle = _capabilityObject(
      wireProjection['lifecycle'],
      '$path Wire V2 history projection lifecycle',
    );
    void removeLifecycleEntries(String key, String idKey, Set<String> ids) {
      final entries = _capabilityObjectList(
        wireLifecycle?[key],
        '$path Wire V2 history projection lifecycle.$key',
      );
      wireLifecycle?[key] = <Object?>[
        for (final entry in entries ?? const <Map<String, Object?>>[])
          if (!ids.contains(entry[idKey])) entry,
      ];
    }

    removeLifecycleEntries('resourceAdoptionPolicies', 'id', const {
      'materialized_media_resource_adoption',
    });
    removeLifecycleEntries('resultCompletionPolicies', 'resultType', const {
      'materialized_media_resource',
      'materialized_media_released',
    });
    removeLifecycleEntries('lateResultPolicies', 'resultType', const {
      'materialized_media_resource',
      'materialized_media_released',
    });
    final boundaries = _capabilityObjectList(
      wireLifecycle?['boundaries'],
      '$path Wire V2 history projection lifecycle.boundaries',
    );
    for (final boundary in boundaries ?? const <Map<String, Object?>>[]) {
      final actions = _capabilityObjectList(
        boundary['actions'],
        '$path Wire V2 history projection boundary actions',
      );
      boundary['actions'] = <Object?>[
        for (final action in actions ?? const <Map<String, Object?>>[])
          if (!const {
            'active_transfer_exports',
            'inflight_transfer_exports',
          }.contains(action['resourceId']))
            action,
      ];
      final remaining = _capabilityObjectList(
        boundary['actions'],
        '$path Wire V2 history projection boundary actions',
      );
      for (var index = 0; index < (remaining?.length ?? 0); index += 1) {
        remaining![index]['order'] = index + 1;
      }
    }
    final errorDetails = _wireObjectsByWireKey(
      wireProjection['errorDetailFields'],
      'key',
      '$path Wire V2 history projection errorDetailFields',
    );
    final capacity = errorDetails['capacity'];
    final capacityValues =
        _capabilityStringSet(
          capacity?['enumValues'],
          '$path Wire V2 history projection capacity enum',
        ) ??
        <String>{};
    capacity?['enumValues'] = <Object?>[
      for (final value in capacityValues.toList()..sort())
        if (!const {
          'active_exports',
          'active_export_bytes',
          'release_tombstones',
        }.contains(value))
          value,
    ];
    void removeErrorDetailValues(String key, Set<String> removedValues) {
      final detail = errorDetails[key];
      final values =
          _capabilityStringSet(
            detail?['enumValues'],
            '$path Wire V2 history projection $key enum',
          ) ??
          <String>{};
      detail?['enumValues'] = <Object?>[
        for (final value in values.toList()..sort())
          if (!removedValues.contains(value)) value,
      ];
    }

    removeErrorDetailValues('operation', const {
      'materialize_media_resource',
      'release_materialized_media',
      'dismiss_capture_flow',
    });
    removeErrorDetailValues('capabilityFailureId', const {
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
    });
    removeErrorDetailValues('field', const {
      'contentType',
      'exportHandle',
      'fileUri',
      'expiresAt',
      'integritySha256',
      'presentationRequestId',
    });
    final coverage = _capabilityObject(
      wireProjection['coverage'],
      '$path Capability V2 coverage projection',
    );
    void removeCoverage(String key, Set<String> removedIds) {
      final entries = _capabilityObjectList(
        coverage?[key],
        '$path Wire V2 coverage projection $key',
      );
      coverage?[key] = <Object?>[
        for (final entry in entries ?? const <Map<String, Object?>>[])
          if (!removedIds.contains(entry['capabilityId'])) entry,
      ];
    }

    removeCoverage('operations', const {'copy_confirmed_media_to_sink'});
    removeCoverage('results', const {'media_export_result'});
    removeCoverage('failures', const {
      'media_export_conflict',
      'media_export_overloaded',
      'media_export_too_large',
      'media_export_sink_rejected',
      'media_export_read_failed',
      'media_export_write_failed',
      'media_export_cancelled',
      'media_export_timed_out',
    });
    removeCoverage('resources', const {
      'media_export_job',
      'media_export_buffer',
    });
    removeCoverage('ownershipScopes', const {
      'media_export_job_scope',
      'media_export_buffer_scope',
    });
    removeCoverage('nativeInputs', const {
      'media_copy_sink',
      'media_export_max_length',
    });
    final security = _capabilityObject(
      wireProjection['security'],
      '$path Wire V2 history projection security',
    );
    void removeSecurityEntries(String key, Set<String> removedIds) {
      final entries = _capabilityObjectList(
        security?[key],
        '$path Wire V2 history projection security.$key',
      );
      security?[key] = <Object?>[
        for (final entry in entries ?? const <Map<String, Object?>>[])
          if (!removedIds.contains(entry['id'])) entry,
      ];
    }

    removeSecurityEntries('dataClassifications', const {
      'transfer_locator',
      'transfer_metadata',
      'presentation_control',
    });
    removeSecurityEntries('policies', const {
      'caller_path_forbidden',
      'scoped_transfer_file_uri_only',
      'transfer_locator_redacted',
      'transfer_capacity_bounded',
      'transfer_cleanup_exactly_once',
      'source_media_release_order',
      'no_raw_media_channel_transfer',
    });
    final policies = _capabilityObjectList(
      security?['policies'],
      '$path Wire V2 history projection security.policies',
    );
    if (policies != null &&
        !policies.any((entry) => entry['id'] == 'path_transfer_forbidden')) {
      policies.add({
        'id': 'path_transfer_forbidden',
        'description': 'Paths and arbitrary URIs never cross the Channel.',
      });
    }
    final changeLog = _capabilityObjectList(
      wireProjection['changeLog'],
      '$path Wire V2 history projection changeLog',
    );
    wireProjection['changeLog'] = <Object?>[
      for (final entry in changeLog ?? const <Map<String, Object?>>[])
        if (entry['wireVersion'] != 3) entry,
    ];
    final resourcePolicy = _capabilityObject(
      capabilityProjection['resourcePolicy'],
      '$path Capability V3 additive transport delta resourcePolicy',
    );
    final renderSurfaces = _capabilityObjectList(
      resourcePolicy?['renderSurfaces'],
      '$path Capability V3 additive transport delta renderSurfaces',
    );
    final actualSurfacePolicyIds = renderSurfaces
        ?.map((item) => item['id'])
        .whereType<String>()
        .toSet();
    if (actualSurfacePolicyIds == null ||
        !_sameStringSet(actualSurfacePolicyIds, surfacePolicyIds)) {
      errors.add(
        '$path Capability V3 additive transport delta 必须精确包含 2 个 render surface policy',
      );
    }
    resourcePolicy?['renderSurfaces'] = <Object?>[];

    void removeExactEntries(
      Map<String, Object?>? owner,
      String key,
      String idKey,
      Set<String> removedIds,
      String label,
    ) {
      final entries = _capabilityObjectList(owner?[key], '$path $label');
      final presentRemovedIds = entries
          ?.map((item) => item[idKey])
          .whereType<String>()
          .where(removedIds.contains)
          .toSet();
      if (presentRemovedIds == null ||
          !_sameStringSet(presentRemovedIds, removedIds)) {
        errors.add(
          '$path Capability V3 additive transport delta 必须精确包含 ${removedIds.length} 个 $label',
        );
      }
      owner?[key] = <Object?>[
        for (final entry in entries ?? const <Map<String, Object?>>[])
          if (!removedIds.contains(entry[idKey])) entry,
      ];
    }

    removeExactEntries(
      resourcePolicy,
      'resources',
      'id',
      surfaceResourceIds,
      'surface resource',
    );
    removeExactEntries(
      resourcePolicy,
      'ownershipPhases',
      'id',
      surfaceOwnerScopeIds,
      'surface owner scope',
    );
    capabilityProjection['capabilityVersion'] = 2;
    final versionHistory = _capabilityObjectList(
      capabilityProjection['versionHistory'],
      '$path Capability V3 additive transport delta versionHistory',
    );
    capabilityProjection['versionHistory'] = <Object?>[
      for (final entry in versionHistory ?? const <Map<String, Object?>>[])
        if (entry['version'] != 3) entry,
    ];

    removeExactEntries(
      coverage,
      'resources',
      'capabilityId',
      surfaceResourceIds,
      'Wire surface resource coverage',
    );
    removeExactEntries(
      coverage,
      'ownershipScopes',
      'capabilityId',
      surfaceOwnerScopeIds,
      'Wire surface owner scope coverage',
    );
    final nativeArtifacts = _capabilityObjectList(
      coverage?['nativeArtifacts'],
      '$path Capability V3 additive transport delta nativeArtifacts',
    );
    if (nativeArtifacts?.length != nativeArtifactCount) {
      errors.add(
        '$path Capability V3 additive transport delta 必须精确包含 53 个 Native artifact coverage entry',
      );
    }
    coverage?['nativeArtifacts'] = <Object?>[];
    return (wire: wireProjection, capability: capabilityProjection);
  }

  Map<String, Object?> _validateWireCapabilityReference(
    Object? value,
    Object? wireVersion,
    Map<String, Object?> capability,
    String path,
  ) {
    final reference = _capabilityObject(value, '$path capability');
    if (reference == null) {
      return capability;
    }
    _validateCapabilityExactKeys(reference, const {
      'contractId',
      'contractPath',
      'compatibleCapabilityVersions',
    }, '$path capability');
    if (reference['contractId'] != capability['contractId'] ||
        reference['contractPath'] !=
            '../../infrastructure/contracts/media-capture.capability.json') {
      errors.add('$path capability 引用必须指向当前 Media Capture Capability');
    }
    final versionsValue = reference['compatibleCapabilityVersions'];
    if (versionsValue is! List<Object?> ||
        versionsValue.isEmpty ||
        versionsValue.any((item) => item is! int || item < 1) ||
        versionsValue.toSet().length != versionsValue.length) {
      errors.add('$path 必须声明非空且唯一的正整数 Capability 兼容版本');
      return capability;
    }
    final versions = versionsValue.cast<int>().toSet();
    if (wireVersion != 3 ||
        capability['capabilityVersion'] != 4 ||
        !_sameStringSet(versions.map((item) => '$item').toSet(), const {'4'})) {
      errors.add('$path Wire V3 必须精确兼容 Capability V4');
    }
    return capability;
  }

  void _validateWireChannels(Object? value, String path) {
    final channels = _wireObjectsById(value, 'id', '$path channels');
    const expected = {
      'commands': 'method_channel|com.example.media_capture.commands',
      'events': 'event_channel|com.example.media_capture.events',
    };
    if (!_sameStringSet(channels.keys.toSet(), expected.keys.toSet())) {
      errors.add('$path 必须精确声明 commands 与 events Channel');
    }
    for (final entry in channels.entries) {
      _validateCapabilityExactKeys(entry.value, const {
        'id',
        'kind',
        'name',
      }, '$path channel ${entry.key}');
      final signature = '${entry.value['kind']}|${entry.value['name']}';
      if (expected[entry.key] != signature) {
        errors.add('$path channel ${entry.key} 的 kind/name 不匹配');
      }
    }
  }

  Map<String, Map<String, Object?>> _validateWireFieldMappings(
    Object? value,
    Map<String, Map<String, Object?>> capabilityFields,
    String path,
  ) {
    final mappings = _wireObjectsById(
      value,
      'capabilityFieldId',
      '$path fieldMappings',
    );
    final hasTransferExport = capabilityFields.containsKey('media_copy_sink');
    final expectedIds = capabilityFields.keys.toSet()
      ..removeAll(const {
        'read_access',
        'render_target_adapter',
        'owner_generation',
        'attachment_kind',
        'media_copy_sink',
        'media_export_max_length',
      });
    if (!hasTransferExport) {
      expectedIds.remove('content_type');
    } else {
      expectedIds.addAll(const {
        'export_handle',
        'file_uri',
        'expires_at',
        'integrity_sha256',
        'presentation_request_id',
      });
    }
    if (!_sameStringSet(mappings.keys.toSet(), expectedIds)) {
      errors.add('$path fieldMappings 必须精确映射可跨 Channel 的 Capability fields');
    }
    const typeMappings = {
      'boolean': 'bool',
      'bounded_copy': 'bytes',
      'decimal': 'double',
      'enum': 'string',
      'integer': 'int',
      'opaque_id': 'string',
      'string': 'string',
      'string_list': 'list_string',
      'timestamp': 'int',
    };
    const wireOnlyMappings =
        <
          String,
          ({
            String key,
            String wireType,
            bool required,
            bool nullable,
            String format,
            num? minimum,
            num? maximum,
          })
        >{
          'export_handle': (
            key: 'exportHandle',
            wireType: 'string',
            required: true,
            nullable: false,
            format: 'opaque_handle',
            minimum: null,
            maximum: null,
          ),
          'file_uri': (
            key: 'fileUri',
            wireType: 'string',
            required: true,
            nullable: false,
            format: 'canonical_file_uri',
            minimum: null,
            maximum: null,
          ),
          'expires_at': (
            key: 'expiresAt',
            wireType: 'int',
            required: true,
            nullable: false,
            format: 'unix_epoch_millis',
            minimum: 0,
            maximum: null,
          ),
          'integrity_sha256': (
            key: 'integritySha256',
            wireType: 'string',
            required: false,
            nullable: false,
            format: 'lowercase_sha256_hex',
            minimum: null,
            maximum: null,
          ),
          'presentation_request_id': (
            key: 'presentationRequestId',
            wireType: 'string',
            required: true,
            nullable: false,
            format: 'opaque_request_id',
            minimum: null,
            maximum: null,
          ),
        };
    final wireKeys = <String>{};
    for (final entry in mappings.entries) {
      final label = '$path fieldMapping ${entry.key}';
      final mapping = entry.value;
      _validateCapabilityExactKeys(mapping, const {
        'capabilityFieldId',
        'key',
        'wireType',
        'required',
        'nullable',
        'enumValues',
        'validation',
      }, label);
      final capabilityField = capabilityFields[entry.key];
      final wireOnlyField = wireOnlyMappings[entry.key];
      if (capabilityField == null && wireOnlyField == null) {
        errors.add('$label 引用了未知 Capability field');
        continue;
      }
      final key = mapping['key'];
      if (key is! String ||
          !RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(key) ||
          key != (wireOnlyField?.key ?? _wireLowerCamel(entry.key)) ||
          !wireKeys.add(key)) {
        errors.add('$label 必须声明唯一且确定性的 lowerCamelCase key');
      }
      if (wireOnlyField != null) {
        final validation = _capabilityObject(
          mapping['validation'],
          '$label validation',
        );
        if (mapping['wireType'] != wireOnlyField.wireType ||
            mapping['required'] != wireOnlyField.required ||
            mapping['nullable'] != wireOnlyField.nullable ||
            !_wireJsonEquals(mapping['enumValues'], const <Object?>[]) ||
            validation?['format'] != wireOnlyField.format ||
            validation?['minimum'] != wireOnlyField.minimum ||
            validation?['maximum'] != wireOnlyField.maximum ||
            validation?['outOfRangePolicy'] is! String) {
          errors.add('$label 必须闭合声明 Adapter 生成 transfer 字段');
        }
        continue;
      }
      if (mapping['wireType'] != typeMappings[capabilityField!['valueType']] ||
          mapping['required'] != capabilityField['required'] ||
          mapping['nullable'] != capabilityField['nullable'] ||
          !_wireJsonEquals(
            mapping['enumValues'],
            capabilityField['enumValues'],
          ) ||
          !_wireJsonEquals(
            mapping['validation'],
            capabilityField['validation'],
          )) {
        errors.add('$label 必须完整保留 Capability 类型、可选性与 validation');
      }
      final enumValues = _capabilityStringSet(
        mapping['enumValues'],
        '$label enumValues',
      );
      if (enumValues != null &&
          enumValues.any(
            (item) => !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(item),
          )) {
        errors.add('$label enum wire value 必须使用小写 snake_case');
      }
    }
    return mappings;
  }

  void _validateWireTransportConstraints(
    Object? value,
    Map<String, Object?> capability,
    String path,
  ) {
    final constraints = _capabilityObject(value, '$path transportConstraints');
    if (constraints == null) {
      return;
    }
    _validateCapabilityExactKeys(constraints, const {
      'signedInteger',
      'opaqueHandles',
    }, '$path transportConstraints');
    final integer = _capabilityObject(
      constraints['signedInteger'],
      '$path transportConstraints.signedInteger',
    );
    if (integer != null) {
      _validateCapabilityExactKeys(integer, const {
        'wireType',
        'bits',
        'minimum',
        'maximum',
        'inboundOutOfRange',
        'outboundOutOfRange',
      }, '$path transportConstraints.signedInteger');
      if (integer['wireType'] != 'int' ||
          integer['bits'] != 64 ||
          integer['minimum'] is! int ||
          integer['minimum'] != -9223372036854775808 ||
          integer['maximum'] is! int ||
          integer['maximum'] != 9223372036854775807 ||
          integer['inboundOutOfRange'] != 'invalid_wire_payload' ||
          integer['outboundOutOfRange'] != 'wire_encoding_failed') {
        errors.add('$path Wire int 必须使用共同 signed 64-bit 边界');
      }
    }

    final policy = _capabilityObject(
      capability['resourcePolicy'],
      '$path Capability resourcePolicy',
    );
    final handlePolicies = _wireObjectsById(
      policy?['handles'],
      'id',
      '$path Capability handle policies',
    );
    final handles = _wireObjectsById(
      constraints['opaqueHandles'],
      'capabilityFieldId',
      '$path transportConstraints.opaqueHandles',
    );
    final expectedFields = {
      'session_handle',
      'media_handle',
      if (handlePolicies.containsKey('media_export_job_policy'))
        'export_handle',
    };
    if (capability['capabilityVersion'] == 4) {
      expectedFields.add('export_handle');
    }
    if (!_sameStringSet(handles.keys.toSet(), expectedFields)) {
      errors.add('$path 必须约束 Session 与 Media opaque handle');
    }
    for (final entry in handles.entries) {
      final handle = entry.value;
      final label = '$path opaque handle ${entry.key}';
      _validateCapabilityExactKeys(handle, const {
        'capabilityFieldId',
        'capabilityHandlePolicyId',
        'wireType',
        'minLength',
        'maxLength',
        'format',
        'inboundOutOfRange',
        'outboundOutOfRange',
      }, label);
      final expectedPolicyId = '${entry.key}_policy';
      final isExportHandle = entry.key == 'export_handle';
      final capabilityPolicy = handlePolicies[expectedPolicyId];
      if (handle['capabilityHandlePolicyId'] != expectedPolicyId ||
          (!isExportHandle && capabilityPolicy == null) ||
          handle['wireType'] != 'string' ||
          handle['minLength'] != (isExportHandle ? 22 : 1) ||
          handle['maxLength'] !=
              (isExportHandle ? 64 : capabilityPolicy?['maxLength']) ||
          handle['format'] != 'opaque_string' ||
          handle['inboundOutOfRange'] != 'invalid_wire_payload' ||
          handle['outboundOutOfRange'] != 'wire_encoding_failed') {
        errors.add('$label 必须从 Capability/transfer handle policy 派生有界长度');
      }
    }
  }

  Map<String, Map<String, Object?>> _validateWirePayloads(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> fieldMappings,
    String path,
  ) {
    final payloads = _wireObjectsById(value, 'id', '$path payloads');
    final expectedShapes = <String, ({String kind, Set<String> fields})>{};
    const nativeOnlyShapes = {
      'live_preview_attachment_request',
      'live_preview_detach_request',
      'unconfirmed_preview_attachment_request',
      'unconfirmed_preview_detach_request',
      'render_attachment_attached',
      'render_attachment_detached',
      'render_attachment_revoked',
    };
    final hasTransferExport = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operation',
    ).containsKey('copy_confirmed_media_to_sink');
    for (final kind in const ['request', 'result', 'event']) {
      final shapes = _wireObjectsById(
        capability[kind],
        'id',
        '$path Capability $kind',
      );
      for (final shape in shapes.entries) {
        if ((kind == 'result' && shape.key == 'scoped_media_read') ||
            (hasTransferExport &&
                const {
                  'media_export_request',
                  'media_export_result',
                }.contains(shape.key)) ||
            nativeOnlyShapes.contains(shape.key)) {
          continue;
        }
        expectedShapes[shape.key] = (
          kind: kind,
          fields:
              _capabilityStringSet(
                shape.value['fieldIds'],
                '$path Capability ${shape.key}.fieldIds',
              ) ??
              <String>{},
        );
      }
    }
    if (hasTransferExport) {
      expectedShapes.addAll(const {
        'materialize_media_resource_request': (
          kind: 'request',
          fields: {'media_handle'},
        ),
        'materialized_media_resource': (
          kind: 'result',
          fields: {
            'export_handle',
            'file_uri',
            'media_type',
            'content_type',
            'byte_length',
            'duration_millis',
            'expires_at',
            'integrity_sha256',
          },
        ),
        'release_materialized_media_request': (
          kind: 'request',
          fields: {'export_handle'},
        ),
        'materialized_media_released': (kind: 'result', fields: <String>{}),
        'dismiss_capture_flow_request': (
          kind: 'request',
          fields: {'presentation_request_id'},
        ),
        'capture_flow_dismissed': (kind: 'result', fields: <String>{}),
      });
    }
    final seenShapes = <String>{};
    for (final entry in payloads.entries) {
      final payload = entry.value;
      final label = '$path payload ${entry.key}';
      _validateCapabilityExactKeys(payload, const {
        'id',
        'kind',
        'capabilityShapeId',
        'fieldIds',
        'unknownFieldPolicy',
      }, label);
      final shapeId = payload['capabilityShapeId'];
      if (shapeId is! String || !seenShapes.add(shapeId)) {
        errors.add('$label 必须唯一引用一个 Capability shape');
        continue;
      }
      final expected = expectedShapes[shapeId];
      if (expected == null) {
        errors.add('$label 引用了未映射或不存在的 Capability shape');
        continue;
      }
      final fields =
          _capabilityStringSet(payload['fieldIds'], '$label fieldIds') ??
          <String>{};
      final expectedPayloadId = switch (shapeId) {
        'materialize_media_resource_request' =>
          'materialize_media_resource_request_payload',
        'materialized_media_resource' => 'materialized_media_result_payload',
        'release_materialized_media_request' =>
          'release_materialized_media_request_payload',
        'materialized_media_released' =>
          'materialized_media_released_result_payload',
        'dismiss_capture_flow_request' =>
          'dismiss_capture_flow_request_payload',
        'capture_flow_dismissed' => 'capture_flow_dismissed_result_payload',
        _ =>
          expected.kind == 'request'
              ? '${shapeId}_payload'
              : '${shapeId}_${expected.kind}_payload',
      };
      if (payload['kind'] != expected.kind ||
          entry.key != expectedPayloadId ||
          !_sameStringSet(fields, expected.fields) ||
          !fieldMappings.keys.toSet().containsAll(fields) ||
          payload['unknownFieldPolicy'] != 'reject') {
        errors.add('$label 必须从 Capability shape 确定性派生并拒绝未知字段');
      }
    }
    if (!_sameStringSet(seenShapes, expectedShapes.keys.toSet())) {
      errors.add('$path payloads 未完整覆盖可传输 Capability shapes');
    }
    return payloads;
  }

  Map<String, Map<String, Object?>> _validateWireFailurePayloads(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> fieldMappings,
    String path,
  ) {
    final payloads = _wireObjectsById(value, 'id', '$path failurePayloads');
    final failures = _wireObjectsById(
      capability['failure'],
      'id',
      '$path Capability failures',
    );
    if (!_sameStringSet(payloads.keys.toSet(), const {
      'session_timeout_failure_payload',
    })) {
      errors.add('$path failurePayloads 必须映射异步 session_timeout');
    }
    final payload = payloads['session_timeout_failure_payload'];
    if (payload != null) {
      _validateCapabilityExactKeys(payload, const {
        'id',
        'capabilityFailureId',
        'contextFieldIds',
        'unknownFieldPolicy',
      }, '$path session_timeout failure payload');
      final contextFields =
          _capabilityStringSet(
            payload['contextFieldIds'],
            '$path session_timeout contextFieldIds',
          ) ??
          <String>{};
      if (payload['capabilityFailureId'] != 'session_timeout' ||
          !failures.containsKey('session_timeout') ||
          !_sameStringSet(contextFields, const {'session_handle'}) ||
          !fieldMappings.keys.toSet().containsAll(contextFields) ||
          payload['unknownFieldPolicy'] != 'reject') {
        errors.add('$path session_timeout failure payload 映射不一致');
      }
    }
    return payloads;
  }

  Map<String, Map<String, Object?>> _validateWireFailureDelivery(
    Object? value,
    Map<String, Object?> capability,
    String path,
  ) {
    final delivery = _wireObjectsById(
      value,
      'capabilityOperationId',
      '$path failureDelivery',
    );
    final operations = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operations',
    );
    final expectedIds = operations.keys.toSet()
      ..removeAll(const {
        'open_media_read',
        'attach_live_preview',
        'detach_live_preview',
        'attach_unconfirmed_preview_render',
        'detach_unconfirmed_preview_render',
      });
    if (!_sameStringSet(delivery.keys.toSet(), expectedIds)) {
      errors.add('$path failureDelivery 必须覆盖全部暴露 method');
    }
    for (final entry in delivery.entries) {
      final rule = entry.value;
      final label = '$path failureDelivery ${entry.key}';
      _validateCapabilityExactKeys(rule, const {
        'capabilityOperationId',
        'directFailureIds',
        'deferredEventId',
        'deferredFailureIds',
      }, label);
      final operation = operations[entry.key];
      if (operation == null) {
        errors.add('$label 引用了未知 Capability operation');
        continue;
      }
      final declared =
          _capabilityStringSet(operation['failureIds'], '$label failureIds') ??
          <String>{};
      final direct =
          _capabilityStringSet(
            rule['directFailureIds'],
            '$label directFailureIds',
          ) ??
          <String>{};
      final deferred =
          _capabilityStringSet(
            rule['deferredFailureIds'],
            '$label deferredFailureIds',
          ) ??
          <String>{};
      final overlap = direct.intersection(deferred);
      final combined = {...direct, ...deferred};
      final eventIds =
          _capabilityStringSet(operation['eventIds'], '$label eventIds') ??
          <String>{};
      final deferredEvent = rule['deferredEventId'];
      if (overlap.isNotEmpty || !_sameStringSet(combined, declared)) {
        errors.add('$label direct/deferred 必须无重叠地覆盖 operation Failure');
      }
      if (deferred.isEmpty) {
        if (deferredEvent != null) {
          errors.add('$label 没有 deferred Failure 时 event 必须为 null');
        }
      } else if (deferredEvent != 'session_failed' ||
          !eventIds.contains('session_failed')) {
        errors.add('$label deferred Failure 必须通过已声明 session_failed 交付');
      }
      if (entry.key == 'start_session') {
        if (!_sameStringSet(direct, const {
              'invalid_argument',
              'unsupported_capability',
              'session_conflict',
            }) ||
            !_sameStringSet(deferred, const {
              'permission_denied',
              'permission_restricted',
              'permission_permanently_denied',
              'resource_in_use',
              'storage_full',
              'system_interrupted',
            })) {
          errors.add('$label 必须固定立即结果之前/之后的 Failure 分流');
        }
      } else if (!_sameStringSet(direct, declared) || deferred.isNotEmpty) {
        errors.add('$label 必须由 pending method 直接且只交付一次 operation Failure');
      }
    }
    return delivery;
  }

  Map<String, Map<String, Object?>> _validateWireMethods(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> payloads,
    Map<String, Map<String, Object?>> failureDelivery,
    String path,
  ) {
    final methods = _wireObjectsById(value, 'id', '$path methods');
    final operations = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operations',
    );
    final directOperationIds = operations.keys.toSet()
      ..removeAll(const {
        'open_media_read',
        'copy_confirmed_media_to_sink',
        'attach_live_preview',
        'detach_live_preview',
        'attach_unconfirmed_preview_render',
        'detach_unconfirmed_preview_render',
      });
    final expectedIds = {
      ...directOperationIds,
      if (operations.containsKey('copy_confirmed_media_to_sink'))
        'materialize_media_resource',
      if (operations.containsKey('copy_confirmed_media_to_sink'))
        'release_materialized_media',
      if (operations.containsKey('copy_confirmed_media_to_sink'))
        'dismiss_capture_flow',
      'present_capture_flow',
    };
    if (!_sameStringSet(methods.keys.toSet(), expectedIds)) {
      errors.add('$path methods 必须精确包含可传输 Capability operation 与 presentation');
    }
    const protocolErrors = {
      'incompatible_wire_version',
      'invalid_wire_payload',
      'duplicate_request',
      'bridge_unavailable',
      'bridge_overloaded',
      'wire_encoding_failed',
    };
    for (final entry in methods.entries) {
      final method = entry.value;
      final label = '$path method ${entry.key}';
      if (entry.key == 'present_capture_flow') {
        _validateMediaCapturePresentationMethod(
          method,
          operations,
          payloads,
          protocolErrors,
          label,
        );
        continue;
      }
      if (entry.key == 'materialize_media_resource') {
        _validateMediaCaptureMaterializeMethod(
          method,
          operations,
          payloads,
          failureDelivery,
          protocolErrors,
          label,
        );
        continue;
      }
      if (entry.key == 'release_materialized_media') {
        _validateMediaCaptureReleaseMaterializedMethod(
          method,
          payloads,
          protocolErrors,
          label,
        );
        continue;
      }
      if (entry.key == 'dismiss_capture_flow') {
        _validateMediaCaptureDismissMethod(
          method,
          payloads,
          protocolErrors,
          label,
        );
        continue;
      }
      _validateCapabilityExactKeys(method, const {
        'id',
        'kind',
        'channelId',
        'capabilityOperationId',
        'requestPayloadId',
        'resultPayloadId',
        'resultType',
        'errorCodes',
        'completion',
        'platformSupport',
      }, label);
      final operation = operations[entry.key];
      if (operation == null || !directOperationIds.contains(entry.key)) {
        errors.add('$label 引用了未知 Capability operation');
        continue;
      }
      final expectedRequest = '${operation['requestId']}_payload';
      final expectedResult = '${operation['resultId']}_result_payload';
      final capabilityFailures =
          _capabilityStringSet(
            failureDelivery[entry.key]?['directFailureIds'],
            '$label directFailureIds',
          ) ??
          <String>{};
      final expectedErrors = {...capabilityFailures, ...protocolErrors};
      final actualErrors =
          _capabilityStringSet(method['errorCodes'], '$label errorCodes') ??
          <String>{};
      if (method['kind'] != 'direct_operation' ||
          method['capabilityOperationId'] != entry.key ||
          method['channelId'] != 'commands' ||
          method['requestPayloadId'] != expectedRequest ||
          method['resultPayloadId'] != expectedResult ||
          method['resultType'] != operation['resultId'] ||
          !payloads.containsKey(expectedRequest) ||
          !payloads.containsKey(expectedResult) ||
          !_sameStringSet(actualErrors, expectedErrors) ||
          method['completion'] != 'exactly_once') {
        errors.add('$label 的 Capability/Payload/Error/完成映射不一致');
      }
      _validateWirePlatformSupport(method['platformSupport'], label);
    }
    return methods;
  }

  void _validateMediaCaptureMaterializeMethod(
    Map<String, Object?> method,
    Map<String, Map<String, Object?>> operations,
    Map<String, Map<String, Object?>> payloads,
    Map<String, Map<String, Object?>> failureDelivery,
    Set<String> protocolErrors,
    String label,
  ) {
    _validateCapabilityExactKeys(method, const {
      'id',
      'kind',
      'channelId',
      'capabilityOperationId',
      'requestPayloadId',
      'resultPayloadId',
      'resultType',
      'errorCodes',
      'completion',
      'platformSupport',
    }, label);
    final operation = operations['copy_confirmed_media_to_sink'];
    final capabilityFailures =
        _capabilityStringSet(
          failureDelivery['copy_confirmed_media_to_sink']?['directFailureIds'],
          '$label directFailureIds',
        ) ??
        <String>{};
    final actualErrors =
        _capabilityStringSet(method['errorCodes'], '$label errorCodes') ??
        <String>{};
    if (operation == null ||
        method['kind'] != 'direct_operation' ||
        method['capabilityOperationId'] != 'copy_confirmed_media_to_sink' ||
        method['channelId'] != 'commands' ||
        method['requestPayloadId'] !=
            'materialize_media_resource_request_payload' ||
        method['resultPayloadId'] != 'materialized_media_result_payload' ||
        method['resultType'] != 'materialized_media_resource' ||
        !payloads.containsKey('materialize_media_resource_request_payload') ||
        !payloads.containsKey('materialized_media_result_payload') ||
        !_sameStringSet(actualErrors, {
          ...capabilityFailures,
          ...protocolErrors,
          'transfer_store_overloaded',
          'transfer_store_unavailable',
        }) ||
        method['completion'] != 'exactly_once') {
      errors.add('$label 必须以 Adapter-owned sink 映射 Capability V4 export');
    }
    _validateWirePlatformSupport(method['platformSupport'], label);
  }

  void _validateMediaCaptureReleaseMaterializedMethod(
    Map<String, Object?> method,
    Map<String, Map<String, Object?>> payloads,
    Set<String> protocolErrors,
    String label,
  ) {
    _validateCapabilityExactKeys(method, const {
      'id',
      'kind',
      'channelId',
      'requestPayloadId',
      'resultPayloadId',
      'resultType',
      'errorCodes',
      'completion',
      'platformSupport',
    }, label);
    final actualErrors =
        _capabilityStringSet(method['errorCodes'], '$label errorCodes') ??
        <String>{};
    if (method['kind'] != 'adapter_operation' ||
        method['channelId'] != 'commands' ||
        method['requestPayloadId'] !=
            'release_materialized_media_request_payload' ||
        method['resultPayloadId'] !=
            'materialized_media_released_result_payload' ||
        method['resultType'] != 'materialized_media_released' ||
        !payloads.containsKey('release_materialized_media_request_payload') ||
        !payloads.containsKey('materialized_media_released_result_payload') ||
        !_sameStringSet(actualErrors, {
          ...protocolErrors,
          'materialized_media_invalid',
          'transfer_store_overloaded',
          'transfer_store_unavailable',
        }) ||
        method['completion'] != 'exactly_once') {
      errors.add('$label 必须是 Adapter transfer release，不能释放 source media');
    }
    _validateWirePlatformSupport(method['platformSupport'], label);
  }

  void _validateMediaCaptureDismissMethod(
    Map<String, Object?> method,
    Map<String, Map<String, Object?>> payloads,
    Set<String> protocolErrors,
    String label,
  ) {
    _validateCapabilityExactKeys(method, const {
      'id',
      'kind',
      'channelId',
      'requestPayloadId',
      'resultPayloadId',
      'resultType',
      'errorCodes',
      'completion',
      'platformSupport',
    }, label);
    final actualErrors =
        _capabilityStringSet(method['errorCodes'], '$label errorCodes') ??
        <String>{};
    final platformSupport = _capabilityObject(
      method['platformSupport'],
      '$label platformSupport',
    );
    if (method['kind'] != 'adapter_operation' ||
        method['channelId'] != 'commands' ||
        method['requestPayloadId'] != 'dismiss_capture_flow_request_payload' ||
        method['resultPayloadId'] != 'capture_flow_dismissed_result_payload' ||
        method['resultType'] != 'capture_flow_dismissed' ||
        !payloads.containsKey('dismiss_capture_flow_request_payload') ||
        !payloads.containsKey('capture_flow_dismissed_result_payload') ||
        !_sameStringSet(actualErrors, protocolErrors) ||
        method['completion'] != 'exactly_once' ||
        platformSupport?['android'] != 'supported' ||
        platformSupport?['ios'] != 'supported') {
      errors.add('$label 必须按 presentation requestId 精确关闭 Android/iOS flow');
    }
  }

  void _validateMediaCapturePresentationMethod(
    Map<String, Object?> method,
    Map<String, Map<String, Object?>> operations,
    Map<String, Map<String, Object?>> payloads,
    Set<String> protocolErrors,
    String label,
  ) {
    _validateCapabilityExactKeys(method, const {
      'id',
      'kind',
      'channelId',
      'capabilityOperationId',
      'requestPayloadId',
      'orchestratedCapabilityOperationIds',
      'nativeOnlyCapabilityOperationIds',
      'presentationPolicy',
      'terminalOutcomes',
      'errorCodes',
      'completion',
      'platformSupport',
    }, label);
    const orchestrated = {
      'start_session',
      'take_photo',
      'start_recording',
      'stop_recording',
      'switch_camera',
      'set_flash_mode',
      'set_focus_point',
      'set_zoom',
      'retake',
      'confirm',
      'cancel',
    };
    const nativeOnly = {
      'attach_live_preview',
      'detach_live_preview',
      'attach_unconfirmed_preview_render',
      'detach_unconfirmed_preview_render',
    };
    final declaredOrchestrated =
        _capabilityStringSet(
          method['orchestratedCapabilityOperationIds'],
          '$label orchestratedCapabilityOperationIds',
        ) ??
        <String>{};
    final declaredNativeOnly =
        _capabilityStringSet(
          method['nativeOnlyCapabilityOperationIds'],
          '$label nativeOnlyCapabilityOperationIds',
        ) ??
        <String>{};
    if (method['kind'] != 'presentation' ||
        method['channelId'] != 'commands' ||
        method['capabilityOperationId'] != null ||
        method['requestPayloadId'] != 'start_session_request_payload' ||
        !payloads.containsKey('start_session_request_payload') ||
        operations.containsKey('present_capture_flow') ||
        !_sameStringSet(declaredOrchestrated, orchestrated) ||
        !_sameStringSet(declaredNativeOnly, nativeOnly) ||
        !operations.keys.toSet().containsAll({
          ...orchestrated,
          ...nativeOnly,
        }) ||
        method['completion'] != 'exactly_once') {
      errors.add('$label 必须是只编排既有 Capability operation 的 presentation');
    }

    final policy = _capabilityObject(
      method['presentationPolicy'],
      '$label presentationPolicy',
    );
    if (policy != null) {
      _validateCapabilityExactKeys(policy, const {
        'mode',
        'ownerScope',
        'ownerGeneration',
        'maxConcurrentPerOwner',
        'capabilityEventRouting',
        'slotPolicy',
        'presentOrder',
        'dismissOrder',
        'ownerLifecyclePolicies',
        'ownerDestroy',
        'engineDetach',
      }, '$label presentationPolicy');
      if (policy['mode'] != 'full_screen' ||
          policy['ownerScope'] != 'current_attached_ui_owner' ||
          policy['ownerGeneration'] != 'monotonic_per_attachment' ||
          policy['maxConcurrentPerOwner'] != 1 ||
          policy['capabilityEventRouting'] !=
              'consume_in_presentation_do_not_emit_to_flutter' ||
          !_wireJsonEquals(policy['presentOrder'], const [
            'validate_request',
            'reserve_completion',
            'capture_owner_generation',
            'coordinator_owner_generation_open_recheck',
            'coordinator_reserve_active_presentation_slot',
            'create_capability_session',
            'present_native_ui',
          ]) ||
          !_wireJsonEquals(policy['dismissOrder'], const [
            'revoke_native_render_scopes',
            'dismiss_native_ui',
            'cleanup_session_and_unconfirmed_media',
            'settle_confirmed_or_undelivered_lease',
            'release_active_presentation_slot',
            'complete_flutter_once',
          ]) ||
          policy['ownerDestroy'] !=
              'cleanup_session_preview_and_undelivered_lease_release_slot_then_bridge_unavailable' ||
          policy['engineDetach'] !=
              'cleanup_session_preview_and_leases_release_slot_then_bridge_unavailable') {
        errors.add(
          '$label presentation owner、present/dismiss 与 lifecycle 顺序不闭合',
        );
      }
      _validatePresentationSlotPolicy(
        policy['slotPolicy'],
        '$label presentationPolicy.slotPolicy',
      );
      _validateOwnerLifecyclePolicies(
        policy['ownerLifecyclePolicies'],
        '$label presentationPolicy.ownerLifecyclePolicies',
      );
    }

    final outcomes = _wireObjectsById(
      method['terminalOutcomes'],
      'id',
      '$label terminalOutcomes',
    );
    const expectedOutcomes = {
      'confirmed': (
        delivery: 'result',
        resultType: 'capture_flow_confirmed',
        payload: 'confirmed_media_result_payload',
        adoption: 'capture_flow_confirmed_adoption',
        cleanup:
            'cleanup_session_preview_settle_delivered_lease_release_slot_then_complete',
      ),
      'cancelled': (
        delivery: 'result',
        resultType: 'capture_flow_cancelled',
        payload: null,
        adoption: null,
        cleanup: 'cleanup_session_preview_no_lease_release_slot_then_complete',
      ),
      'failure': (
        delivery: 'error',
        resultType: null,
        payload: null,
        adoption: null,
        cleanup:
            'cleanup_session_preview_release_undelivered_lease_release_slot_then_complete',
      ),
    };
    if (!_sameStringSet(outcomes.keys.toSet(), expectedOutcomes.keys.toSet())) {
      errors.add('$label 必须声明 confirmed/cancelled/failure 三个互斥终态');
    }
    for (final entry in outcomes.entries) {
      _validateCapabilityExactKeys(entry.value, const {
        'id',
        'delivery',
        'resultType',
        'resultPayloadId',
        'resourceAdoptionPolicyId',
        'completionMachineOrderId',
        'cleanupPolicyId',
      }, '$label terminal ${entry.key}');
      final expected = expectedOutcomes[entry.key];
      if (expected == null ||
          entry.value['delivery'] != expected.delivery ||
          entry.value['resultType'] != expected.resultType ||
          entry.value['resultPayloadId'] != expected.payload ||
          entry.value['resourceAdoptionPolicyId'] != expected.adoption ||
          entry.value['completionMachineOrderId'] !=
              'presentation_callback_terminal_machine' ||
          entry.value['cleanupPolicyId'] != expected.cleanup ||
          (expected.payload != null &&
              !payloads.containsKey(expected.payload))) {
        errors.add('$label terminal ${entry.key} 的交付、adoption 或 cleanup 不一致');
      }
    }

    const flowCapabilityFailures = {
      'permission_denied',
      'permission_restricted',
      'permission_permanently_denied',
      'resource_in_use',
      'storage_full',
      'encoding_failed',
      'media_invalid',
      'session_invalid',
      'unsupported_capability',
      'system_interrupted',
      'session_conflict',
      'invalid_state',
      'invalid_argument',
      'session_timeout',
    };
    final declaredErrors =
        _capabilityStringSet(method['errorCodes'], '$label errorCodes') ??
        <String>{};
    if (!_sameStringSet(declaredErrors, {
      ...flowCapabilityFailures,
      ...protocolErrors,
      'presentation_conflict',
    })) {
      errors.add('$label failure 终态必须使用闭合的 Capability/Wire error 集合');
    }
    _validateWirePlatformSupport(method['platformSupport'], label);
  }

  void _validatePresentationSlotPolicy(Object? value, String label) {
    final policy = _capabilityObject(value, label);
    if (policy == null) {
      return;
    }
    _validateCapabilityExactKeys(policy, const {
      'coordinatorId',
      'scope',
      'capacity',
      'generationTransition',
      'terminalMachineOrderId',
      'reservationOrder',
      'conflictOutcome',
      'releaseTriggerIds',
      'releaseOrder',
    }, label);
    final releaseTriggers =
        _capabilityStringSet(
          policy['releaseTriggerIds'],
          '$label releaseTriggerIds',
        ) ??
        <String>{};
    if (policy['coordinatorId'] != 'bridge_lifecycle_coordinator' ||
        policy['scope'] != 'attached_ui_owner_identity' ||
        policy['capacity'] != 1 ||
        policy['generationTransition'] !=
            'preserve_owner_identity_slot_across_fresh_generation' ||
        policy['terminalMachineOrderId'] !=
            'presentation_callback_terminal_machine' ||
        !_wireJsonEquals(policy['reservationOrder'], const [
          'owner_generation_open_recheck',
          'reserve_active_presentation_slot',
          'create_capability_session',
        ]) ||
        policy['conflictOutcome'] !=
            'presentation_conflict_once_without_session' ||
        !_sameStringSet(releaseTriggers, const {
          'confirmed_terminal',
          'cancelled_terminal',
          'failure_terminal',
          'presentation_failed',
          'engine_detach',
          'ui_owner_destroy',
        }) ||
        !_wireJsonEquals(policy['releaseOrder'], const [
          'revoke_dismiss_cleanup_session_preview',
          'settle_confirmed_or_undelivered_lease',
          'release_active_presentation_slot',
          'complete_flutter_once',
        ])) {
      errors.add(
        '$label 必须按稳定 owner identity 原子 recheck/reserve，并在 cleanup 后、completion 前释放 slot',
      );
    }
  }

  void _validateOwnerLifecyclePolicies(Object? value, String label) {
    final policies = _wireObjectsById(value, 'id', label);
    const expected =
        <
          String,
          ({
            String triggerId,
            String ownerState,
            List<String> actions,
            String generationPolicy,
            String reattachPolicy,
            String? terminalOutcome,
          })
        >{
          'background_owner_alive': (
            triggerId: 'app_backgrounded',
            ownerState: 'alive',
            actions: [
              'revoke_render_scopes',
              'detach_render_targets',
              'suspend_presentation',
              'preserve_attached_owner_slot',
              'allocate_strictly_higher_generation_on_foreground',
              'explicit_reattach',
            ],
            generationPolicy: 'strictly_higher_than_retired_generation',
            reattachPolicy: 'explicit_after_foreground',
            terminalOutcome: null,
          ),
          'rotation_owner_alive': (
            triggerId: 'display_rotation_changed',
            ownerState: 'alive',
            actions: [
              'revoke_render_scopes',
              'detach_render_targets',
              'preserve_attached_owner_slot',
              'allocate_strictly_higher_generation_after_rotation',
              'explicit_reattach',
            ],
            generationPolicy: 'strictly_higher_than_retired_generation',
            reattachPolicy: 'explicit_after_rotation',
            terminalOutcome: null,
          ),
          'rotation_owner_destroyed': (
            triggerId: 'display_rotation_changed',
            ownerState: 'destroyed',
            actions: [
              'revoke_render_scopes',
              'dismiss_native_ui',
              'interrupt_session_cleanup_preview',
              'release_undelivered_lease',
              'release_active_presentation_slot',
              'complete_failure_once',
            ],
            generationPolicy: 'no_new_generation',
            reattachPolicy: 'forbidden',
            terminalOutcome: 'failure',
          ),
        };
    if (!_sameStringSet(policies.keys.toSet(), expected.keys.toSet())) {
      errors.add('$label 必须区分 background/rotation owner 存活与销毁路径');
    }
    for (final entry in policies.entries) {
      final policy = entry.value;
      _validateCapabilityExactKeys(policy, const {
        'id',
        'triggerId',
        'ownerState',
        'actions',
        'generationPolicy',
        'reattachPolicy',
        'terminalOutcome',
      }, '$label ${entry.key}');
      final expectedPolicy = expected[entry.key];
      if (expectedPolicy == null ||
          policy['triggerId'] != expectedPolicy.triggerId ||
          policy['ownerState'] != expectedPolicy.ownerState ||
          !_wireJsonEquals(policy['actions'], expectedPolicy.actions) ||
          policy['generationPolicy'] != expectedPolicy.generationPolicy ||
          policy['reattachPolicy'] != expectedPolicy.reattachPolicy ||
          policy['terminalOutcome'] != expectedPolicy.terminalOutcome) {
        errors.add(
          '$label ${entry.key} 必须先 revoke，并按 owner 存活状态使用 fresh generation 或 failure',
        );
      }
    }
  }

  Map<String, Map<String, Object?>> _validateWireEvents(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> payloads,
    String path,
  ) {
    final events = _wireObjectsById(value, 'id', '$path events');
    final capabilityEvents = _wireObjectsById(
      capability['event'],
      'id',
      '$path Capability events',
    );
    final expectedEventIds = capabilityEvents.keys.toSet()
      ..remove('render_attachment_revoked');
    if (!_sameStringSet(events.keys.toSet(), expectedEventIds)) {
      errors.add('$path events 必须映射全部可跨 Channel 的 Capability events');
    }
    for (final entry in events.entries) {
      final event = entry.value;
      final label = '$path event ${entry.key}';
      _validateCapabilityExactKeys(event, const {
        'id',
        'channelId',
        'capabilityEventId',
        'payloadId',
        'platformSupport',
      }, label);
      final expectedPayload = '${entry.key}_event_payload';
      if (!expectedEventIds.contains(entry.key) ||
          event['capabilityEventId'] != entry.key ||
          event['channelId'] != 'events' ||
          event['payloadId'] != expectedPayload ||
          !payloads.containsKey(expectedPayload)) {
        errors.add('$label 的 Capability/Payload 映射不一致');
      }
      _validateWirePlatformSupport(event['platformSupport'], label);
    }
    return events;
  }

  void _validateWireAsyncFailures(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> failurePayloads,
    String path,
  ) {
    final asyncFailures = _wireObjectsById(value, 'id', '$path asyncFailures');
    final capabilityFailureEmissions = <String>{};
    final machines = _wireObjectsById(
      capability['stateMachines'],
      'id',
      '$path Capability stateMachines',
    );
    for (final machine in machines.entries) {
      final transitions = _capabilityObjectList(
        machine.value['transitions'],
        '$path Capability ${machine.key}.transitions',
      );
      if (transitions == null) {
        continue;
      }
      for (final transition in transitions) {
        final emission = _capabilityObject(
          transition['emission'],
          '$path Capability ${machine.key}.emission',
        );
        if (emission?['kind'] == 'failure') {
          capabilityFailureEmissions.add(
            '${machine.key}|${transition['triggerId']}|${emission?['id']}',
          );
        }
      }
    }
    if (!_sameStringSet(capabilityFailureEmissions, const {
      'session|preview_timed_out|session_timeout',
    })) {
      errors.add('$path Capability failure emission 集合与 Wire V2 映射不一致');
    }
    if (!_sameStringSet(asyncFailures.keys.toSet(), const {
      'session_timeout',
    })) {
      errors.add('$path asyncFailures 必须完整映射 Capability failure emission');
    }
    final failure = asyncFailures['session_timeout'];
    if (failure == null) {
      return;
    }
    _validateCapabilityExactKeys(failure, const {
      'id',
      'channelId',
      'capabilityFailureId',
      'capabilityStateMachineId',
      'capabilityTriggerId',
      'payloadId',
      'failureType',
      'callbackThread',
      'sinkBehavior',
      'platformSupport',
    }, '$path asyncFailure session_timeout');
    if (failure['channelId'] != 'events' ||
        failure['capabilityFailureId'] != 'session_timeout' ||
        failure['capabilityStateMachineId'] != 'session' ||
        failure['capabilityTriggerId'] != 'preview_timed_out' ||
        failure['payloadId'] != 'session_timeout_failure_payload' ||
        !failurePayloads.containsKey('session_timeout_failure_payload') ||
        failure['failureType'] != 'session_timeout' ||
        failure['callbackThread'] != 'platform_ui_thread' ||
        failure['sinkBehavior'] != 'continue') {
      errors.add('$path asyncFailure session_timeout 映射不一致');
    }
    _validateWirePlatformSupport(
      failure['platformSupport'],
      '$path asyncFailure session_timeout',
    );
  }

  Map<String, Map<String, Object?>> _validateWireErrorDetailFields(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> fieldMappings,
    Map<String, Map<String, Object?>> methods,
    String path,
  ) {
    final details = _wireObjectsByWireKey(
      value,
      'key',
      '$path errorDetailFields',
    );
    const expectedKeys = {
      'operation',
      'capabilityFailureId',
      'actualWireVersion',
      'expectedWireVersion',
      'field',
      'reason',
      'lifecycleReason',
      'capacity',
    };
    if (!_sameStringSet(details.keys.toSet(), expectedKeys)) {
      errors.add('$path errorDetailFields 必须精确声明安全 details 字段');
    }
    final failureIds = _wireObjectsById(
      capability['failure'],
      'id',
      '$path Capability failures',
    ).keys.toSet();
    final hasTransferExport = methods.containsKey('materialize_media_resource');
    final expectedEnums = <String, Set<String>>{
      'operation': {...methods.keys, 'unknown_operation'},
      'capabilityFailureId': failureIds,
      'actualWireVersion': {},
      'expectedWireVersion': {},
      'field': {
        ...fieldMappings.values
            .map((mapping) => mapping['key'])
            .whereType<String>(),
        'wireVersion',
        'requestId',
        'payload',
        'resultType',
        'eventType',
        'failureType',
        'unknown_field',
      },
      'reason': {
        'missing_required_field',
        'unknown_field',
        'type_mismatch',
        'null_not_allowed',
        'non_finite',
        'out_of_range',
        'invalid_enum',
        'invalid_format',
        'integer_overflow',
        'result_type_mismatch',
        'native_value_unencodable',
      },
      'lifecycleReason': {
        'engine_detached',
        'activity_destroyed',
        'view_controller_destroyed',
        'adapter_disposed',
      },
      'capacity': {
        'pending_requests',
        'completed_request_tombstones',
        'active_presentation',
        if (hasTransferExport) 'active_exports',
        if (hasTransferExport) 'active_export_bytes',
        if (hasTransferExport) 'release_tombstones',
      },
    };
    const expectedSources = {
      'operation': 'method_id_or_unknown',
      'capabilityFailureId': 'capability_failure_id',
      'actualWireVersion': 'request_wire_version',
      'expectedWireVersion': 'contract_wire_version',
      'field': 'declared_field_key_or_unknown',
      'reason': 'closed_reason_code',
      'lifecycleReason': 'closed_lifecycle_reason',
      'capacity': 'closed_capacity_code',
    };
    for (final entry in details.entries) {
      final detail = entry.value;
      final label = '$path error detail ${entry.key}';
      _validateCapabilityExactKeys(detail, const {
        'key',
        'wireType',
        'source',
        'enumValues',
        'minLength',
        'maxLength',
        'minimum',
        'maximum',
        'redaction',
      }, label);
      final enumValues =
          _capabilityStringSet(detail['enumValues'], '$label enumValues') ??
          <String>{};
      if (!_sameStringSet(enumValues, expectedEnums[entry.key] ?? const {}) ||
          detail['source'] != expectedSources[entry.key] ||
          detail['redaction'] != 'allowlisted_value_only') {
        errors.add('$label 的 source/enum/redaction 不满足闭合集合');
      }
      final isVersion =
          entry.key == 'actualWireVersion' ||
          entry.key == 'expectedWireVersion';
      if (isVersion) {
        if (detail['wireType'] != 'int' ||
            detail['minLength'] != null ||
            detail['maxLength'] != null ||
            detail['minimum'] is! int ||
            detail['minimum'] != -9223372036854775808 ||
            detail['maximum'] is! int ||
            detail['maximum'] != 9223372036854775807) {
          errors.add('$label 必须使用 signed-64 int');
        }
      } else if (detail['wireType'] != 'string' ||
          detail['minLength'] != 1 ||
          detail['maxLength'] != 64 ||
          detail['minimum'] != null ||
          detail['maximum'] != null) {
        errors.add('$label 必须使用最长 64 字符的 allowlisted string');
      }
    }
    return details;
  }

  Map<String, Map<String, Object?>> _validateWireErrors(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> errorDetailFields,
    String path,
  ) {
    final wireErrors = _wireObjectsById(value, 'code', '$path errors');
    final failures = _wireObjectsById(
      capability['failure'],
      'id',
      '$path Capability failures',
    );
    final hasTransferExport = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operations',
    ).containsKey('copy_confirmed_media_to_sink');
    final protocolCodes = {
      'incompatible_wire_version',
      'invalid_wire_payload',
      'duplicate_request',
      'bridge_unavailable',
      'bridge_overloaded',
      'wire_encoding_failed',
      'listener_already_active',
      'presentation_conflict',
      if (hasTransferExport) 'transfer_store_overloaded',
      if (hasTransferExport) 'transfer_store_unavailable',
      if (hasTransferExport) 'materialized_media_invalid',
    };
    final mappedFailureIds = failures.keys.toSet()
      ..removeAll(const {
        'attachment_generation_retired',
        'attachment_target_conflict',
      });
    final expectedCodes = {...mappedFailureIds, ...protocolCodes};
    if (!_sameStringSet(wireErrors.keys.toSet(), expectedCodes)) {
      errors.add('$path errors 必须完整映射 Capability Failure 和固定 Wire error');
    }
    for (final entry in wireErrors.entries) {
      final error = entry.value;
      final label = '$path error ${entry.key}';
      _validateCapabilityExactKeys(error, const {
        'code',
        'source',
        'capabilityFailureId',
        'recoverable',
        'terminal',
        'messagePolicy',
        'detailsAllowedKeys',
      }, label);
      final details =
          _capabilityStringSet(
            error['detailsAllowedKeys'],
            '$label detailsAllowedKeys',
          ) ??
          <String>{};
      if (error['messagePolicy'] != 'static_redacted' ||
          !errorDetailFields.keys.toSet().containsAll(details) ||
          details.any((key) => !RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(key))) {
        errors.add('$label 必须使用脱敏 message 和 lowerCamelCase details key');
      }
      final failure = failures[entry.key];
      if (failure != null) {
        if (error['source'] != 'capability_failure' ||
            error['capabilityFailureId'] != entry.key ||
            error['recoverable'] != failure['recoverable'] ||
            error['terminal'] != failure['terminal'] ||
            !_sameStringSet(details, const {
              'operation',
              'capabilityFailureId',
            })) {
          errors.add('$label 必须原样映射 Capability Failure');
        }
        continue;
      }
      final expected = switch (entry.key) {
        'incompatible_wire_version' => (
          recoverable: false,
          details: {'actualWireVersion', 'expectedWireVersion'},
        ),
        'invalid_wire_payload' => (
          recoverable: true,
          details: {'operation', 'field', 'reason'},
        ),
        'duplicate_request' => (recoverable: true, details: {'operation'}),
        'bridge_unavailable' => (
          recoverable: true,
          details: {'operation', 'lifecycleReason'},
        ),
        'bridge_overloaded' => (
          recoverable: true,
          details: {'operation', 'capacity'},
        ),
        'wire_encoding_failed' => (
          recoverable: false,
          details: {'operation', 'field', 'reason'},
        ),
        'listener_already_active' => (recoverable: true, details: <String>{}),
        'presentation_conflict' => (
          recoverable: true,
          details: {'operation', 'capacity'},
        ),
        'transfer_store_overloaded' => (
          recoverable: true,
          details: {'operation', 'capacity'},
        ),
        'transfer_store_unavailable' => (
          recoverable: true,
          details: {'operation', 'lifecycleReason'},
        ),
        'materialized_media_invalid' => (
          recoverable: true,
          details: {'operation'},
        ),
        _ => null,
      };
      if (expected == null ||
          error['source'] != 'wire_protocol' ||
          error['capabilityFailureId'] != null ||
          error['recoverable'] != expected.recoverable ||
          error['terminal'] != false ||
          !_sameStringSet(details, expected.details)) {
        errors.add('$label 不是固定的 Wire protocol error');
      }
    }
    return wireErrors;
  }

  void _validateWireCoverage(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> methods,
    Map<String, Map<String, Object?>> events,
    Map<String, Map<String, Object?>> payloads,
    Map<String, Map<String, Object?>> wireErrors,
    String path,
  ) {
    final coverage = _capabilityObject(value, '$path coverage');
    if (coverage == null) {
      return;
    }
    _validateCapabilityExactKeys(coverage, const {
      'operations',
      'results',
      'events',
      'failures',
      'resources',
      'ownershipScopes',
      'nativeInputs',
      'nativeArtifacts',
    }, '$path coverage');
    final operationIds = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operation',
    ).keys.toSet();
    final resultIds = _wireObjectsById(
      capability['result'],
      'id',
      '$path Capability result',
    ).keys.toSet();
    final eventIds = _wireObjectsById(
      capability['event'],
      'id',
      '$path Capability event',
    ).keys.toSet();
    final failureIds = _wireObjectsById(
      capability['failure'],
      'id',
      '$path Capability failure',
    ).keys.toSet();

    final operations = _wireCoverageEntries(
      coverage['operations'],
      '$path coverage.operations',
    );
    if (!_sameStringSet(operations.keys.toSet(), operationIds)) {
      errors.add('$path operation coverage 必须覆盖全部 Capability operation');
    }
    const nativeOnlyOperations = {
      'open_media_read',
      'attach_live_preview',
      'detach_live_preview',
      'attach_unconfirmed_preview_render',
      'detach_unconfirmed_preview_render',
    };
    for (final id in operationIds) {
      final entry = operations[id];
      if (entry == null) {
        continue;
      }
      if (nativeOnlyOperations.contains(id)) {
        if (entry['disposition'] != 'native_consumer_only' ||
            entry['wireId'] != null ||
            !_wireNonEmpty(entry['reason']) ||
            methods.containsKey(id)) {
          errors.add('$path operation $id 必须闭合为 native_consumer_only');
        }
      } else if (id == 'copy_confirmed_media_to_sink') {
        if (entry['disposition'] != 'exposed_method' ||
            entry['wireId'] != 'materialize_media_resource' ||
            entry['reason'] != null ||
            !methods.containsKey('materialize_media_resource')) {
          errors.add('$path operation $id 必须映射为 materialize_media_resource');
        }
      } else if (entry['disposition'] != 'exposed_method' ||
          entry['wireId'] != id ||
          entry['reason'] != null ||
          !methods.containsKey(id)) {
        errors.add('$path operation $id coverage 与 method 不一致');
      }
    }

    final results = _wireCoverageEntries(
      coverage['results'],
      '$path coverage.results',
    );
    if (!_sameStringSet(results.keys.toSet(), resultIds)) {
      errors.add('$path result coverage 必须覆盖全部 Capability result');
    }
    for (final id in resultIds) {
      final entry = results[id];
      if (entry == null) {
        continue;
      }
      final payloadId = '${id}_result_payload';
      if (id == 'scoped_media_read') {
        if (entry['disposition'] != 'intentionally_not_exposed' ||
            entry['wireId'] != null ||
            !_wireNonEmpty(entry['reason']) ||
            payloads.containsKey(payloadId)) {
          errors.add('$path scoped_media_read 必须明确为 intentionally_not_exposed');
        }
      } else if (const {
        'render_attachment_attached',
        'render_attachment_detached',
      }.contains(id)) {
        if (entry['disposition'] != 'native_consumer_only' ||
            entry['wireId'] != null ||
            !_wireNonEmpty(entry['reason']) ||
            payloads.containsKey(payloadId)) {
          errors.add('$path result $id 必须闭合为 native_consumer_only');
        }
      } else if (id == 'media_export_result') {
        if (entry['disposition'] != 'mapped_payload' ||
            entry['wireId'] != 'materialized_media_result_payload' ||
            entry['reason'] != null ||
            !payloads.containsKey('materialized_media_result_payload')) {
          errors.add(
            '$path result $id 必须映射为 materialized_media_result_payload',
          );
        }
      } else if (entry['disposition'] != 'mapped_payload' ||
          entry['wireId'] != payloadId ||
          entry['reason'] != null ||
          !payloads.containsKey(payloadId)) {
        errors.add('$path result $id coverage 与 payload 不一致');
      }
    }
    final eventCoverage = _wireCoverageEntries(
      coverage['events'],
      '$path event coverage',
    );
    if (!_sameStringSet(eventCoverage.keys.toSet(), eventIds)) {
      errors.add('$path event coverage 必须覆盖完整 Capability ID 集合');
    }
    for (final id in eventIds) {
      final entry = eventCoverage[id];
      if (entry == null) {
        continue;
      }
      final nativeOnly = id == 'render_attachment_revoked';
      if (nativeOnly) {
        if (entry['disposition'] != 'native_consumer_only' ||
            entry['wireId'] != null ||
            !_wireNonEmpty(entry['reason']) ||
            events.containsKey(id)) {
          errors.add('$path event $id 必须闭合为 native_consumer_only');
        }
      } else if (entry['disposition'] != 'mapped_event' ||
          entry['wireId'] != id ||
          entry['reason'] != null ||
          !events.containsKey(id)) {
        errors.add('$path event $id coverage 与 event 不一致');
      }
    }
    final failureCoverage = _wireCoverageEntries(
      coverage['failures'],
      '$path failure coverage',
    );
    if (!_sameStringSet(failureCoverage.keys.toSet(), failureIds)) {
      errors.add('$path failure coverage 必须覆盖完整 Capability ID 集合');
    }
    for (final id in failureIds) {
      final entry = failureCoverage[id];
      if (entry == null) {
        continue;
      }
      final nativeOnly = const {
        'attachment_generation_retired',
        'attachment_target_conflict',
      }.contains(id);
      if (nativeOnly) {
        if (entry['disposition'] != 'native_consumer_only' ||
            entry['wireId'] != null ||
            !_wireNonEmpty(entry['reason']) ||
            wireErrors.containsKey(id)) {
          errors.add('$path failure $id 必须闭合为 native_consumer_only');
        }
      } else if (entry['disposition'] != 'mapped_error' ||
          entry['wireId'] != id ||
          entry['reason'] != null ||
          !wireErrors.containsKey(id)) {
        errors.add('$path failure $id coverage 与 error 不一致');
      }
    }

    final resourcePolicy = _capabilityObject(
      capability['resourcePolicy'],
      '$path Capability resourcePolicy',
    );
    final capabilityResources = _wireObjectsById(
      resourcePolicy?['resources'],
      'id',
      '$path Capability resources',
    ).keys.toSet();
    final capabilityOwnershipScopes = _wireObjectsById(
      resourcePolicy?['ownershipPhases'],
      'id',
      '$path Capability ownership phases',
    ).keys.toSet();
    final expectedResourceCoverage =
        <String, ({String disposition, String? wireId})>{
          'capture_session': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'captured_media': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'live_preview_attachment': (
            disposition: 'native_consumer_only',
            wireId: null,
          ),
          'unconfirmed_preview_render_attachment': (
            disposition: 'native_consumer_only',
            wireId: null,
          ),
          'thumbnail_generation_job': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'thumbnail_generation_buffer': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'thumbnail_copy': (
            disposition: 'mapped_payload',
            wireId: 'media_thumbnail_result_payload',
          ),
        };
    if (capabilityResources.contains('media_export_job')) {
      expectedResourceCoverage.addAll(const {
        'media_export_job': (
          disposition: 'intentionally_not_exposed',
          wireId: null,
        ),
        'media_export_buffer': (
          disposition: 'intentionally_not_exposed',
          wireId: null,
        ),
      });
    }
    if (capabilityResources.contains('live_platform_render_surface')) {
      expectedResourceCoverage.addAll(const {
        'live_platform_render_surface': (
          disposition: 'native_consumer_only',
          wireId: null,
        ),
        'unconfirmed_platform_render_surface': (
          disposition: 'native_consumer_only',
          wireId: null,
        ),
      });
    }
    _validateWireResourceCoverage(
      coverage['resources'],
      capabilityResources,
      expectedResourceCoverage,
      '$path resource coverage',
    );
    final expectedOwnershipCoverage =
        <String, ({String disposition, String? wireId})>{
          'session_active': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'session_tombstone': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'media_preview': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'media_consumer_lease': (
            disposition: 'mapped_payload',
            wireId: 'confirmed_media_result_payload',
          ),
          'media_read_grace': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'media_tombstone': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'live_preview_render_scope': (
            disposition: 'native_consumer_only',
            wireId: null,
          ),
          'unconfirmed_preview_render_scope': (
            disposition: 'native_consumer_only',
            wireId: null,
          ),
          'thumbnail_generation_job_scope': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
          'thumbnail_generation_buffer_scope': (
            disposition: 'intentionally_not_exposed',
            wireId: null,
          ),
        };
    if (capabilityOwnershipScopes.contains('media_export_job_scope')) {
      expectedOwnershipCoverage.addAll(const {
        'media_export_job_scope': (
          disposition: 'intentionally_not_exposed',
          wireId: null,
        ),
        'media_export_buffer_scope': (
          disposition: 'intentionally_not_exposed',
          wireId: null,
        ),
      });
    }
    if (capabilityOwnershipScopes.contains('live_render_surface_owner_scope')) {
      expectedOwnershipCoverage.addAll(const {
        'live_render_surface_owner_scope': (
          disposition: 'native_consumer_only',
          wireId: null,
        ),
        'unconfirmed_render_surface_owner_scope': (
          disposition: 'native_consumer_only',
          wireId: null,
        ),
      });
    }
    _validateWireResourceCoverage(
      coverage['ownershipScopes'],
      capabilityOwnershipScopes,
      expectedOwnershipCoverage,
      '$path ownership scope coverage',
    );
    final capabilityFields = _wireObjectsById(
      capability['field'],
      'id',
      '$path Capability fields',
    );
    final nativeInputs = _wireObjectsById(
      coverage['nativeInputs'],
      'capabilityId',
      '$path coverage.nativeInputs',
    );
    final expectedNativeInputs = <String>{
      if (capabilityFields.containsKey('media_copy_sink')) 'media_copy_sink',
      if (capabilityFields.containsKey('media_export_max_length'))
        'media_export_max_length',
    };
    if (!_sameStringSet(nativeInputs.keys.toSet(), expectedNativeInputs)) {
      errors.add(
        '$path native input coverage 必须闭合 Adapter 注入的 Capability fields',
      );
    }
    for (final entry in nativeInputs.entries) {
      final input = entry.value;
      final label = '$path native input coverage ${entry.key}';
      _validateCapabilityExactKeys(input, const {
        'capabilityId',
        'disposition',
        'wireId',
        'bindingKind',
        'fixedIntegerValue',
        'reason',
      }, label);
      final validBinding = switch (entry.key) {
        'media_copy_sink' =>
          input['bindingKind'] == 'adapter_native_sink' &&
              input['fixedIntegerValue'] == null,
        'media_export_max_length' =>
          input['bindingKind'] == 'fixed_integer' &&
              input['fixedIntegerValue'] == 52428800,
        _ => false,
      };
      if (input['disposition'] != 'native_consumer_only' ||
          input['wireId'] != null ||
          !_wireNonEmpty(input['reason']) ||
          !validBinding) {
        errors.add('$label 必须声明 native sink 或固定 52428800-byte Adapter binding');
      }
    }
    _validateWireNativeArtifactCoverage(
      coverage['nativeArtifacts'],
      resourcePolicy?['renderSurfaces'],
      path,
    );
  }

  void _validateWireResourceCoverage(
    Object? value,
    Set<String> capabilityIds,
    Map<String, ({String disposition, String? wireId})> expected,
    String label,
  ) {
    final entries = _wireCoverageEntries(value, label);
    if (!_sameStringSet(entries.keys.toSet(), capabilityIds) ||
        !_sameStringSet(entries.keys.toSet(), expected.keys.toSet())) {
      errors.add('$label 必须逐项覆盖 Capability resource ownership 集合');
    }
    for (final id in capabilityIds) {
      final entry = entries[id];
      final expectedEntry = expected[id];
      if (entry == null || expectedEntry == null) {
        continue;
      }
      final requiresReason = expectedEntry.wireId == null;
      if (entry['disposition'] != expectedEntry.disposition ||
          entry['wireId'] != expectedEntry.wireId ||
          (requiresReason
              ? !_wireNonEmpty(entry['reason'])
              : entry['reason'] != null)) {
        errors.add('$label $id 的 disposition/wireId/reason 不闭合');
      }
    }
  }

  void _validateWireNativeArtifactCoverage(
    Object? value,
    Object? renderSurfacesValue,
    String path,
  ) {
    String signature(
      String artifactKind,
      String ownerPolicyId,
      String? platform,
      String capabilityId,
    ) => '$artifactKind|$ownerPolicyId|${platform ?? 'shared'}|$capabilityId';

    final expected = <String>{};
    void expect(
      String artifactKind,
      String ownerPolicyId,
      String? platform,
      String capabilityId,
    ) {
      expected.add(
        signature(artifactKind, ownerPolicyId, platform, capabilityId),
      );
    }

    final renderSurfaces = _capabilityObjectList(
      renderSurfacesValue,
      '$path Capability render surfaces',
    );
    for (final surface in renderSurfaces ?? const <Map<String, Object?>>[]) {
      final ownerPolicyId = surface['id'];
      if (ownerPolicyId is! String) {
        errors.add('$path Capability render surface 缺少稳定 policy ID');
        continue;
      }
      expect('surface_policy', ownerPolicyId, null, ownerPolicyId);
      expect('factory', ownerPolicyId, null, ownerPolicyId);

      final factory = _capabilityObject(
        surface['factoryContract'],
        '$path Capability render surface $ownerPolicyId factoryContract',
      );
      final factoryInputs = _capabilityObjectList(
        factory?['inputBindings'],
        '$path Capability render surface $ownerPolicyId factory inputs',
      );
      for (final input in factoryInputs ?? const <Map<String, Object?>>[]) {
        final roleId = input['roleId'];
        if (roleId is String) {
          expect('factory_input', ownerPolicyId, null, roleId);
        }
      }
      final factoryOutput = _capabilityObject(
        factory?['output'],
        '$path Capability render surface $ownerPolicyId factory output',
      );
      final outputRoleId = factoryOutput?['roleId'];
      if (outputRoleId is String) {
        expect('factory_output', ownerPolicyId, null, outputRoleId);
      }
      final targetFieldId = surface['targetFieldId'];
      if (targetFieldId is String) {
        expect('target_identity', ownerPolicyId, null, targetFieldId);
      }
      final ownerGenerationFieldId = surface['ownerGenerationFieldId'];
      if (ownerGenerationFieldId is String) {
        expect('owner_generation', ownerPolicyId, null, ownerGenerationFieldId);
      }
      final diagnostic = _capabilityObject(
        surface['diagnosticPolicy'],
        '$path Capability render surface $ownerPolicyId diagnosticPolicy',
      );
      final diagnosticId = diagnostic?['id'];
      if (diagnosticId is String) {
        expect('diagnostic', ownerPolicyId, null, diagnosticId);
      }
      final mountSources = _capabilityStringSet(
        surface['mountSourceKindIds'],
        '$path Capability render surface $ownerPolicyId mountSourceKindIds',
      );
      for (final sourceId in mountSources ?? const <String>{}) {
        expect('source', ownerPolicyId, null, sourceId);
      }

      final implementations = _capabilityObjectList(
        surface['platformImplementations'],
        '$path Capability render surface $ownerPolicyId platformImplementations',
      );
      final platforms = <String>{};
      for (final implementation
          in implementations ?? const <Map<String, Object?>>[]) {
        final platform = implementation['platform'];
        if (platform is! String || !platforms.add(platform)) {
          continue;
        }
        expect('platform_surface', ownerPolicyId, platform, ownerPolicyId);
        final conformance = _capabilityObject(
          implementation['targetConformance'],
          '$path Capability $ownerPolicyId $platform targetConformance',
        );
        final conformanceId = conformance?['id'];
        if (conformanceId is String) {
          expect('target_conformance', ownerPolicyId, platform, conformanceId);
        }
        final mountBinding = _capabilityObject(
          implementation['mountBinding'],
          '$path Capability $ownerPolicyId $platform mountBinding',
        );
        final bindingConformanceId = mountBinding?['targetConformanceId'];
        if (bindingConformanceId is String) {
          expect(
            'mount_binding',
            ownerPolicyId,
            platform,
            bindingConformanceId,
          );
        }
        final targets = _capabilityStringSet(
          implementation['actualMountTargetIds'],
          '$path Capability $ownerPolicyId $platform actualMountTargetIds',
        );
        for (final targetId in targets ?? const <String>{}) {
          expect('mount_target', ownerPolicyId, platform, targetId);
        }
        final components = _capabilityStringSet(
          implementation['moduleOwnedRendererIds'],
          '$path Capability $ownerPolicyId $platform moduleOwnedRendererIds',
        );
        for (final componentId in components ?? const <String>{}) {
          final artifactKind = componentId.endsWith('_source')
              ? 'source'
              : componentId.endsWith('_binding')
              ? 'binding'
              : 'renderer';
          expect(artifactKind, ownerPolicyId, platform, componentId);
        }
      }
      if (!_sameStringSet(platforms, const {'android', 'ios'})) {
        errors.add('$path Capability render surface $ownerPolicyId 必须覆盖双平台');
      }
    }

    final entries = _capabilityObjectList(
      value,
      '$path coverage.nativeArtifacts',
    );
    final actual = <String>{};
    const artifactKinds = {
      'surface_policy',
      'factory',
      'factory_input',
      'factory_output',
      'target_identity',
      'owner_generation',
      'platform_surface',
      'target_conformance',
      'mount_binding',
      'mount_target',
      'source',
      'renderer',
      'binding',
      'diagnostic',
    };
    for (final entry in entries ?? const <Map<String, Object?>>[]) {
      _validateCapabilityExactKeys(entry, const {
        'capabilityId',
        'artifactKind',
        'ownerPolicyId',
        'platform',
        'disposition',
        'wireId',
        'reason',
      }, '$path native artifact coverage');
      final capabilityId = entry['capabilityId'];
      final artifactKind = entry['artifactKind'];
      final ownerPolicyId = entry['ownerPolicyId'];
      final platform = entry['platform'];
      if (capabilityId is! String ||
          artifactKind is! String ||
          ownerPolicyId is! String ||
          !artifactKinds.contains(artifactKind) ||
          (platform != null && platform != 'android' && platform != 'ios')) {
        errors.add('$path native artifact coverage 的 ID/kind/platform 不合法');
        continue;
      }
      final itemSignature = signature(
        artifactKind,
        ownerPolicyId,
        platform as String?,
        capabilityId,
      );
      if (!actual.add(itemSignature)) {
        errors.add('$path native artifact coverage 重复：$itemSignature');
      }
      if (entry['disposition'] != 'native_consumer_only' ||
          entry['wireId'] != null ||
          !_wireNonEmpty(entry['reason'])) {
        errors.add('$path native artifact $itemSignature 必须保持 Native-only');
      }
    }
    if (!_sameStringSet(actual, expected)) {
      errors.add(
        '$path native artifact coverage 必须逐项对照 Capability V3 factory/conformance/mount/target/source/renderer/binding/diagnostic',
      );
    }
  }

  void _validateWirePlatformSupport(Object? value, String label) {
    final support = _capabilityObject(value, '$label platformSupport');
    if (support == null) {
      return;
    }
    _validateCapabilityExactKeys(support, const {
      'android',
      'ios',
    }, '$label platformSupport');
    if (support['android'] != 'supported' || support['ios'] != 'supported') {
      errors.add('$label 必须显式支持 Android 与 iOS');
    }
  }

  void _validateWirePlatform(Object? value, String path) {
    final platform = _capabilityObject(value, '$path platform');
    if (platform == null) {
      return;
    }
    _validateCapabilityExactKeys(platform, const {
      'supported',
      'semanticParity',
      'differences',
    }, '$path platform');
    final supported =
        _capabilityStringSet(
          platform['supported'],
          '$path platform.supported',
        ) ??
        <String>{};
    if (!_sameStringSet(supported, const {'android', 'ios'}) ||
        platform['semanticParity'] != 'required') {
      errors.add('$path platform 必须要求 Android/iOS 语义一致');
    }
    final differences = _wireObjectsById(
      platform['differences'],
      'id',
      '$path platform.differences',
    );
    const Map<String, ({String platform, String description})> expected = {
      'android_ui_thread_dispatch': (
        platform: 'android',
        description:
            'The Android Adapter dispatches Channel results and events through the Android main thread.',
      ),
      'ios_main_actor_dispatch': (
        platform: 'ios',
        description:
            'The iOS Adapter dispatches Channel results and events through the main actor or main queue.',
      ),
      'android_private_cache_transfer_root': (
        platform: 'android',
        description:
            'The Android Adapter creates transfer files under a plugin-owned application-private cache transfer root.',
      ),
      'ios_private_cache_transfer_root': (
        platform: 'ios',
        description:
            'The iOS Adapter creates transfer files under a plugin-owned application-private cache transfer root.',
      ),
    };
    if (!_sameStringSet(differences.keys.toSet(), expected.keys.toSet())) {
      errors.add(
        '$path platform differences 必须只描述两端 callback 调度和私有 cache transfer root',
      );
    }
    for (final entry in differences.entries) {
      _validateCapabilityExactKeys(entry.value, const {
        'platform',
        'id',
        'description',
      }, '$path platform difference ${entry.key}');
      if (entry.value['platform'] != expected[entry.key]?.platform ||
          entry.value['description'] != expected[entry.key]?.description) {
        errors.add('$path platform difference ${entry.key} 不完整');
      }
    }
  }

  void _validateWireLifecycle(
    Object? value,
    Map<String, Object?> capability,
    Map<String, Map<String, Object?>> methods,
    String path,
  ) {
    final lifecycle = _capabilityObject(value, '$path lifecycle');
    if (lifecycle == null) {
      return;
    }
    final operations = _wireObjectsById(
      capability['operation'],
      'id',
      '$path Capability operations',
    );
    final failures = _wireObjectsById(
      capability['failure'],
      'id',
      '$path Capability failures',
    );
    final lifecycleContract = _capabilityObject(
      capability['lifecycle'],
      '$path Capability lifecycle',
    );
    final lifecycleRuleIds = _capabilitySemanticEntryIds(
      lifecycleContract?['rules'],
      '$path Capability lifecycle.rules',
    );
    if (!operations.containsKey('release_media') ||
        failures['system_interrupted']?['terminal'] != true ||
        lifecycleRuleIds?.contains('capability_failure') != true) {
      errors.add('$path 生命周期清理依赖的 Capability 语义不存在');
    }
    final hasTransferExport = operations.containsKey(
      'copy_confirmed_media_to_sink',
    );
    _validateCapabilityExactKeys(lifecycle, const {
      'requestEnvelope',
      'resultEnvelope',
      'eventListenEnvelope',
      'eventEnvelope',
      'failureEnvelope',
      'requestIdPolicy',
      'duplicateRequests',
      'methodCompletion',
      'callbackThread',
      'sessionFailedEventCorrelation',
      'listenerPolicy',
      'boundaries',
      'linearizationPolicy',
      'resourceAdoptionPolicies',
      'resultCompletionPolicies',
      'lateResultPolicies',
      'lateCallbackBehavior',
      'eventEncodingFailureBehavior',
      'cancelBehavior',
    }, '$path lifecycle');
    for (final entry in const {
      'requestEnvelope': {'wireVersion', 'requestId', 'payload'},
      'resultEnvelope': {'wireVersion', 'requestId', 'resultType', 'payload'},
      'eventListenEnvelope': {'wireVersion'},
      'eventEnvelope': {'wireVersion', 'eventType', 'payload'},
      'failureEnvelope': {'wireVersion', 'failureType', 'payload'},
    }.entries) {
      final envelope = _capabilityObject(
        lifecycle[entry.key],
        '$path lifecycle.${entry.key}',
      );
      if (envelope == null) {
        continue;
      }
      _validateCapabilityExactKeys(envelope, const {
        'requiredKeys',
        'unknownFieldPolicy',
      }, '$path lifecycle.${entry.key}');
      final requiredKeys =
          _capabilityStringSet(
            envelope['requiredKeys'],
            '$path lifecycle.${entry.key}.requiredKeys',
          ) ??
          <String>{};
      if (!_sameStringSet(requiredKeys, entry.value) ||
          envelope['unknownFieldPolicy'] != 'reject') {
        errors.add('$path lifecycle.${entry.key} 必须固定且拒绝未知字段');
      }
    }
    final requestId = _capabilityObject(
      lifecycle['requestIdPolicy'],
      '$path lifecycle.requestIdPolicy',
    );
    if (requestId != null) {
      _validateCapabilityExactKeys(requestId, const {
        'wireType',
        'minLength',
        'maxLength',
        'pattern',
        'format',
        'logging',
      }, '$path lifecycle.requestIdPolicy');
      if (requestId['wireType'] != 'string' ||
          requestId['minLength'] != 1 ||
          requestId['maxLength'] != 128 ||
          requestId['pattern'] != r'^[A-Za-z0-9_-]{1,128}$' ||
          requestId['format'] != 'ascii_token' ||
          requestId['logging'] != 'redact') {
        errors.add('$path requestId 必须有界且不可记录');
      }
    }
    final duplicate = _capabilityObject(
      lifecycle['duplicateRequests'],
      '$path lifecycle.duplicateRequests',
    );
    if (duplicate != null) {
      _validateCapabilityExactKeys(duplicate, const {
        'key',
        'scope',
        'pending',
        'maxPendingRequests',
        'completedTombstoneSeconds',
        'completed',
        'maxCompletedRequestTombstones',
        'completionSlotReservation',
        'overflow',
        'pendingEviction',
        'completedEvictionBeforeTtl',
        'extendsCapabilityLifetime',
      }, '$path lifecycle.duplicateRequests');
      if (duplicate['key'] != 'requestId' ||
          duplicate['scope'] != 'engine_attachment' ||
          duplicate['pending'] != 'reject_duplicate_request' ||
          duplicate['maxPendingRequests'] != 32 ||
          duplicate['completedTombstoneSeconds'] != 300 ||
          duplicate['completed'] != 'reject_duplicate_request' ||
          duplicate['maxCompletedRequestTombstones'] != 4096 ||
          duplicate['completionSlotReservation'] !=
              'reserve_before_invoking_capability' ||
          duplicate['overflow'] !=
              'reject_bridge_overloaded_without_invoking_capability' ||
          duplicate['pendingEviction'] != 'forbidden' ||
          duplicate['completedEvictionBeforeTtl'] != 'forbidden' ||
          duplicate['extendsCapabilityLifetime'] != false) {
        errors.add('$path duplicate request 策略必须有界且不得延长 Capability 生命周期');
      }
    }
    final listener = _capabilityObject(
      lifecycle['listenerPolicy'],
      '$path lifecycle.listenerPolicy',
    );
    if (listener != null) {
      const expectedListener = {
        'maxActiveSinks': 1,
        'secondListen': 'reject_new_listener_keep_existing_sink',
        'secondListenErrorCode': 'listener_already_active',
        'cancel': 'remove_current_sink',
        'relisten': 'allow_after_cancel_or_terminal_error',
        'generation': 'monotonic_per_successful_listen',
        'lateEvent': 'drop_generation_mismatch',
      };
      _validateCapabilityExactKeys(
        listener,
        expectedListener.keys.toSet(),
        '$path lifecycle.listenerPolicy',
      );
      for (final entry in expectedListener.entries) {
        if (listener[entry.key] != entry.value) {
          errors.add('$path listenerPolicy.${entry.key} 不一致');
        }
      }
    }
    final boundaries = _wireObjectsById(
      lifecycle['boundaries'],
      'id',
      '$path lifecycle.boundaries',
    );
    final expectedBoundaryActions = {
      'engine_detach': {
        '1|attachment_generation|close_generation_reject_new_calls',
        '2|ui_owner_generation|close_generation_reject_new_calls',
        '3|active_presentation_flow|revoke_render_scopes_and_dismiss',
        '4|active_sessions|capability_failure_system_interrupted',
        '5|unconfirmed_previews|detach_revoke_and_cleanup',
        '6|pending_presentation_leases|release_before_drop',
        '7|confirmed_media_leases|release_attachment_leases',
        if (hasTransferExport)
          '8|inflight_transfer_exports|cancel_sink_delete_partial_file_release_capacity',
        if (hasTransferExport)
          '9|active_transfer_exports|delete_registered_transfer_files',
        '${hasTransferExport ? 10 : 8}|event_sink|cancel',
        '${hasTransferExport ? 11 : 9}|active_presentation_slot|release_after_cleanup_if_owned',
        '${hasTransferExport ? 12 : 10}|pending_requests|complete_bridge_unavailable_if_unsettled',
        '${hasTransferExport ? 13 : 11}|late_callbacks|cleanup_resource_before_drop',
        '${hasTransferExport ? 14 : 12}|new_attachment|start_generation_no_inheritance',
      },
      'ui_owner_destroy': {
        '1|ui_owner_generation|close_generation_reject_new_calls',
        '2|active_presentation_flow|revoke_render_scopes_and_dismiss',
        '3|active_sessions|capability_failure_system_interrupted',
        '4|unconfirmed_previews|detach_revoke_and_cleanup',
        '5|pending_presentation_leases|release_before_drop',
        '6|confirmed_media_leases|retain_engine_attachment_leases',
        if (hasTransferExport)
          '7|inflight_transfer_exports|retain_engine_attachment_exports',
        if (hasTransferExport)
          '8|active_transfer_exports|retain_engine_attachment_exports',
        '${hasTransferExport ? 9 : 7}|event_sink|retain_for_engine_attachment',
        '${hasTransferExport ? 10 : 8}|active_presentation_slot|release_after_cleanup_if_owned',
        '${hasTransferExport ? 11 : 9}|pending_requests|complete_bridge_unavailable_if_unsettled',
        '${hasTransferExport ? 12 : 10}|late_callbacks|cleanup_resource_before_drop',
        '${hasTransferExport ? 13 : 11}|new_ui_owner|start_generation_no_session_inheritance',
      },
    };
    if (!_sameStringSet(
      boundaries.keys.toSet(),
      expectedBoundaryActions.keys.toSet(),
    )) {
      errors.add('$path lifecycle 必须精确声明 Engine/UI owner 两类 boundary');
    }
    for (final boundary in boundaries.entries) {
      final label = '$path lifecycle boundary ${boundary.key}';
      _validateCapabilityExactKeys(boundary.value, const {
        'id',
        'description',
        'coordinatorId',
        'actions',
      }, label);
      if (!_wireNonEmpty(boundary.value['description']) ||
          boundary.value['coordinatorId'] != 'bridge_lifecycle_coordinator') {
        errors.add('$label 必须声明 description 并共享生命周期 coordinator');
      }
      final actions = _capabilityObjectList(
        boundary.value['actions'],
        '$label actions',
      );
      final signatures = <String>{};
      final orders = <int>{};
      if (actions != null) {
        for (final action in actions) {
          _validateCapabilityExactKeys(action, const {
            'order',
            'resourceId',
            'actionId',
          }, '$label action');
          final order = action['order'];
          final resourceId = action['resourceId'];
          final actionId = action['actionId'];
          if (order is! int ||
              resourceId is! String ||
              actionId is! String ||
              !orders.add(order) ||
              !signatures.add('$order|$resourceId|$actionId')) {
            errors.add('$label action 必须有唯一顺序和稳定 resource/action ID');
          }
        }
      }
      final expectedActions = expectedBoundaryActions[boundary.key];
      if (expectedActions == null ||
          !_sameStringSet(signatures, expectedActions)) {
        errors.add('$label actions 与 Media Capture Wire V2 不一致');
      }
    }

    final linearization = _capabilityObject(
      lifecycle['linearizationPolicy'],
      '$path lifecycle.linearizationPolicy',
    );
    if (linearization != null) {
      _validateCapabilityExactKeys(linearization, const {
        'coordinatorId',
        'participants',
        'callbackWinOrderId',
        'callbackWinOrder',
        'boundaryWinOrder',
      }, '$path lifecycle.linearizationPolicy');
      final participants =
          _capabilityStringSet(
            linearization['participants'],
            '$path lifecycle.linearizationPolicy.participants',
          ) ??
          <String>{};
      const expectedParticipants = {
        'generation_open_check',
        'owner_generation_open_recheck',
        'presentation_slot_reservation',
        'presentation_cleanup',
        'presentation_lease_settlement',
        'presentation_slot_release',
        'resource_adoption',
        'non_resource_result_decision',
        'exactly_once_completion_decision',
        'boundary_close',
        'boundary_resource_scan',
        'late_result_cleanup',
      };
      const expectedCallbackOrder = [
        'generation_open_recheck',
        'presentation_cleanup_complete_if_owned',
        'resource_adoption_if_required',
        'presentation_lease_settlement_if_owned',
        'presentation_slot_release_if_owned',
        'exactly_once_success_completion',
      ];
      const expectedBoundaryOrder = [
        'boundary_close_generation',
        'boundary_revoke_and_cleanup_presentation_resources',
        'boundary_settle_undelivered_lease',
        'boundary_release_presentation_slot',
        'exactly_once_bridge_unavailable_completion',
        'boundary_scan_registered_resources',
        'late_result_cleanup_before_drop',
      ];
      _capabilityStringSet(
        linearization['callbackWinOrder'],
        '$path lifecycle.linearizationPolicy.callbackWinOrder',
      );
      _capabilityStringSet(
        linearization['boundaryWinOrder'],
        '$path lifecycle.linearizationPolicy.boundaryWinOrder',
      );
      if (linearization['coordinatorId'] != 'bridge_lifecycle_coordinator' ||
          linearization['callbackWinOrderId'] !=
              'presentation_callback_terminal_machine' ||
          !_sameStringSet(participants, expectedParticipants) ||
          !_wireJsonEquals(
            linearization['callbackWinOrder'],
            expectedCallbackOrder,
          ) ||
          !_wireJsonEquals(
            linearization['boundaryWinOrder'],
            expectedBoundaryOrder,
          )) {
        errors.add('$path lifecycle linearization 顺序不一致');
      }
    }

    final adoptions = _wireObjectsById(
      lifecycle['resourceAdoptionPolicies'],
      'id',
      '$path lifecycle.resourceAdoptionPolicies',
    );
    final expectedAdoptions =
        <String, ({String result, String resource, String action})>{
          'session_created_adoption': (
            result: 'session_created',
            resource: 'active_session',
            action: 'register_active_session_before_flutter_completion',
          ),
          'confirmed_media_adoption': (
            result: 'confirmed_media',
            resource: 'attachment_media_lease',
            action: 'register_attachment_lease_before_flutter_completion',
          ),
          'capture_flow_confirmed_adoption': (
            result: 'capture_flow_confirmed',
            resource: 'attachment_media_lease',
            action: 'register_attachment_lease_before_flutter_completion',
          ),
          if (hasTransferExport)
            'materialized_media_resource_adoption': (
              result: 'materialized_media_resource',
              resource: 'active_transfer_export',
              action: 'atomic_commit_register_export_before_flutter_completion',
            ),
        };
    if (!_sameStringSet(
      adoptions.keys.toSet(),
      expectedAdoptions.keys.toSet(),
    )) {
      errors.add('$path lifecycle resource adoption 集合不完整');
    }
    for (final entry in adoptions.entries) {
      final adoption = entry.value;
      final label = '$path resource adoption ${entry.key}';
      _validateCapabilityExactKeys(adoption, const {
        'id',
        'resultType',
        'resourceId',
        'adoptionActionId',
        'coordinatorId',
      }, label);
      final expected = expectedAdoptions[entry.key];
      if (expected == null ||
          adoption['resultType'] != expected.result ||
          adoption['resourceId'] != expected.resource ||
          adoption['adoptionActionId'] != expected.action ||
          adoption['coordinatorId'] != 'bridge_lifecycle_coordinator') {
        errors.add('$label 必须在 Flutter completion 前原子登记资源');
      }
    }

    final completionPolicies = _wireObjectsById(
      lifecycle['resultCompletionPolicies'],
      'resultType',
      '$path lifecycle.resultCompletionPolicies',
    );
    final adoptionByResult = {
      'session_created': 'session_created_adoption',
      'confirmed_media': 'confirmed_media_adoption',
      'capture_flow_confirmed': 'capture_flow_confirmed_adoption',
      if (hasTransferExport)
        'materialized_media_resource': 'materialized_media_resource_adoption',
    };
    final expectedCompletionResults = {
      'session_created',
      'control_applied',
      'recording_started',
      'media_preview',
      'retake_ready',
      'confirmed_media',
      'session_cancelled',
      'media_released',
      'media_thumbnail',
      'capture_flow_confirmed',
      'capture_flow_cancelled',
      if (hasTransferExport) 'materialized_media_resource',
      if (hasTransferExport) 'materialized_media_released',
    };
    if (!_sameStringSet(
      completionPolicies.keys.toSet(),
      expectedCompletionResults,
    )) {
      errors.add('$path resultCompletionPolicies 必须覆盖全部暴露结果');
    }
    for (final entry in completionPolicies.entries) {
      final policy = entry.value;
      final label = '$path result completion ${entry.key}';
      _validateCapabilityExactKeys(policy, const {
        'resultType',
        'coordinatorId',
        'resourceAdoptionPolicyId',
        'callbackWinOrderId',
        'callbackWinActionId',
        'boundaryWinActionId',
      }, label);
      final adoptionId = adoptionByResult[entry.key];
      final isCaptureFlow =
          entry.key == 'capture_flow_confirmed' ||
          entry.key == 'capture_flow_cancelled';
      final expectedCallback = isCaptureFlow
          ? 'run_presentation_callback_terminal_machine'
          : adoptionId == null
          ? 'complete_flutter_once_without_resource_adoption'
          : 'adopt_resource_then_complete_flutter';
      final expectedCallbackOrderId = isCaptureFlow
          ? 'presentation_callback_terminal_machine'
          : null;
      if (policy['coordinatorId'] != 'bridge_lifecycle_coordinator' ||
          policy['resourceAdoptionPolicyId'] != adoptionId ||
          (adoptionId != null && !adoptions.containsKey(adoptionId)) ||
          policy['callbackWinOrderId'] != expectedCallbackOrderId ||
          policy['callbackWinActionId'] != expectedCallback ||
          policy['boundaryWinActionId'] !=
              'cleanup_by_late_result_policy_then_drop_without_flutter_completion') {
        errors.add('$label 与 callback/boundary 原子顺序不一致');
      }
    }

    final presentationPolicy = _capabilityObject(
      methods['present_capture_flow']?['presentationPolicy'],
      '$path present_capture_flow.presentationPolicy',
    );
    final presentationSlotPolicy = _capabilityObject(
      presentationPolicy?['slotPolicy'],
      '$path present_capture_flow.presentationPolicy.slotPolicy',
    );
    final callbackWinOrderId = linearization?['callbackWinOrderId'];
    final confirmedFlowOrderId =
        completionPolicies['capture_flow_confirmed']?['callbackWinOrderId'];
    final cancelledFlowOrderId =
        completionPolicies['capture_flow_cancelled']?['callbackWinOrderId'];
    if (callbackWinOrderId != 'presentation_callback_terminal_machine' ||
        presentationSlotPolicy?['terminalMachineOrderId'] !=
            callbackWinOrderId ||
        confirmedFlowOrderId != callbackWinOrderId ||
        cancelledFlowOrderId != callbackWinOrderId) {
      errors.add(
        '$path presentation terminal、slot release 与 capture-flow completion 必须引用同一 callback machine order',
      );
    }

    final lateResults = _wireObjectsById(
      lifecycle['lateResultPolicies'],
      'resultType',
      '$path lifecycle.lateResultPolicies',
    );
    final expectedLateResults = <String, ({String resource, String action})>{
      'session_created': (
        resource: 'returned_session',
        action: 'capability_failure_system_interrupted_returned_session',
      ),
      'control_applied': (
        resource: 'request_session',
        action:
            'capability_failure_system_interrupted_request_session_if_active',
      ),
      'recording_started': (
        resource: 'request_session',
        action:
            'capability_failure_system_interrupted_request_session_if_active',
      ),
      'media_preview': (
        resource: 'request_session_and_preview',
        action:
            'capability_failure_system_interrupted_request_session_cleanup_preview',
      ),
      'retake_ready': (
        resource: 'request_session',
        action:
            'capability_failure_system_interrupted_request_session_if_active',
      ),
      'confirmed_media': (
        resource: 'returned_media_lease',
        action: 'release_media_returned_lease',
      ),
      'session_cancelled': (
        resource: 'no_live_resource',
        action: 'verify_terminal_then_drop',
      ),
      'media_released': (
        resource: 'no_live_resource',
        action: 'verify_terminal_then_drop',
      ),
      'media_thumbnail': (
        resource: 'returned_thumbnail_copy',
        action: 'wipe_thumbnail_copy_before_drop',
      ),
      'capture_flow_confirmed': (
        resource: 'returned_flow_lease_session_and_preview',
        action: 'release_lease_interrupt_session_cleanup_preview_then_drop',
      ),
      'capture_flow_cancelled': (
        resource: 'flow_session_and_preview',
        action: 'verify_cancel_cleanup_then_drop',
      ),
      if (hasTransferExport)
        'materialized_media_resource': (
          resource: 'returned_transfer_file',
          action: 'delete_transfer_file_before_drop',
        ),
      if (hasTransferExport)
        'materialized_media_released': (
          resource: 'no_live_resource',
          action: 'verify_transfer_tombstone_then_drop',
        ),
    };
    final capabilityResults =
        _wireObjectsById(
            capability['result'],
            'id',
            '$path Capability results',
          ).keys.toSet()
          ..removeAll(const {
            'scoped_media_read',
            'media_export_result',
            'render_attachment_attached',
            'render_attachment_detached',
          })
          ..addAll({
            'capture_flow_confirmed',
            'capture_flow_cancelled',
            if (hasTransferExport) 'materialized_media_resource',
            if (hasTransferExport) 'materialized_media_released',
          });
    if (!_sameStringSet(lateResults.keys.toSet(), capabilityResults) ||
        !_sameStringSet(
          lateResults.keys.toSet(),
          expectedLateResults.keys.toSet(),
        )) {
      errors.add('$path lateResultPolicies 必须覆盖全部暴露 Capability result');
    }
    for (final entry in lateResults.entries) {
      final policy = entry.value;
      final label = '$path late result ${entry.key}';
      _validateCapabilityExactKeys(policy, const {
        'resultType',
        'boundaryIds',
        'resourceId',
        'cleanupActionId',
        'cleanupBeforeDrop',
        'flutterCompletion',
      }, label);
      final boundaryIds =
          _capabilityStringSet(policy['boundaryIds'], '$label boundaryIds') ??
          <String>{};
      final expectedPolicy = expectedLateResults[entry.key];
      if (expectedPolicy == null ||
          !_sameStringSet(boundaryIds, const {
            'engine_detach',
            'ui_owner_destroy',
          }) ||
          policy['resourceId'] != expectedPolicy.resource ||
          policy['cleanupActionId'] != expectedPolicy.action ||
          policy['cleanupBeforeDrop'] != true ||
          policy['flutterCompletion'] !=
              'none_pending_already_bridge_unavailable') {
        errors.add('$label 必须先清理资源再丢弃，且不得二次完成 Flutter');
      }
    }
    const expected = {
      'methodCompletion': 'exactly_once',
      'callbackThread': 'platform_ui_thread',
      'sessionFailedEventCorrelation':
          'independent_session_terminal_notification_never_method_completion',
      'lateCallbackBehavior': 'cleanup_result_then_drop_generation_mismatch',
      'eventEncodingFailureBehavior':
          'terminate_sink_wire_encoding_failed_keep_capability_owned',
      'cancelBehavior': 'capability_result_not_platform_exception',
    };
    for (final entry in expected.entries) {
      if (lifecycle[entry.key] != entry.value) {
        errors.add('$path lifecycle.${entry.key} 与 V2 Wire 语义不一致');
      }
    }
  }

  void _validateWireSecurity(
    Object? value,
    Map<String, Map<String, Object?>> fieldMappings,
    String path,
  ) {
    final security = _capabilityObject(value, '$path security');
    if (security == null) {
      return;
    }
    _validateCapabilityExactKeys(security, const {
      'dataClassifications',
      'policies',
    }, '$path security');
    final classifications = _wireObjectsById(
      security['dataClassifications'],
      'id',
      '$path security.dataClassifications',
    );
    final hasTransferExport = fieldMappings.containsKey('file_uri');
    final expectedClassifications =
        <
          String,
          ({
            Set<String> fields,
            Set<String> wireKeys,
            String classification,
            String policy,
          })
        >{
          'opaque_handles': (
            fields: {'session_handle', 'media_handle'},
            wireKeys: <String>{},
            classification: 'sensitive_identifier',
            policy: 'capability_created_opaque_only',
          ),
          'capture_configuration': (
            fields: {
              'enabled_media_types',
              'preferred_camera',
              'audio_enabled',
              'max_video_duration_millis',
              'flash_mode',
              'normalized_x',
              'normalized_y',
              'zoom_factor',
            },
            wireKeys: <String>{},
            classification: 'user_configuration',
            policy: 'operation_scoped',
          ),
          'capability_snapshot': (
            fields: {
              'active_camera',
              'available_cameras',
              'switch_camera_supported',
              'supported_flash_modes',
              'focus_point_supported',
              'min_zoom_factor',
              'max_zoom_factor',
            },
            wireKeys: <String>{},
            classification: 'operational_metadata',
            policy: 'minimal_metadata_only',
          ),
          'media_metadata': (
            fields: {
              'audio_included',
              'media_type',
              'pixel_width',
              'pixel_height',
              'duration_millis',
              'orientation_degrees',
              'byte_length',
              'lease_expires_at',
            },
            wireKeys: <String>{},
            classification: 'media_metadata',
            policy: 'minimal_metadata_only',
          ),
          'thumbnail_request': (
            fields: {'max_pixel_edge'},
            wireKeys: <String>{},
            classification: 'user_configuration',
            policy: 'operation_scoped',
          ),
          'sanitized_thumbnail_copy': (
            fields: {
              'thumbnail_copy',
              'thumbnail_byte_length',
              'thumbnail_pixel_width',
              'thumbnail_pixel_height',
              'thumbnail_content_type',
              'thumbnail_orientation_degrees',
              'poster_frame_millis',
            },
            wireKeys: <String>{},
            classification: 'sanitized_bounded_media_copy',
            policy: 'confirmed_active_lease_only',
          ),
          'failure_metadata': (
            fields: {'terminal_failure_id'},
            wireKeys: <String>{},
            classification: 'failure_metadata',
            policy: 'allowlisted_only',
          ),
          'protocol_metadata': (
            fields: <String>{},
            wireKeys: {
              'wireVersion',
              'requestId',
              'resultType',
              'eventType',
              'failureType',
            },
            classification: 'protocol_metadata',
            policy: 'allowlisted_only',
          ),
          'native_render_artifacts': (
            fields: <String>{},
            wireKeys: <String>{},
            classification: 'native_lifecycle_resource',
            policy: 'native_consumer_only',
          ),
          if (hasTransferExport)
            'transfer_locator': (
              fields: {'export_handle', 'file_uri', 'expires_at'},
              wireKeys: <String>{},
              classification: 'sensitive_local_locator',
              policy: 'immediate_infrastructure_import_only',
            ),
          if (hasTransferExport)
            'transfer_metadata': (
              fields: {'content_type', 'integrity_sha256'},
              wireKeys: <String>{},
              classification: 'media_metadata',
              policy: 'minimal_metadata_only',
            ),
          if (hasTransferExport)
            'presentation_control': (
              fields: {'presentation_request_id'},
              wireKeys: <String>{},
              classification: 'sensitive_identifier',
              policy: 'originating_client_cancel_only',
            ),
        };
    if (!_sameStringSet(
      classifications.keys.toSet(),
      expectedClassifications.keys.toSet(),
    )) {
      errors.add('$path security data classifications 不完整');
    }
    final classifiedFields = <String>{};
    for (final entry in classifications.entries) {
      final classification = entry.value;
      final label = '$path security classification ${entry.key}';
      _validateCapabilityExactKeys(classification, const {
        'id',
        'description',
        'fieldIds',
        'wireKeys',
        'classification',
        'transferPolicy',
      }, label);
      final fields =
          _capabilityStringSet(classification['fieldIds'], '$label fieldIds') ??
          <String>{};
      final wireKeys =
          _capabilityStringSet(classification['wireKeys'], '$label wireKeys') ??
          <String>{};
      classifiedFields.addAll(fields);
      final expected = expectedClassifications[entry.key];
      if (expected == null ||
          !_sameStringSet(fields, expected.fields) ||
          !_sameStringSet(wireKeys, expected.wireKeys) ||
          classification['classification'] != expected.classification ||
          classification['transferPolicy'] != expected.policy ||
          !_wireNonEmpty(classification['description'])) {
        errors.add('$label 与 Media Capture Wire V2/V3 数据分类不一致');
      }
    }
    if (!_sameStringSet(classifiedFields, fieldMappings.keys.toSet())) {
      errors.add('$path security 必须分类全部 Wire field mappings');
    }
    final policies = _wireObjectsById(
      security['policies'],
      'id',
      '$path security.policies',
    );
    final expectedPolicies = {
      'metadata_opaque_handle_and_bounded_thumbnail_only',
      'capability_created_opaque_handle_only',
      if (!hasTransferExport) 'path_transfer_forbidden',
      'free_form_payload_forbidden',
      'unknown_fields_rejected',
      'error_details_allowlisted',
      'sensitive_logging_redacted',
      'native_render_scope_channel_forbidden',
      'native_render_surface_artifacts_channel_forbidden',
      'native_render_diagnostics_redacted_no_projection',
      'no_native_render_path_bytes_fallback',
      'thumbnail_uint8list_only',
      'thumbnail_length_matches_bytes',
      'thumbnail_upright_jpeg_only',
      'thumbnail_exif_and_source_metadata_stripped',
      'thumbnail_confirmed_active_lease_only',
      'thumbnail_video_poster_deterministic',
      'no_media_path_uri_fallback',
      if (hasTransferExport) 'caller_path_forbidden',
      if (hasTransferExport) 'scoped_transfer_file_uri_only',
      if (hasTransferExport) 'transfer_locator_redacted',
      if (hasTransferExport) 'transfer_capacity_bounded',
      if (hasTransferExport) 'transfer_cleanup_exactly_once',
      if (hasTransferExport) 'source_media_release_order',
      if (hasTransferExport) 'no_raw_media_channel_transfer',
    };
    if (!_sameStringSet(policies.keys.toSet(), expectedPolicies)) {
      errors.add('$path security policies 不完整');
    }
    for (final entry in policies.entries) {
      _validateCapabilityExactKeys(entry.value, const {
        'id',
        'description',
      }, '$path security policy ${entry.key}');
      if (!_wireNonEmpty(entry.value['description'])) {
        errors.add('$path security policy ${entry.key} 必须有说明');
      }
    }
  }

  void _validateWireTransferStore(Object? value, String path) {
    final store = _capabilityObject(value, '$path transferStore');
    if (store == null) {
      errors.add('$path 必须声明 Adapter-owned transfer store');
      return;
    }
    _validateCapabilityExactKeys(store, const {
      'owner',
      'locatorClassification',
      'exportHandlePolicy',
      'fileUriPolicy',
      'resultPolicy',
      'limits',
      'lifecycle',
      'redaction',
      'fileUriGoldenVectors',
      'fileUriLengthGoldenVectors',
    }, '$path transferStore');
    final handlePolicy = _capabilityObject(
      store['exportHandlePolicy'],
      '$path transferStore.exportHandlePolicy',
    );
    final uriPolicy = _capabilityObject(
      store['fileUriPolicy'],
      '$path transferStore.fileUriPolicy',
    );
    final resultPolicy = _capabilityObject(
      store['resultPolicy'],
      '$path transferStore.resultPolicy',
    );
    final limits = _capabilityObject(
      store['limits'],
      '$path transferStore.limits',
    );
    final lifecycle = _capabilityObject(
      store['lifecycle'],
      '$path transferStore.lifecycle',
    );
    final redaction = _capabilityObject(
      store['redaction'],
      '$path transferStore.redaction',
    );
    if (handlePolicy != null) {
      _validateCapabilityExactKeys(handlePolicy, const {
        'ownerScope',
        'generator',
        'minimumEntropyBits',
        'format',
        'minLength',
        'maxLength',
        'lookup',
        'reuse',
        'crossAttachmentUse',
        'logging',
      }, '$path transferStore.exportHandlePolicy');
    }
    if (uriPolicy != null) {
      _validateCapabilityExactKeys(uriPolicy, const {
        'scheme',
        'serialization',
        'lengthUnit',
        'percentEncodingHexCase',
        'maxLength',
        'absolutePath',
        'normalizedPath',
        'emptyHostOnly',
        'rejectUserInfo',
        'rejectPort',
        'rejectQuery',
        'rejectFragment',
        'rejectDotSegments',
        'rejectUnescapedNonAscii',
        'rejectIllegalOrOverlongPercentEncoding',
      }, '$path transferStore.fileUriPolicy');
    }
    if (resultPolicy != null) {
      _validateCapabilityExactKeys(resultPolicy, const {
        'maxByteLength',
        'photoContentType',
        'videoContentType',
        'durationFieldId',
        'integrityFieldId',
        'integrityAlgorithm',
        'integrityEncoding',
        'integrityRequired',
      }, '$path transferStore.resultPolicy');
    }
    if (limits != null) {
      _validateCapabilityExactKeys(limits, const {
        'maxFileBytes',
        'ttlSeconds',
        'maxActiveExportsPerEngineAttachment',
        'maxActiveBytesPerEngineAttachment',
        'releaseTombstoneSeconds',
        'maxReleaseTombstones',
        'releaseTombstoneOverflow',
      }, '$path transferStore.limits');
    }
    if (lifecycle != null) {
      _validateCapabilityExactKeys(lifecycle, const {
        'materializeOrder',
        'releaseOrder',
        'inflightCleanupOrder',
        'activeExportCleanupOrder',
        'restartSweepOrder',
        'cleanupTriggers',
        'releasePendingDuplicatePolicy',
        'releaseTombstoneHitOutcome',
        'releaseUnknownOrExpiredOutcome',
        'deleteFailurePolicy',
        'sourceLeasePolicy',
      }, '$path transferStore.lifecycle');
    }
    if (store['owner'] != 'adapter_owned_app_private_cache_transfer_root' ||
        store['locatorClassification'] != 'sensitive_local_locator') {
      errors.add('$path transferStore 必须由 Adapter 私有 cache root 持有');
    }
    if (handlePolicy?['ownerScope'] != 'engine_attachment' ||
        handlePolicy?['generator'] != 'cryptographically_secure_random' ||
        handlePolicy?['minimumEntropyBits'] != 128 ||
        handlePolicy?['format'] != 'base64url_no_padding' ||
        handlePolicy?['minLength'] != 22 ||
        handlePolicy?['maxLength'] != 64 ||
        handlePolicy?['lookup'] != 'strict_registry_lookup' ||
        handlePolicy?['reuse'] != 'forbidden' ||
        handlePolicy?['crossAttachmentUse'] !=
            'reject_materialized_media_invalid' ||
        handlePolicy?['logging'] != 'redact') {
      errors.add(
        '$path transferStore export handle 必须有 128-bit CSPRNG 与 attachment 隔离',
      );
    }
    if (uriPolicy?['scheme'] != 'file' ||
        uriPolicy?['serialization'] != 'ascii_percent_encoded' ||
        uriPolicy?['lengthUnit'] != 'ascii_code_units' ||
        uriPolicy?['percentEncodingHexCase'] != 'uppercase' ||
        uriPolicy?['maxLength'] != 4096 ||
        uriPolicy?['absolutePath'] != true ||
        uriPolicy?['normalizedPath'] != true ||
        uriPolicy?['emptyHostOnly'] != true ||
        uriPolicy?['rejectUserInfo'] != true ||
        uriPolicy?['rejectPort'] != true ||
        uriPolicy?['rejectQuery'] != true ||
        uriPolicy?['rejectFragment'] != true ||
        uriPolicy?['rejectDotSegments'] != true ||
        uriPolicy?['rejectUnescapedNonAscii'] != true ||
        uriPolicy?['rejectIllegalOrOverlongPercentEncoding'] != true) {
      errors.add('$path transferStore 必须固定 canonical private file URI 边界');
    }
    if (resultPolicy?['maxByteLength'] != 52428800 ||
        resultPolicy?['photoContentType'] != 'image/jpeg' ||
        resultPolicy?['videoContentType'] != 'video/mp4' ||
        resultPolicy?['durationFieldId'] != 'duration_millis' ||
        resultPolicy?['integrityFieldId'] != 'integrity_sha256' ||
        resultPolicy?['integrityAlgorithm'] != 'sha256' ||
        resultPolicy?['integrityEncoding'] != 'lowercase_hex_64' ||
        resultPolicy?['integrityRequired'] != false) {
      errors.add(
        '$path transferStore result 必须闭合 MIME、长度、duration 和 optional SHA-256',
      );
    }
    if (limits?['maxFileBytes'] != 52428800 ||
        limits?['ttlSeconds'] != 300 ||
        limits?['maxActiveExportsPerEngineAttachment'] != 4 ||
        limits?['maxActiveBytesPerEngineAttachment'] != 104857600 ||
        limits?['releaseTombstoneSeconds'] != 300 ||
        limits?['maxReleaseTombstones'] != 4096 ||
        limits?['releaseTombstoneOverflow'] !=
            'reject_transfer_store_overloaded_without_eviction') {
      errors.add('$path transferStore 必须固定容量、TTL 与有界 tombstone');
    }
    if (lifecycle?['releasePendingDuplicatePolicy'] !=
            'join_claimed_cleanup_without_new_reservation_or_side_effects' ||
        lifecycle?['releaseTombstoneHitOutcome'] !=
            'materialized_media_released' ||
        lifecycle?['releaseUnknownOrExpiredOutcome'] !=
            'materialized_media_invalid' ||
        lifecycle?['deleteFailurePolicy'] !=
            'retain_registry_entry_active_capacity_and_tombstone_reservation_retry_same_claim_bounded_without_success' ||
        lifecycle?['sourceLeasePolicy'] !=
            'materialize_and_release_export_do_not_release_source_media') {
      errors.add('$path transferStore 必须固定幂等 release 与 source lease 边界');
    }
    final cleanupTriggers =
        _capabilityStringSet(
          lifecycle?['cleanupTriggers'],
          '$path transferStore.cleanupTriggers',
        ) ??
        <String>{};
    if (!_wireJsonEquals(lifecycle?['materializeOrder'], const [
          'validate_request',
          'reserve_transfer_capacity',
          'create_random_temp_target',
          'invoke_capability_with_adapter_sink',
          'atomic_commit_file',
          'register_export_before_flutter_completion',
        ]) ||
        !_wireJsonEquals(lifecycle?['releaseOrder'], const [
          'validate_export_handle',
          'atomically_claim_cleanup_and_reserve_release_tombstone',
          'delete_transfer_file',
          'remove_export_registry_entry',
          'release_transfer_capacity',
          'record_release_tombstone',
          'complete_flutter_once',
        ]) ||
        !_wireJsonEquals(lifecycle?['inflightCleanupOrder'], const [
          'close_transfer_generation',
          'cancel_capability_export_and_sink',
          'delete_partial_transfer_file',
          'release_transfer_capacity',
          'complete_flutter_once',
        ]) ||
        !_wireJsonEquals(lifecycle?['activeExportCleanupOrder'], const [
          'mark_export_cleanup_pending',
          'delete_transfer_file',
          'remove_export_registry_entry',
          'release_transfer_capacity',
        ]) ||
        !_wireJsonEquals(lifecycle?['restartSweepOrder'], const [
          'close_transfer_generation',
          'delete_all_files_under_private_transfer_root',
          'reset_transfer_registry_and_capacity',
          'open_transfer_generation',
        ]) ||
        !_sameStringSet(cleanupTriggers, const {
          'flutter_completion_failed',
          'engine_detach',
          'app_restart',
          'ttl_expired',
          'cancel',
          'late_capability_result',
        })) {
      errors.add(
        '$path transferStore cleanup 必须覆盖 commit、release、active export、restart、detach、TTL、cancel 和 late result',
      );
    }
    final forbiddenSinks =
        _capabilityStringSet(
          redaction?['forbiddenSinks'],
          '$path transferStore.redaction.forbiddenSinks',
        ) ??
        <String>{};
    final forbiddenDetailKeys =
        _capabilityStringSet(
          redaction?['forbiddenDetailKeys'],
          '$path transferStore.redaction.forbiddenDetailKeys',
        ) ??
        <String>{};
    if (!_sameStringSet(forbiddenSinks, const {
          'logs',
          'error_details',
          'event_payloads',
          'messages',
          'fixtures',
          'routes',
          'analytics',
          'persistent_storage',
        }) ||
        !forbiddenDetailKeys.containsAll(const {
          'fileUri',
          'exportHandle',
          'path',
          'uri',
          'handle',
          'underlyingError',
        })) {
      errors.add('$path transferStore 必须禁止 locator 进入日志、错误、事件、Fixture 和持久化');
    }
    final vectors = _wireObjectsById(
      store['fileUriGoldenVectors'],
      'id',
      '$path transferStore.fileUriGoldenVectors',
    );
    const Map<String, ({String uri, bool valid, String reason})>
    expectedVectors = {
      'absolute_no_authority': (
        uri:
            'file:///var/mobile/Containers/Data/Application/app/Library/Caches/media-transfer/a.bin',
        valid: true,
        reason: 'absolute_normalized_empty_host',
      ),
      'localhost_authority_rejected': (
        uri:
            'file://localhost/var/mobile/Containers/Data/Application/app/Library/Caches/media-transfer/a.bin',
        valid: false,
        reason: 'non_empty_host',
      ),
      'relative_path_rejected': (
        uri: 'file:media-transfer/a.bin',
        valid: false,
        reason: 'not_absolute',
      ),
      'single_slash_absolute_rejected': (
        uri: 'file:/data/user/0/app/cache/media-transfer/a.bin',
        valid: false,
        reason: 'non_canonical_authority_form',
      ),
      'port_rejected': (
        uri: 'file://:123/data/user/0/app/cache/media-transfer/a.bin',
        valid: false,
        reason: 'port',
      ),
      'dot_segment_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/../a.bin',
        valid: false,
        reason: 'dot_segment',
      ),
      'encoded_dot_segment_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/%2E%2E/a.bin',
        valid: false,
        reason: 'encoded_dot_segment',
      ),
      'query_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/a.bin?x=1',
        valid: false,
        reason: 'query',
      ),
      'fragment_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/a.bin#x',
        valid: false,
        reason: 'fragment',
      ),
      'userinfo_rejected': (
        uri: 'file://user@/data/user/0/app/cache/media-transfer/a.bin',
        valid: false,
        reason: 'userinfo',
      ),
      'overlong_percent_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/%C0%AF.bin',
        valid: false,
        reason: 'illegal_percent_encoding',
      ),
      'invalid_percent_triplet_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/%GG.bin',
        valid: false,
        reason: 'illegal_percent_encoding',
      ),
      'encoded_slash_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/a%2Fb.bin',
        valid: false,
        reason: 'encoded_path_separator',
      ),
      'encoded_backslash_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/a%5Cb.bin',
        valid: false,
        reason: 'encoded_path_separator',
      ),
      'nul_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/a%00.bin',
        valid: false,
        reason: 'control_character',
      ),
      'control_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/a%0A.bin',
        valid: false,
        reason: 'control_character',
      ),
      'raw_unicode_rejected': (
        uri: 'file:///data/user/0/app/cache/media-transfer/照片.jpg',
        valid: false,
        reason: 'unescaped_non_ascii',
      ),
      'percent_encoded_unicode_accepted': (
        uri:
            'file:///data/user/0/app/cache/media-transfer/%E7%85%A7%E7%89%87.jpg',
        valid: true,
        reason: 'ascii_percent_encoded_unicode',
      ),
    };
    if (!_sameStringSet(vectors.keys.toSet(), expectedVectors.keys.toSet())) {
      errors.add('$path transferStore 必须声明三端共享 file URI golden vectors');
    }
    for (final entry in vectors.entries) {
      final vector = entry.value;
      _validateCapabilityExactKeys(vector, const {
        'id',
        'uri',
        'valid',
        'reason',
      }, '$path file URI vector ${entry.key}');
      final expected = expectedVectors[entry.key];
      if (expected == null ||
          vector['uri'] != expected.uri ||
          vector['valid'] != expected.valid ||
          vector['reason'] != expected.reason) {
        errors.add('$path file URI vector ${entry.key} 未闭合法恶意样本');
      }
    }
    final lengthVectors = _wireObjectsById(
      store['fileUriLengthGoldenVectors'],
      'id',
      '$path transferStore.fileUriLengthGoldenVectors',
    );
    const expectedLengthVectors = {
      'maximum_length_accepted': (
        totalLength: 4096,
        valid: true,
        reason: 'maximum_length',
      ),
      'over_maximum_length_rejected': (
        totalLength: 4097,
        valid: false,
        reason: 'over_maximum_length',
      ),
    };
    if (!_sameStringSet(
      lengthVectors.keys.toSet(),
      expectedLengthVectors.keys.toSet(),
    )) {
      errors.add('$path transferStore 必须声明 4096/4097 file URI 长度边界');
    }
    for (final entry in lengthVectors.entries) {
      final vector = entry.value;
      _validateCapabilityExactKeys(vector, const {
        'id',
        'totalLength',
        'valid',
        'reason',
      }, '$path file URI length vector ${entry.key}');
      final expected = expectedLengthVectors[entry.key];
      if (expected == null ||
          vector['totalLength'] != expected.totalLength ||
          vector['valid'] != expected.valid ||
          vector['reason'] != expected.reason) {
        errors.add('$path file URI length vector ${entry.key} 未闭合 4096 字符上限');
      }
    }
  }

  void _validateWireChangeLog(Object? value, String path) {
    final entries = _capabilityObjectList(value, '$path changeLog');
    if (entries == null || entries.length != 3) {
      errors.add('$path changeLog 必须包含 Wire V1/V2 历史和当前 Wire V3 记录');
      return;
    }
    final byVersion = <int, Map<String, Object?>>{};
    for (final entry in entries) {
      _validateCapabilityExactKeys(entry, const {
        'wireVersion',
        'compatibleCapabilityVersions',
        'description',
      }, '$path changeLog');
      final version = entry['wireVersion'];
      if (version is int) {
        byVersion[version] = entry;
      }
    }
    final expected = <int, ({List<int> versions, String description})>{
      1: (
        versions: [1],
        description:
            'Initial typed Media Capture mapping with bounded transport, typed error details, listener and host lifecycle policy, and direct Capability failure-emission coverage; callback-scoped native media reads are intentionally not exposed.',
      ),
      2: (
        versions: [2, 3],
        description:
            'Adds a full-screen presentation method and sanitized bounded thumbnail bytes; Capability V3 module-defined render surfaces and internals remain Native-only, so the existing Version 2 Channel shape is unchanged while supporting Capability Versions 2 and 3.',
      ),
      3: (
        versions: [4],
        description:
            'Adds scoped one-time materialize and release methods for Capability V4 bounded export using an Adapter-owned private cache store, plus a request-correlated Adapter presentation dismiss method for Flutter lifecycle cleanup. Transfer uses 128-bit CSPRNG export handles, fixed native sink and length bindings, canonical short-lived file URI locators, closed media metadata, optional SHA-256 integrity, bounded tombstones, and ordered cleanup while preserving Wire V1/V2 history; dismiss is supported by both Android and iOS adapters.',
      ),
    };
    if (byVersion.length != 3 ||
        !byVersion.containsKey(1) ||
        !byVersion.containsKey(2) ||
        !byVersion.containsKey(3)) {
      errors.add('$path changeLog 必须精确保留 Wire V1/V2/V3 版本集合');
    }
    for (final expectedEntry in expected.entries) {
      final entry = byVersion[expectedEntry.key];
      if (entry == null ||
          !_wireJsonEquals(
            entry['compatibleCapabilityVersions'],
            expectedEntry.value.versions,
          ) ||
          entry['description'] != expectedEntry.value.description) {
        errors.add(
          '$path changeLog 必须保留 Wire V1 history，并精确记录 Wire V2 对 Capability V2/V3 的同形兼容',
        );
      }
    }
  }

  Map<String, Map<String, Object?>> _wireCoverageEntries(
    Object? value,
    String label,
  ) {
    final entries = _wireObjectsById(value, 'capabilityId', label);
    for (final entry in entries.entries) {
      _validateCapabilityExactKeys(entry.value, const {
        'capabilityId',
        'disposition',
        'wireId',
        'reason',
      }, '$label ${entry.key}');
      final wireId = entry.value['wireId'];
      if (wireId != null && wireId is! String) {
        errors.add('$label ${entry.key}.wireId 必须是字符串或 null');
      }
      final reason = entry.value['reason'];
      if (reason != null && reason is! String) {
        errors.add('$label ${entry.key}.reason 必须是字符串或 null');
      }
    }
    return entries;
  }

  Map<String, Map<String, Object?>> _wireObjectsById(
    Object? value,
    String idKey,
    String label,
  ) {
    final items = _capabilityObjectList(value, label);
    if (items == null) {
      return {};
    }
    final result = <String, Map<String, Object?>>{};
    for (final item in items) {
      final id = item[idKey];
      if (id is! String || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
        errors.add('$label.$idKey 必须是小写 snake_case 稳定 ID');
      } else if (result.containsKey(id)) {
        errors.add('$label 包含重复 $idKey：$id');
      } else {
        result[id] = item;
      }
    }
    return result;
  }

  Map<String, Map<String, Object?>> _wireObjectsByWireKey(
    Object? value,
    String keyName,
    String label,
  ) {
    final items = _capabilityObjectList(value, label);
    if (items == null) {
      return {};
    }
    final result = <String, Map<String, Object?>>{};
    for (final item in items) {
      final key = item[keyName];
      if (key is! String || !RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(key)) {
        errors.add('$label.$keyName 必须是 lowerCamelCase key');
      } else if (result.containsKey(key)) {
        errors.add('$label 包含重复 $keyName：$key');
      } else {
        result[key] = item;
      }
    }
    return result;
  }

  String _wireLowerCamel(String value) {
    final parts = value.split('_');
    return parts.first +
        parts
            .skip(1)
            .map(
              (part) => part.isEmpty
                  ? part
                  : '${part[0].toUpperCase()}${part.substring(1)}',
            )
            .join();
  }

  bool _wireJsonEquals(Object? left, Object? right) =>
      jsonEncode(left) == jsonEncode(right);

  bool _wireNonEmpty(Object? value) =>
      value is String && value.trim().isNotEmpty;

  Map<String, Object?>? _readNativeArchitectureContract(File file) {
    const startMarker = '<!-- native-architecture-contract:start -->';
    const endMarker = '<!-- native-architecture-contract:end -->';
    final content = file.readAsStringSync();
    final start = content.indexOf(startMarker);
    if (start < 0 || content.indexOf(startMarker, start + 1) >= 0) {
      errors.add('${_relative(file)} 必须包含唯一的原生架构契约 start marker');
      return null;
    }
    final end = content.indexOf(endMarker, start + startMarker.length);
    if (end < 0 || content.indexOf(endMarker, end + 1) >= 0) {
      errors.add('${_relative(file)} 必须包含唯一的原生架构契约 end marker');
      return null;
    }

    final lines = content
        .substring(start + startMarker.length, end)
        .trim()
        .split('\n');
    if (lines.length < 3 ||
        lines.first.trim() != '```json' ||
        lines.last.trim() != '```') {
      errors.add('${_relative(file)} 的原生架构契约必须是 JSON fenced block');
      return null;
    }

    try {
      final decoded = jsonDecode(lines.sublist(1, lines.length - 1).join('\n'));
      if (decoded is! Map<String, Object?>) {
        errors.add('${_relative(file)} 的原生架构契约根节点必须是 JSON Object');
        return null;
      }
      return decoded;
    } on FormatException catch (error) {
      errors.add('${_relative(file)} 的原生架构契约不是有效 JSON：${error.message}');
      return null;
    }
  }

  void _validateNativeArchitectureHosts(Object? value) {
    const pathByPlatform = {
      'android': 'app/apps/demo/android/',
      'ios': 'app/apps/demo/ios/',
    };
    final hosts = _nativeContractObjectList(value, 'hosts');
    if (hosts == null) {
      return;
    }
    if (hosts.length != pathByPlatform.length) {
      errors.add('docs/native-architecture.md 的 hosts 必须只声明 Android/iOS Host');
    }

    final seenPlatforms = <String>{};
    for (final host in hosts) {
      _validateExactJsonKeys(host, const {
        'platform',
        'path',
        'status',
      }, 'hosts entry');
      final platform = host['platform'];
      final path = host['path'];
      if (platform is! String || !pathByPlatform.containsKey(platform)) {
        errors.add(
          'docs/native-architecture.md 的 Host platform 必须是 android 或 ios',
        );
        continue;
      }
      if (!seenPlatforms.add(platform)) {
        errors.add('docs/native-architecture.md 的 hosts 重复声明：$platform');
      }
      final expectedPath = pathByPlatform[platform]!;
      if (path != expectedPath) {
        errors.add(
          'docs/native-architecture.md 的 $platform Host path 必须是 $expectedPath',
        );
      } else {
        _validateImplementedDirectory(expectedPath, '$platform Host');
      }
      if (host['status'] != 'implemented') {
        errors.add(
          'docs/native-architecture.md 的 $platform Host 必须标记 implemented',
        );
      }
    }
    for (final platform in pathByPlatform.keys) {
      if (!seenPlatforms.contains(platform)) {
        errors.add('docs/native-architecture.md 的 hosts 缺少：$platform');
      }
    }
  }

  void _validateNativeModules(Object? value) {
    final modules = _nativeContractObjectList(value, 'nativeModules');
    if (modules == null) {
      return;
    }
    for (final module in modules) {
      _validateExactJsonKeys(module, const {
        'platform',
        'path',
        'status',
      }, 'nativeModules entry');
      final platform = module['platform'];
      final path = module['path'];
      final validPath = switch (platform) {
        'android' =>
          path is String &&
              RegExp(r'^app/native/android/[a-z][a-z0-9_-]*/$').hasMatch(path),
        'ios' =>
          path is String &&
              RegExp(
                r'^app/native/ios/[A-Za-z][A-Za-z0-9_-]*/$',
              ).hasMatch(path),
        _ => false,
      };
      if (!validPath) {
        errors.add('docs/native-architecture.md 的 Native Module 必须声明匹配平台的具体路径');
      } else {
        _validateImplementedDirectory(path as String, 'Native Module');
      }
      if (module['status'] != 'implemented') {
        errors.add(
          'docs/native-architecture.md 的 Native Module 必须标记 implemented',
        );
      }
    }
  }

  void _validateNativeBridgePackages(Object? value) {
    final packages = _nativeContractObjectList(value, 'bridgePackages');
    if (packages == null) {
      return;
    }
    for (final package in packages) {
      _validateExactJsonKeys(package, const {
        'path',
        'status',
      }, 'bridgePackages entry');
      final path = package['path'];
      if (path is! String ||
          !RegExp(r'^app/packages/app_[a-z0-9_]+_bridge/$').hasMatch(path)) {
        errors.add('docs/native-architecture.md 的 Bridge Package 路径无效');
      } else {
        _validateImplementedDirectory(path, 'Bridge Package');
      }
      if (package['status'] != 'implemented') {
        errors.add(
          'docs/native-architecture.md 的 Bridge Package 必须标记 implemented',
        );
      }
    }
  }

  void _validateNativeLayoutTemplates(Object? value) {
    if (value is! Map<String, Object?>) {
      errors.add(
        'docs/native-architecture.md 的 layoutTemplates 必须是 JSON Object',
      );
      return;
    }
    const expected = {
      'androidNativeModule': 'app/native/android/<module>/',
      'iosNativeModule': 'app/native/ios/<Module>/',
      'flutterBridgePackage': 'app/packages/app_<capability>_bridge/',
    };
    _validateExactJsonKeys(value, expected.keys.toSet(), 'layoutTemplates');
    for (final template in expected.entries) {
      if (value[template.key] != template.value) {
        errors.add(
          'docs/native-architecture.md 的 ${template.key} 模板必须是 ${template.value}',
        );
      }
    }
  }

  void _validateNativeComponents(Object? value) {
    const required = {
      'host',
      'native_module',
      'dart_client',
      'android_bridge_adapter',
      'ios_bridge_adapter',
    };
    final components = _jsonStringSet(value);
    if (components == null) {
      errors.add('docs/native-architecture.md 的 components 必须是字符串列表');
      return;
    }
    if (value is List<Object?> && components.length != value.length) {
      errors.add('docs/native-architecture.md 的 components 不得重复');
    }
    for (final component in required) {
      if (!components.contains(component)) {
        errors.add('docs/native-architecture.md 的 components 缺少：$component');
      }
    }
    for (final component in components.difference(required)) {
      errors.add('docs/native-architecture.md 的 components 包含未知项：$component');
    }
  }

  Set<String>? _nativeDependencyEdges(Object? value, String field) {
    final items = _nativeContractObjectList(value, field);
    if (items == null) {
      return null;
    }
    final edges = <String>{};
    for (final item in items) {
      _validateExactJsonKeys(item, const {'from', 'to'}, '$field entry');
      final from = item['from'];
      final to = item['to'];
      if (from is! String || from.isEmpty || to is! String || to.isEmpty) {
        errors.add('docs/native-architecture.md 的 $field 必须声明非空 from/to');
        continue;
      }
      final edge = '$from->$to';
      if (!edges.add(edge)) {
        errors.add('docs/native-architecture.md 的 $field 不得重复：$edge');
      }
    }
    return edges;
  }

  List<Map<String, Object?>>? _nativeContractObjectList(
    Object? value,
    String field,
  ) {
    if (value is! List<Object?>) {
      errors.add('docs/native-architecture.md 的 $field 必须是 JSON Array');
      return null;
    }
    final result = <Map<String, Object?>>[];
    for (final item in value) {
      if (item is! Map<String, Object?>) {
        errors.add('docs/native-architecture.md 的 $field 元素必须是 JSON Object');
      } else {
        result.add(item);
      }
    }
    return result;
  }

  void _validateExactJsonKeys(
    Map<String, Object?> value,
    Set<String> expected,
    String label,
  ) {
    final actual = value.keys.toSet();
    for (final key in expected.difference(actual)) {
      errors.add('docs/native-architecture.md 的 $label 缺少字段：$key');
    }
    for (final key in actual.difference(expected)) {
      errors.add('docs/native-architecture.md 的 $label 包含未知字段：$key');
    }
  }

  void _validateImplementedDirectory(String path, String label) {
    if (!_directory(path).existsSync()) {
      errors.add('docs/native-architecture.md 声明的 $label 实现路径不存在：$path');
    }
  }

  String? _markdownLevelTwoSection(String content, String heading) {
    final lines = content.split('\n');
    final start = lines.indexWhere((line) => line.trim() == '## $heading');
    if (start < 0) {
      return null;
    }
    final relativeEnd = lines
        .skip(start + 1)
        .toList()
        .indexWhere((line) => RegExp(r'^##\s+\S').hasMatch(line.trim()));
    final end = relativeEnd < 0 ? lines.length : start + 1 + relativeEnd;
    return lines.sublist(start + 1, end).join('\n');
  }

  bool _linksTo(File source, File target) {
    return _contentLinksTo(source, source.readAsStringSync(), target);
  }

  bool _contentLinksTo(File source, String content, File target) {
    final expected = target.uri.normalizePath();
    return _markdownLinkTargets(content).any((rawTarget) {
      if (_isExternalMarkdownTarget(rawTarget)) {
        return false;
      }
      final path = rawTarget.split('#').first;
      return path.isNotEmpty &&
          source.parent.uri.resolve(path).normalizePath() == expected;
    });
  }

  void _validateMarkdownLinks() {
    for (final file in _markdownFiles(root)) {
      final content = file.readAsStringSync();
      for (var target in _markdownLinkTargets(content)) {
        if (_isExternalMarkdownTarget(target)) {
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

  Iterable<String> _markdownLinkTargets(String content) sync* {
    final link = RegExp(r'!?\[[^\]]*\]\(([^)]+)\)');
    for (final match in link.allMatches(content)) {
      var target = match.group(1)!.trim();
      if (target.startsWith('<') && target.contains('>')) {
        target = target.substring(1, target.indexOf('>'));
      } else {
        target = target.split(RegExp(r'\s+')).first;
      }
      yield target;
    }
  }

  bool _isExternalMarkdownTarget(String target) =>
      target.startsWith('http://') ||
      target.startsWith('https://') ||
      target.startsWith('mailto:') ||
      target.startsWith('#');

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
          if (entry.key == 'get') {
            _validateGetxDependency(
              pubspec,
              '$section.${entry.key}',
              entry.value,
            );
          }
          _validateDependencySource(
            pubspec,
            '$section.${entry.key}',
            entry.value,
          );
        }
      }
    }
  }

  void _validateGetxDependency(File pubspec, String name, Object? value) {
    const expectedUrl = 'https://github.com/bladeofgod/getx.git';
    const expectedRef = '7bfcd9c3711c8880ee730579724dabe54f4e2598';
    final relative = _relative(pubspec);
    final git = value is YamlMap ? value['git'] : null;
    if (git is! YamlMap ||
        git['url'] != expectedUrl ||
        git['ref'] != expectedRef) {
      errors.add('$relative 的 $name 必须使用仓库约定的 GetX 精简 fork，并锁定完整 Commit');
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

  String _relativeEntity(FileSystemEntity entity) => entity.path
      .substring(root.path.length)
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^/'), '');

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
