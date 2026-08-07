import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/check_package_dependencies.dart' as checker;

const _packagePaths = <String, String>{
  'app_core': 'packages/app_core',
  'app_ui': 'packages/app_ui',
  'app_data': 'packages/app_data',
  'app_media': 'packages/app_media',
  'app_media_capture_bridge': 'packages/app_media_capture_bridge',
  'app_features': 'packages/app_features',
  'demo_app': 'apps/demo',
};

void main() {
  late _DependencyFixture fixture;

  setUp(() {
    fixture = _DependencyFixture.create();
  });

  tearDown(() => fixture.dispose());

  test('keeps the existing allowed dependency matrix compatible', () async {
    final result = await fixture.runMatrixCheck();

    expect(result.exitCode, 0);
    expect(
      result.stdout,
      '[lint] Workspace Package 依赖矩阵检查通过。'
      '${Platform.lineTerminator}',
    );
    expect(result.stderr, isEmpty);
  });

  test(
    'accepts production, dev, conditional import, and export consumers',
    () async {
      fixture
        ..removeProductionDependency('app_features', 'app_media_capture_bridge')
        ..writeFeatureImports(includeBridge: false)
        ..addDevelopmentDependency('app_features', 'app_media_capture_bridge')
        ..appendSource(
          'app_features',
          'test/bridge_test.dart',
          "import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';\n",
        );

      final result = await fixture.runConsumptionCheck();

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        '[lint] Workspace Package 依赖消费检查通过。'
        '${Platform.lineTerminator}',
      );
      expect(result.stderr, isEmpty);
    },
  );

  test(
    'does not count comments or generated sources as consumers',
    () async {
      fixture
        ..writeFeatureImports(includeBridge: false)
        ..appendSource(
          'app_features',
          'lib/ignored.dart',
          "// import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';\n"
              "const text = \"package:app_media_capture_bridge/app_media_capture_bridge.dart\";\n",
        )
        ..appendSource(
          'app_features',
          'lib/generated/ignored.dart',
          "import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';\n",
        );

      final result = await fixture.runConsumptionCheck(useCli: true);

      _expectErrors(result, [
        'app_features 的 production dependency 未被生产源码消费：'
            'app_media_capture_bridge',
      ], fixture.root.path);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('distinguishes a test-only production dependency', () async {
    fixture
      ..writeFeatureImports(includeBridge: false)
      ..appendSource(
        'app_features',
        'test/media_test.dart',
        "import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';\n",
      );

    final result = await fixture.runConsumptionCheck();

    _expectErrors(result, [
      'app_features 的 production dependency 仅被测试/工具源码消费：'
          'app_media_capture_bridge',
    ], fixture.root.path);
  });

  test('reports an unused workspace dev dependency', () async {
    fixture
      ..removeProductionDependency('app_features', 'app_media_capture_bridge')
      ..writeFeatureImports(includeBridge: false)
      ..addDevelopmentDependency('app_features', 'app_media_capture_bridge');

    final result = await fixture.runConsumptionCheck();

    _expectErrors(result, [
      'app_features 的 dev dependency 未被测试/工具源码消费：'
          'app_media_capture_bridge',
    ], fixture.root.path);
  });

  test('rejects Demo direct access to lower-level runtime packages', () async {
    fixture
      ..addProductionDependency('demo_app', 'app_core')
      ..addProductionDependency('demo_app', 'app_media')
      ..addProductionDependency('demo_app', 'app_media_capture_bridge')
      ..appendSource(
        'demo_app',
        'lib/forbidden.dart',
        "import 'package:app_core/app_core.dart';\n"
            "import 'package:app_media/app_media.dart';\n"
            "import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';\n",
      )
      ..writePluginDiscovery();

    final result = await fixture.runConsumptionCheck(withDiscovery: true);

    _expectErrors(result, [
      'demo_app 不得依赖 app_core, app_media, app_media_capture_bridge',
    ], fixture.root.path);
  });

  test('rejects a redundant direct plugin discovery edge', () async {
    fixture
      ..addProductionDependency('demo_app', 'app_media_capture_bridge')
      ..writePluginDiscovery();

    final result = await fixture.runConsumptionCheck(withDiscovery: true);

    _expectErrors(result, [
      'demo_app 不得依赖 app_media_capture_bridge',
      'demo_app 的 Plugin 直连依赖可通过其它生产依赖到达：'
          'app_media_capture_bridge',
    ], fixture.root.path);
  });

  test('requires every declared Android and iOS plugin entry', () async {
    fixture
      ..removeProductionDependency('app_features', 'app_media_capture_bridge')
      ..writeFeatureImports(includeBridge: false)
      ..addProductionDependency('demo_app', 'app_media_capture_bridge')
      ..writePluginDiscovery(includeIos: false);

    final result = await fixture.runConsumptionCheck(withDiscovery: true);

    _expectErrors(result, [
      'demo_app 不得依赖 app_media_capture_bridge',
      'demo_app 的 production dependency 未被生产源码消费：'
          'app_media_capture_bridge',
    ], fixture.root.path);
  });

  test(
    'reports a package without real consumers or a structured role',
    () async {
      fixture
        ..removeProductionDependency('app_features', 'app_media')
        ..writeFeatureImports(includeMedia: false);

      final result = await fixture.runConsumptionCheck();

      _expectErrors(result, [
        'Workspace Package 无消费者：app_media',
      ], fixture.root.path);
    },
  );

  test('reports source imports for unknown packages', () async {
    fixture.appendSource(
      'app_data',
      'lib/unknown.dart',
      "export 'package:not_in_graph/api.dart';\n",
    );

    final result = await fixture.runConsumptionCheck();

    _expectErrors(result, [
      'app_data 的源码引用未知 Package：not_in_graph',
    ], fixture.root.path);
  });

  test('reports unknown workspace packages in matrix mode', () async {
    fixture.addWorkspacePackage('rogue_package');

    final result = await fixture.runMatrixCheck();

    _expectErrors(result, [
      '以下 Workspace Package 尚未加入依赖矩阵：rogue_package',
    ], fixture.root.path);
  });

  test(
    'fails malformed graph metadata without leaking input paths',
    () async {
      final result = await fixture.runMalformedGraphCheck();

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, '错误：依赖检查输入格式无效。${Platform.lineTerminator}');
      expect(result.stderr, isNot(contains(fixture.root.path)));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'reports the current cleanup baseline exactly',
    () async {
      final appRoot = Directory.current.absolute;
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/check_package_dependencies.dart',
        '--check-consumption',
        '--workspace-root',
        '.',
        '--plugin-discovery',
        'apps/demo/.flutter-plugins-dependencies',
      ], workingDirectory: appRoot.path);

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        '[lint] Workspace Package 依赖消费检查通过。'
        '${Platform.lineTerminator}',
      );
      expect(result.stderr, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _expectErrors(
  _CheckOutput result,
  List<String> diagnostics,
  String forbiddenPath,
) {
  expect(result.exitCode, 1);
  expect(result.stdout, isEmpty);
  expect(
    result.stderr,
    diagnostics
        .map((diagnostic) => '错误：$diagnostic${Platform.lineTerminator}')
        .join(),
  );
  expect(result.stderr, isNot(contains(forbiddenPath)));
}

final class _CheckOutput {
  const _CheckOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  factory _CheckOutput.fromProcess(ProcessResult result) => _CheckOutput(
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );

  final int exitCode;
  final String stdout;
  final String stderr;
}

final class _DependencyFixture {
  _DependencyFixture._(
    this.root,
    this.dependencies,
    this.developmentDependencies,
  ) {
    _writeWorkspace();
  }

  final Directory root;
  final Map<String, List<String>> dependencies;
  final Map<String, List<String>> developmentDependencies;

  static _DependencyFixture create() {
    final fixture = _DependencyFixture._(
      Directory.systemTemp.createTempSync('package-dependency-checker.'),
      {
        'app_core': [],
        'app_ui': [],
        'app_data': ['app_core'],
        'app_media': ['app_core', 'app_ui'],
        'app_media_capture_bridge': [],
        'app_features': [
          'app_core',
          'app_data',
          'app_media',
          'app_media_capture_bridge',
          'app_ui',
        ],
        'demo_app': ['app_data', 'app_features', 'app_ui'],
      },
      {for (final name in _packagePaths.keys) name: <String>[]},
    );
    fixture
      ..appendSource(
        'app_data',
        'lib/app_data.dart',
        "import 'package:app_core/app_core.dart'\n"
            "  if (dart.library.io) 'package:app_core/io.dart';\n",
      )
      ..appendSource(
        'app_media',
        'lib/app_media.dart',
        "import 'package:app_core/app_core.dart';\n"
            "export 'package:app_ui/app_ui.dart';\n",
      )
      ..writeFeatureImports()
      ..appendSource(
        'demo_app',
        'lib/main.dart',
        "import 'package:app_data/app_data.dart';\n"
            "import 'package:app_features/app_features.dart';\n"
            "import 'package:app_ui/app_ui.dart';\n",
      );
    return fixture;
  }

  File get graphFile => File.fromUri(root.uri.resolve('dependencies.json'));

  File get discoveryFile =>
      File.fromUri(root.uri.resolve('plugin-discovery.json'));

  void addProductionDependency(String package, String dependency) {
    dependencies[package]!.add(dependency);
  }

  void removeProductionDependency(String package, String dependency) {
    dependencies[package]!.remove(dependency);
  }

  void addDevelopmentDependency(String package, String dependency) {
    developmentDependencies[package]!.add(dependency);
  }

  void addWorkspacePackage(String name) {
    dependencies[name] = [];
    developmentDependencies[name] = [];
    _writeWorkspace();
  }

  Map<String, String> get _packagePathsWithExtra => {
    ..._packagePaths,
    for (final name in dependencies.keys)
      if (!_packagePaths.containsKey(name)) name: 'packages/$name',
  };

  void writeFeatureImports({
    bool includeBridge = true,
    bool includeMedia = true,
  }) {
    final imports = <String>[
      'app_core',
      'app_data',
      if (includeMedia) 'app_media',
      if (includeBridge) 'app_media_capture_bridge',
      'app_ui',
    ];
    appendSource(
      'app_features',
      'lib/app_features.dart',
      imports.map((name) => "import 'package:$name/$name.dart';").join('\n'),
    );
  }

  void appendSource(String package, String relativePath, String content) {
    final packagePath = _packagePathsWithExtra[package]!;
    final file = File.fromUri(root.uri.resolve('$packagePath/$relativePath'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writePluginDiscovery({bool includeIos = true}) {
    final pluginPath = Directory.fromUri(
      root.uri.resolve('packages/app_media_capture_bridge/'),
    ).path;
    discoveryFile.writeAsStringSync(
      jsonEncode({
        'plugins': {
          'android': [_pluginEntry(pluginPath)],
          'ios': includeIos ? [_pluginEntry(pluginPath)] : <Object?>[],
        },
        'dependencyGraph': [
          {'name': 'app_media_capture_bridge', 'dependencies': <String>[]},
        ],
      }),
    );
  }

  Map<String, Object?> _pluginEntry(String path) => {
    'name': 'app_media_capture_bridge',
    'path': '$path${Platform.pathSeparator}',
    'native_build': true,
    'dependencies': <String>[],
    'dev_dependency': false,
  };

  Future<_CheckOutput> runMatrixCheck() async {
    _writeGraph();
    return _runDirect(checkConsumption: false);
  }

  Future<_CheckOutput> runMalformedGraphCheck() async {
    _writeGraph();
    final document = jsonDecode(graphFile.readAsStringSync()) as Map;
    final packages = document['packages'] as List;
    (packages[1] as Map)['kind'] = 42;
    graphFile.writeAsStringSync(jsonEncode(document));
    return _CheckOutput.fromProcess(await _run(['--input', graphFile.path]));
  }

  Future<_CheckOutput> runConsumptionCheck({
    bool withDiscovery = false,
    bool useCli = false,
  }) async {
    _writeGraph();
    if (useCli) {
      final result = await _run([
        '--input',
        graphFile.path,
        '--check-consumption',
        '--workspace-root',
        root.path,
        if (withDiscovery) ...['--plugin-discovery', discoveryFile.path],
      ]);
      return _CheckOutput.fromProcess(result);
    }
    return _runDirect(checkConsumption: true, withDiscovery: withDiscovery);
  }

  _CheckOutput _runDirect({
    required bool checkConsumption,
    bool withDiscovery = false,
  }) {
    final document = (jsonDecode(graphFile.readAsStringSync()) as Map)
        .cast<String, Object?>();
    final result = checker.checkPackageDependencies(
      document,
      workspaceRoot: checkConsumption ? root : null,
      pluginDiscovery: withDiscovery ? discoveryFile : null,
      checkConsumption: checkConsumption,
    );
    if (result.isValid) {
      return _CheckOutput(
        exitCode: 0,
        stdout:
            '${checkConsumption ? '[lint] Workspace Package 依赖消费检查通过。' : '[lint] Workspace Package 依赖矩阵检查通过。'}'
            '${Platform.lineTerminator}',
        stderr: '',
      );
    }
    return _CheckOutput(
      exitCode: 1,
      stdout: '',
      stderr: result.diagnostics
          .map((diagnostic) => '错误：$diagnostic${Platform.lineTerminator}')
          .join(),
    );
  }

  Future<ProcessResult> _run(List<String> arguments) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/check_package_dependencies.dart', ...arguments],
    workingDirectory: Directory.current.path,
  );

  void _writeWorkspace() {
    final paths = _packagePathsWithExtra;
    File.fromUri(root.uri.resolve('pubspec.yaml')).writeAsStringSync(
      'name: fixture_workspace\n'
      'workspace:\n'
      '${paths.values.map((path) => '  - $path').join('\n')}\n',
    );
    for (final entry in paths.entries) {
      final directory = Directory.fromUri(root.uri.resolve('${entry.value}/'))
        ..createSync(recursive: true);
      final pluginSection = entry.key == 'app_media_capture_bridge'
          ? 'flutter:\n'
                '  plugin:\n'
                '    platforms:\n'
                '      android:\n'
                '        package: fixture.bridge\n'
                '        pluginClass: FixturePlugin\n'
                '      ios:\n'
                '        pluginClass: FixturePlugin\n'
          : '';
      File.fromUri(
        directory.uri.resolve('pubspec.yaml'),
      ).writeAsStringSync('name: ${entry.key}\n$pluginSection');
    }
  }

  void _writeGraph() {
    final packages = <Map<String, Object?>>[
      {
        'name': 'fixture_workspace',
        'kind': 'root',
        'source': 'root',
        'directDependencies': <String>[],
        'devDependencies': <String>[],
      },
      for (final entry in dependencies.entries)
        {
          'name': entry.key,
          'kind': 'root',
          'source': 'root',
          'directDependencies': entry.value,
          'devDependencies': developmentDependencies[entry.key],
        },
    ];
    graphFile.writeAsStringSync(
      jsonEncode({'root': 'fixture_workspace', 'packages': packages}),
    );
  }

  void dispose() => root.deleteSync(recursive: true);
}
