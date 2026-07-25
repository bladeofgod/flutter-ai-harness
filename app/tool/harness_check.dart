import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'codex_adapters.dart';
import 'implementation_digest.dart';

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
    );
    _validateCiBuildJob(
      jobs,
      relativePath,
      name: 'ios-build',
      runnerPrefix: 'macos-',
      command:
          'TOOL_WORKDIR=app/apps/demo bash scripts/flutter-tool.sh '
          'build ios --debug --no-codesign',
    );
  }

  void _validateCiBuildJob(
    YamlMap jobs,
    String path, {
    required String name,
    required String runnerPrefix,
    required String command,
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
      }
    }, nestedEntry: 'SKILL.md');
    _validateDefinitions('.claude/agents', _agents, (file, metadata) {
      _requireString(file, metadata, 'name');
      _requireString(file, metadata, 'description');
      _requireStringOrList(file, metadata, 'tools');
      _validateAgentSkillReferences(file, metadata);
      _validateSecurityReviewerTools(file, metadata);
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

  void _validateSecurityReviewerTools(File file, YamlMap metadata) {
    if (metadata['name'] != 'security-reviewer') {
      return;
    }
    final tools = _toolNames(metadata['tools']);
    if (tools == null ||
        tools.isEmpty ||
        tools.any((tool) => !const {'Read', 'Grep', 'Glob'}.contains(tool))) {
      errors.add(
        '${_relative(file)} 只能使用 Read、Grep、Glob，'
        '不得获得 Bash 或写入工具',
      );
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
    if (!tasks.existsSync()) {
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

    for (final entity in tasks.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final name = _basename(entity.path);
      if (name != 'done') {
        errors.add('docs/tasks/ 只允许 done 子目录：docs/tasks/$name');
      }
    }

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
          !const {'task-executor', 'bridge-engineer'}.contains(executor) ||
          !_agents.contains(executor)) {
        errors.add('$relative 的 executor 必须是 task-executor 或 bridge-engineer');
      }
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

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
}
