import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:yaml/yaml.dart';

const _allowedDependencies = <String, Set<String>>{
  'app_core': {},
  'app_ui': {},
  'app_data': {'app_core'},
  'app_media': {'app_core', 'app_ui'},
  'app_media_capture_bridge': {},
  'app_features': {
    'app_core',
    'app_data',
    'app_media',
    'app_media_capture_bridge',
    'app_ui',
  },
  'demo_app': {'app_data', 'app_features', 'app_ui'},
};

void main(List<String> arguments) {
  final options = _parseOptions(arguments);
  try {
    final graph = _readGraph(options);
    final result = checkPackageDependencies(
      graph,
      workspaceRoot: options.checkConsumption
          ? Directory(options.workspaceRoot!)
          : null,
      pluginDiscovery: options.pluginDiscovery == null
          ? null
          : File(options.pluginDiscovery!),
      checkConsumption: options.checkConsumption,
    );
    if (!result.isValid) {
      for (final diagnostic in result.diagnostics) {
        stderr.writeln('错误：$diagnostic');
      }
      exitCode = 1;
      return;
    }
    stdout.writeln(
      options.checkConsumption
          ? '[lint] Workspace Package 依赖消费检查通过。'
          : '[lint] Workspace Package 依赖矩阵检查通过。',
    );
  } on FormatException {
    stderr.writeln('错误：依赖检查输入格式无效。');
    exitCode = 1;
  } on FileSystemException {
    stderr.writeln('错误：依赖检查输入不可用。');
    exitCode = 1;
  }
}

PackageDependencyCheckResult checkPackageDependencies(
  Map<String, Object?> document, {
  Directory? workspaceRoot,
  File? pluginDiscovery,
  bool checkConsumption = false,
}) {
  final graph = _DependencyGraph.fromDocument(document);
  final diagnostics = _validateMatrix(graph);
  if (checkConsumption) {
    if (workspaceRoot == null) {
      throw const FormatException('Workspace root is required.');
    }
    diagnostics.addAll(
      _validateConsumption(
        graph,
        workspaceRoot,
        pluginDiscovery: pluginDiscovery,
      ),
    );
  }
  return PackageDependencyCheckResult(diagnostics);
}

final class PackageDependencyCheckResult {
  PackageDependencyCheckResult(Iterable<String> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);

  final List<String> diagnostics;

  bool get isValid => diagnostics.isEmpty;
}

List<String> _validateMatrix(_DependencyGraph graph) {
  final diagnostics = <String>[];
  final unknown = graph.workspacePackages.keys.toSet()
    ..removeAll(_allowedDependencies.keys);
  if (unknown.isNotEmpty) {
    diagnostics.add(
      '以下 Workspace Package 尚未加入依赖矩阵：'
      '${(unknown.toList()..sort()).join(', ')}',
    );
  }

  for (final entry in _allowedDependencies.entries) {
    final package = graph.workspacePackages[entry.key];
    if (package == null) {
      diagnostics.add('依赖图缺少 Workspace Package：${entry.key}');
      continue;
    }
    final workspaceDependencies = <String>{
      ...package.directDependencies,
      ...package.devDependencies,
    }..retainAll(graph.workspacePackages.keys);
    final forbidden = workspaceDependencies.difference(entry.value);
    if (forbidden.isNotEmpty) {
      diagnostics.add(
        '${entry.key} 不得依赖 ${(forbidden.toList()..sort()).join(', ')}',
      );
    }
  }
  return diagnostics;
}

List<String> _validateConsumption(
  _DependencyGraph graph,
  Directory workspaceRoot, {
  File? pluginDiscovery,
}) {
  final workspace = _Workspace.load(workspaceRoot, graph.workspacePackages);
  final discovery = pluginDiscovery == null
      ? null
      : _PluginDiscovery.load(pluginDiscovery);
  final usages = <String, _PackageUsage>{};
  final diagnostics = <String>[];

  for (final package in workspace.packages.values) {
    final usage = _scanPackage(package, graph.allPackageNames);
    usages[package.name] = usage;
    for (final unknown in usage.unknownPackages) {
      diagnostics.add('${package.name} 的源码引用未知 Package：$unknown');
    }
  }

  final realIncoming = <String, Set<String>>{
    for (final package in workspace.packages.keys) package: <String>{},
  };
  for (final owner in workspace.packages.values) {
    final usage = usages[owner.name]!;
    for (final target in {...usage.production, ...usage.development}) {
      if (target != owner.name && realIncoming.containsKey(target)) {
        realIncoming[target]!.add(owner.name);
      }
    }

    final packageGraph = graph.workspacePackages[owner.name]!;
    final productionWorkspaceDependencies =
        packageGraph.directDependencies
            .where(workspace.packages.containsKey)
            .toList()
          ..sort();
    for (final dependency in productionWorkspaceDependencies) {
      if (usage.production.contains(dependency)) {
        continue;
      }
      final target = workspace.packages[dependency]!;
      final pluginEvidence = owner.isApplication && target.isPlugin
          ? discovery?.supports(target) ?? false
          : false;
      final hasAlternatePluginPath =
          pluginEvidence &&
          packageGraph.directDependencies.any(
            (candidate) =>
                candidate != dependency &&
                graph.isReachable(candidate, dependency),
          );

      if (hasAlternatePluginPath) {
        diagnostics.add(
          '${owner.name} 的 Plugin 直连依赖可通过其它生产依赖到达：'
          '$dependency',
        );
      } else if (pluginEvidence) {
        realIncoming[dependency]!.add(owner.name);
      } else if (usage.development.contains(dependency)) {
        diagnostics.add(
          '${owner.name} 的 production dependency 仅被测试/工具源码消费：'
          '$dependency',
        );
      } else {
        diagnostics.add(
          '${owner.name} 的 production dependency 未被生产源码消费：'
          '$dependency',
        );
      }
    }

    final developmentWorkspaceDependencies = packageGraph.devDependencies.where(
      workspace.packages.containsKey,
    );
    for (final dependency in developmentWorkspaceDependencies) {
      if (usage.production.contains(dependency)) {
        diagnostics.add('${owner.name} 的 dev dependency 被生产源码消费：$dependency');
      } else if (!usage.development.contains(dependency)) {
        diagnostics.add(
          '${owner.name} 的 dev dependency 未被测试/工具源码消费：$dependency',
        );
      }
    }
  }

  for (final package in workspace.packages.values) {
    if (realIncoming[package.name]!.isEmpty &&
        !package.isApplication &&
        !package.hasToolEntry &&
        !package.isPlugin &&
        !package.isGenerator) {
      diagnostics.add('Workspace Package 无消费者：${package.name}');
    }
  }

  diagnostics.sort();
  return diagnostics;
}

_PackageUsage _scanPackage(
  _WorkspacePackage package,
  Set<String> knownPackages,
) {
  final production = <String>{};
  final development = <String>{};
  final unknown = <String>{};
  _scanSourceRoots(package, const ['lib'], production, unknown, knownPackages);
  _scanSourceRoots(
    package,
    const ['test', 'tool', 'bin'],
    development,
    unknown,
    knownPackages,
  );
  return _PackageUsage(
    production: production,
    development: development,
    unknownPackages: unknown,
  );
}

void _scanSourceRoots(
  _WorkspacePackage package,
  List<String> roots,
  Set<String> consumers,
  Set<String> unknown,
  Set<String> knownPackages,
) {
  for (final rootName in roots) {
    final root = Directory.fromUri(package.directory.uri.resolve('$rootName/'));
    if (!root.existsSync()) {
      continue;
    }
    final files =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => _isScannableDartFile(root, file))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final unit = parseString(content: file.readAsStringSync()).unit;
      for (final directive in unit.directives.whereType<NamespaceDirective>()) {
        final uris = <String?>[
          directive.uri.stringValue,
          ...directive.configurations.map(
            (configuration) => configuration.uri.stringValue,
          ),
        ];
        for (final uri in uris) {
          final packageName = _packageNameFromUri(uri);
          if (packageName == null) {
            continue;
          }
          if (knownPackages.contains(packageName)) {
            consumers.add(packageName);
          } else {
            unknown.add(packageName);
          }
        }
      }
    }
  }
}

bool _isScannableDartFile(Directory root, File file) {
  if (!file.path.endsWith('.dart')) {
    return false;
  }
  final relative = file.uri.path.substring(root.uri.path.length);
  final segments = relative.split('/');
  if (segments.any(
    (segment) =>
        segment == 'build' || segment == 'generated' || segment == '.dart_tool',
  )) {
    return false;
  }
  final name = segments.last;
  return !name.endsWith('.g.dart') &&
      !name.endsWith('.freezed.dart') &&
      !name.endsWith('.gen.dart');
}

String? _packageNameFromUri(String? value) {
  if (value == null || !value.startsWith('package:')) {
    return null;
  }
  final separator = value.indexOf('/', 'package:'.length);
  if (separator <= 'package:'.length) {
    return null;
  }
  return value.substring('package:'.length, separator);
}

final class _PackageUsage {
  const _PackageUsage({
    required this.production,
    required this.development,
    required this.unknownPackages,
  });

  final Set<String> production;
  final Set<String> development;
  final Set<String> unknownPackages;
}

final class _Workspace {
  const _Workspace(this.packages);

  final Map<String, _WorkspacePackage> packages;

  factory _Workspace.load(
    Directory root,
    Map<String, _GraphPackage> graphPackages,
  ) {
    final canonicalRoot = Directory(root.resolveSymbolicLinksSync());
    final rootDocument = _yamlMap(
      loadYaml(
        _readRegularFile(
          File.fromUri(canonicalRoot.uri.resolve('pubspec.yaml')),
        ),
      ),
      'root pubspec',
    );
    final workspaceEntries = _stringList(rootDocument['workspace']);
    final packages = <String, _WorkspacePackage>{};
    for (final relativePath in workspaceEntries) {
      _validateWorkspacePath(relativePath);
      final unresolved = Directory.fromUri(
        canonicalRoot.uri.resolve('$relativePath/'),
      );
      if (FileSystemEntity.typeSync(unresolved.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const FormatException('Workspace entry is not a directory.');
      }
      final directory = Directory(unresolved.resolveSymbolicLinksSync());
      if (!_isInside(canonicalRoot, directory)) {
        throw const FormatException('Workspace entry escapes root.');
      }
      final pubspec = _yamlMap(
        loadYaml(
          _readRegularFile(File.fromUri(directory.uri.resolve('pubspec.yaml'))),
        ),
        'package pubspec',
      );
      final name = pubspec['name'];
      if (name is! String || name.isEmpty || packages.containsKey(name)) {
        throw const FormatException('Workspace package name is invalid.');
      }
      packages[name] = _WorkspacePackage(
        name: name,
        relativePath: relativePath,
        directory: directory,
        document: pubspec,
      );
    }
    if (!packages.keys.toSet().containsAll(graphPackages.keys) ||
        !graphPackages.keys.toSet().containsAll(packages.keys)) {
      throw const FormatException('Workspace paths do not match graph.');
    }
    return _Workspace(Map.unmodifiable(packages));
  }
}

final class _WorkspacePackage {
  const _WorkspacePackage({
    required this.name,
    required this.relativePath,
    required this.directory,
    required this.document,
  });

  final String name;
  final String relativePath;
  final Directory directory;
  final Map<Object?, Object?> document;

  bool get isApplication => relativePath.split('/').first == 'apps';

  bool get hasToolEntry =>
      _containsDartFile(directory, 'bin') ||
      _containsDartFile(directory, 'tool') ||
      document['executables'] is Map<Object?, Object?>;

  bool get isGenerator =>
      File.fromUri(directory.uri.resolve('build.yaml')).existsSync() ||
      document['builders'] is Map<Object?, Object?>;

  Set<String> get pluginPlatforms {
    final flutter = _optionalYamlMap(document['flutter']);
    final plugin = _optionalYamlMap(flutter?['plugin']);
    final platforms = _optionalYamlMap(plugin?['platforms']);
    if (platforms == null) {
      return const {};
    }
    return platforms.keys.whereType<String>().toSet();
  }

  bool get isPlugin => pluginPlatforms.isNotEmpty;
}

bool _containsDartFile(Directory package, String relativePath) {
  final directory = Directory.fromUri(package.uri.resolve('$relativePath/'));
  return directory.existsSync() &&
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .any((file) => _isScannableDartFile(directory, file));
}

void _validateWorkspacePath(String value) {
  final segments = value.split('/');
  if (value.isEmpty ||
      File(value).isAbsolute ||
      value.contains('\\') ||
      segments.contains('..') ||
      segments.contains('.') ||
      segments.any((segment) => segment.isEmpty)) {
    throw const FormatException('Workspace path is invalid.');
  }
}

bool _isInside(Directory root, Directory child) =>
    child.path.startsWith('${root.path}${Platform.pathSeparator}');

String _readRegularFile(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Expected a regular file.');
  }
  return file.readAsStringSync();
}

final class _PluginDiscovery {
  const _PluginDiscovery(this.document);

  final Map<String, Object?> document;

  factory _PluginDiscovery.load(File file) {
    final decoded = jsonDecode(_readRegularFile(file));
    return _PluginDiscovery(_jsonMap(decoded, 'plugin discovery'));
  }

  bool supports(_WorkspacePackage package) {
    final requiredPlatforms =
        package.pluginPlatforms
            .where((platform) => platform == 'android' || platform == 'ios')
            .toList()
          ..sort();
    if (requiredPlatforms.isEmpty) {
      return false;
    }
    final plugins = _jsonMap(document['plugins'], 'plugins');
    for (final platform in requiredPlatforms) {
      final entries = _jsonList(plugins[platform], 'plugins platform')
          .map((entry) => _jsonMap(entry, 'plugin entry'))
          .where((entry) => entry['name'] == package.name)
          .toList();
      if (entries.length != 1) {
        return false;
      }
      final entry = entries.single;
      if (entry['native_build'] != true || entry['dev_dependency'] != false) {
        return false;
      }
      final path = entry['path'];
      if (path is! String ||
          Directory(path).resolveSymbolicLinksSync() !=
              package.directory.resolveSymbolicLinksSync()) {
        return false;
      }
    }
    final graphEntries =
        _jsonList(document['dependencyGraph'], 'dependency graph')
            .map((entry) => _jsonMap(entry, 'dependency graph entry'))
            .where((entry) => entry['name'] == package.name)
            .toList();
    return graphEntries.length == 1;
  }
}

final class _DependencyGraph {
  const _DependencyGraph({
    required this.rootName,
    required this.packages,
    required this.workspacePackages,
  });

  final String rootName;
  final Map<String, _GraphPackage> packages;
  final Map<String, _GraphPackage> workspacePackages;

  Set<String> get allPackageNames => packages.keys.toSet();

  factory _DependencyGraph.fromDocument(Map<String, Object?> document) {
    final rootName = document['root'];
    if (rootName is! String || rootName.isEmpty) {
      throw const FormatException('Dependency graph root is invalid.');
    }
    final packages = <String, _GraphPackage>{};
    for (final value in _jsonList(document['packages'], 'packages')) {
      final package = _GraphPackage.fromMap(_jsonMap(value, 'package'));
      if (packages.containsKey(package.name)) {
        throw const FormatException('Dependency graph package is duplicated.');
      }
      packages[package.name] = package;
    }
    final workspacePackages = <String, _GraphPackage>{};
    for (final package in packages.values) {
      if (package.name != rootName &&
          package.kind == 'root' &&
          package.source == 'root') {
        workspacePackages[package.name] = package;
      }
    }
    return _DependencyGraph(
      rootName: rootName,
      packages: Map.unmodifiable(packages),
      workspacePackages: Map.unmodifiable(workspacePackages),
    );
  }

  bool isReachable(String start, String target) {
    final pending = <String>[start];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) {
        continue;
      }
      if (current == target) {
        return true;
      }
      pending.addAll(packages[current]?.directDependencies ?? const []);
    }
    return false;
  }
}

final class _GraphPackage {
  const _GraphPackage({
    required this.name,
    required this.kind,
    required this.source,
    required this.directDependencies,
    required this.devDependencies,
  });

  final String name;
  final String? kind;
  final String? source;
  final Set<String> directDependencies;
  final Set<String> devDependencies;

  factory _GraphPackage.fromMap(Map<String, Object?> value) {
    final name = value['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('Dependency graph package name is invalid.');
    }
    final kind = value['kind'];
    final source = value['source'];
    if ((kind != null && kind is! String) ||
        (source != null && source is! String)) {
      throw const FormatException('Dependency graph package type is invalid.');
    }
    return _GraphPackage(
      name: name,
      kind: kind as String?,
      source: source as String?,
      directDependencies: _jsonStringSet(value['directDependencies']),
      devDependencies: _jsonStringSet(value['devDependencies']),
    );
  }
}

_Options _parseOptions(List<String> arguments) {
  String? inputPath;
  String? workspaceRoot;
  String? pluginDiscovery;
  var checkConsumption = false;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--check-consumption':
        if (checkConsumption) {
          _usage();
        }
        checkConsumption = true;
      case '--input':
        if (inputPath != null || index + 1 >= arguments.length) {
          _usage();
        }
        inputPath = arguments[++index];
      case '--workspace-root':
        if (workspaceRoot != null || index + 1 >= arguments.length) {
          _usage();
        }
        workspaceRoot = arguments[++index];
      case '--plugin-discovery':
        if (pluginDiscovery != null || index + 1 >= arguments.length) {
          _usage();
        }
        pluginDiscovery = arguments[++index];
      default:
        _usage();
    }
  }
  if (checkConsumption != (workspaceRoot != null) ||
      (!checkConsumption && pluginDiscovery != null)) {
    _usage();
  }
  return _Options(
    inputPath: inputPath,
    workspaceRoot: workspaceRoot,
    pluginDiscovery: pluginDiscovery,
    checkConsumption: checkConsumption,
  );
}

Never _usage() {
  stderr.writeln(
    'Usage: dart run tool/check_package_dependencies.dart '
    '[--input <pub-deps.json>] '
    '[--check-consumption --workspace-root <directory> '
    '--plugin-discovery <json>]',
  );
  exit(64);
}

Map<String, Object?> _readGraph(_Options options) {
  if (options.inputPath case final inputPath?) {
    return _jsonMap(
      jsonDecode(_readRegularFile(File(inputPath))),
      'dependency graph',
    );
  }
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['pub', 'deps', '--json'],
    workingDirectory: options.workspaceRoot ?? Directory.current.path,
  );
  if (result.exitCode != 0) {
    throw const FormatException('Unable to read dependency graph.');
  }
  return _jsonMap(jsonDecode(result.stdout as String), 'dependency graph');
}

final class _Options {
  const _Options({
    required this.inputPath,
    required this.workspaceRoot,
    required this.pluginDiscovery,
    required this.checkConsumption,
  });

  final String? inputPath;
  final String? workspaceRoot;
  final String? pluginDiscovery;
  final bool checkConsumption;
}

Map<String, Object?> _jsonMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$label must be an object.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label keys must be strings.');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

Map<Object?, Object?> _yamlMap(Object? value, String label) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$label must be an object.');
  }
  return value;
}

Map<Object?, Object?>? _optionalYamlMap(Object? value) {
  if (value == null) {
    return null;
  }
  return _yamlMap(value, 'pubspec section');
}

List<Object?> _jsonList(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label must be a list.');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw const FormatException('Expected a string list.');
  }
  return value.cast<String>();
}

Set<String> _jsonStringSet(Object? value) =>
    value == null ? const {} : _stringList(value).toSet();
