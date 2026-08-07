import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_harness_workspace/harness_validator.dart';
import 'package:flutter_ai_harness_workspace/src/implementation_digest.dart';
import 'package:test/test.dart';

import 'support/harness_fixture_catalog.dart';

const _missingConfigurationDiagnostics = [
  '缺少 JSON 配置：.claude/settings.json',
  '缺少 JSON 配置：.mcp.json',
];

void main() {
  final appRoot = Directory.current.absolute;
  final repositoryRoot = appRoot.parent;
  final catalog = HarnessFixtureCatalog.load(appRoot);
  late _HarnessFixture fixture;

  setUpAll(() {
    fixture = _HarnessFixture._(catalog.materialize(catalog.cases.first));
  });

  group('Media Capture generated Wire drift', () {
    test('rejects a hand-edited generated body', () {
      final driftFixture = catalog.materialize(
        catalog.cases.first,
        label: 'generated body drift',
      );
      addTearDown(driftFixture.dispose);
      final generated = _fixtureFile(driftFixture.root, _dartGeneratedPath);
      generated.writeAsStringSync(
        '${generated.readAsStringSync()}// hand-edited\n',
      );

      _expectInvalidContaining(
        driftFixture.root,
        '$_dartGeneratedPath 与当前 Contract 生成摘要或标记不一致',
      );
    });

    test('rejects a Contract change without regeneration', () {
      final driftFixture = catalog.materialize(
        catalog.cases.first,
        label: 'contract without regeneration',
      );
      addTearDown(driftFixture.dispose);
      final contract = _fixtureFile(driftFixture.root, _wireContractPath);
      contract.writeAsStringSync('${contract.readAsStringSync()}\n');

      _expectInvalidContaining(
        driftFixture.root,
        'generation 必须绑定当前 Wire Contract 实现摘要',
      );
    });

    test('rejects regeneration of only one runtime', () {
      final driftFixture = catalog.materialize(
        catalog.cases.first,
        label: 'single runtime regeneration',
      );
      addTearDown(driftFixture.dispose);
      final contractFile = _fixtureFile(driftFixture.root, _wireContractPath);
      final contract =
          jsonDecode(contractFile.readAsStringSync()) as Map<String, Object?>;
      final codeGeneration =
          contract['codeGeneration']! as Map<String, Object?>;
      final manualOnly = codeGeneration['manualOnly']! as List<Object?>;
      final firstManualBoundary = manualOnly.first as Map<String, Object?>;
      firstManualBoundary['reason'] =
          '${firstManualBoundary['reason']} Reviewed wording.';
      _writeJson(contractFile, contract);

      const regeneratedDescriptorDigest =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final dartGenerated = _fixtureFile(driftFixture.root, _dartGeneratedPath);
      dartGenerated.writeAsStringSync(
        dartGenerated.readAsStringSync().replaceFirst(
          RegExp(r'Source digest \(SHA-256\): [0-9a-f]{64}'),
          'Source digest (SHA-256): $regeneratedDescriptorDigest',
        ),
      );

      final goldenFile = _fixtureFile(driftFixture.root, _wireGoldenPath);
      final golden =
          jsonDecode(goldenFile.readAsStringSync()) as Map<String, Object?>;
      final generation = golden['generation']! as Map<String, Object?>;
      generation['normalizedDescriptorDigest'] = regeneratedDescriptorDigest;
      generation['contractImplementationDigest'] =
          calculateImplementationDigest(driftFixture.root, const [
            _wireContractPath,
          ]);
      final outputs =
          generation['outputImplementationDigests']! as Map<String, Object?>;
      outputs['dart'] = calculateImplementationDigest(driftFixture.root, const [
        _dartGeneratedPath,
      ]);
      _writeJson(goldenFile, golden);

      final result = validateHarness(driftFixture.root);
      expect(result.isValid, isFalse);
      expect(
        result.diagnostics,
        contains('$_androidGeneratedPath 与当前 Contract 生成摘要或标记不一致'),
      );
      expect(
        result.diagnostics,
        contains('$_iosGeneratedPath 与当前 Contract 生成摘要或标记不一致'),
      );
      expect(
        result.diagnostics,
        isNot(contains('$_dartGeneratedPath 与当前 Contract 生成摘要或标记不一致')),
      );
    });

    test('rejects a deleted generated marker', () {
      final driftFixture = catalog.materialize(
        catalog.cases.first,
        label: 'deleted generated marker',
      );
      addTearDown(driftFixture.dispose);
      final generated = _fixtureFile(driftFixture.root, _iosGeneratedPath);
      generated.writeAsStringSync(
        generated.readAsStringSync().replaceFirst(
          '// GENERATED CODE - DO NOT MODIFY BY HAND.\n',
          '',
        ),
      );

      _expectInvalidContaining(
        driftFixture.root,
        '$_iosGeneratedPath 与当前 Contract 生成摘要或标记不一致',
      );
    });

    test('rejects a symlinked generated output', () {
      final driftFixture = catalog.materialize(
        catalog.cases.first,
        label: 'symlinked generated output',
      );
      addTearDown(driftFixture.dispose);
      final generated = _fixtureFile(driftFixture.root, _dartGeneratedPath);
      final outside = File.fromUri(
        driftFixture.root.parent.uri.resolve('outside-generated.dart'),
      )..writeAsBytesSync(generated.readAsBytesSync());
      generated.deleteSync();
      Link(generated.path).createSync(outside.path);

      _expectInvalidContaining(
        driftFixture.root,
        'generation dart 必须绑定普通生成文件及小写 SHA-256',
      );
    });

    test('rejects a missing runtime renderer', () {
      final driftFixture = catalog.materialize(
        catalog.cases.first,
        label: 'missing runtime renderer',
      );
      addTearDown(driftFixture.dispose);
      _fixtureFile(
        driftFixture.root,
        'app/tool/src/media_capture_wire_generation.dart',
      ).deleteSync();

      _expectInvalidContaining(
        driftFixture.root,
        'codeGeneration 缺少 Dart、Kotlin 或 Swift renderer 实现',
      );
    });
  });

  tearDownAll(() => fixture.dispose());

  group('validateHarness', () {
    test('accepts an independent minimal valid root', () {
      final result = validateHarness(fixture.root);

      expect(result.isValid, isTrue);
      expect(result.diagnostics, isEmpty);
    });

    test('keeps exact diagnostics ordered and immutable', () {
      final invalidRoot = fixture.createCaseRoot('ordered diagnostics');
      addTearDown(() => invalidRoot.parent.deleteSync(recursive: true));
      _removeConfigurationFiles(invalidRoot);

      final first = validateHarness(invalidRoot);
      final second = validateHarness(invalidRoot);

      expect(first.isValid, isFalse);
      expect(
        first.diagnostics,
        orderedEquals(_missingConfigurationDiagnostics),
      );
      expect(
        second.diagnostics,
        orderedEquals(_missingConfigurationDiagnostics),
      );
      expect(
        () => first.diagnostics.add('unexpected mutation'),
        throwsUnsupportedError,
      );
    });

    test('does not leak state between roots in the same VM', () {
      final invalidRoot = fixture.createCaseRoot('state isolation');
      addTearDown(() => invalidRoot.parent.deleteSync(recursive: true));
      _removeConfigurationFiles(invalidRoot);

      final invalidBefore = validateHarness(invalidRoot);
      final valid = validateHarness(fixture.root);
      final invalidAfter = validateHarness(invalidRoot);

      expect(
        invalidBefore.diagnostics,
        orderedEquals(_missingConfigurationDiagnostics),
      );
      expect(valid.isValid, isTrue);
      expect(
        invalidAfter.diagnostics,
        orderedEquals(_missingConfigurationDiagnostics),
      );
    });

    test('accepts the current repository as a smoke test', () {
      final result = validateHarness(repositoryRoot);

      expect(result.isValid, isTrue);
      expect(result.diagnostics, isEmpty);
    });
  });

  group('harness_check CLI', () {
    test('preserves --root success output and exit code', () async {
      final result = await _runCli(appRoot, ['--root', fixture.root.path]);

      _expectSuccessfulCli(result);
    });

    test('preserves no-argument success output and exit code', () async {
      final result = await _runCliDirect(
        appRoot,
        workingDirectory: fixture.root.uri.resolve('app/').toFilePath(),
      );

      _expectSuccessfulCli(result);
    });

    test(
      'preserves exact failure output and exit code for a spaced path',
      () async {
        final invalidRoot = fixture.createCaseRoot('cli failure');
        addTearDown(() => invalidRoot.parent.deleteSync(recursive: true));
        _removeConfigurationFiles(invalidRoot);

        final result = await _runCli(appRoot, ['--root', invalidRoot.path]);

        expect(result.exitCode, 1);
        expect(result.stdout, isEmpty);
        expect(
          result.stderr,
          _missingConfigurationDiagnostics
              .map((diagnostic) => '错误：$diagnostic${Platform.lineTerminator}')
              .join(),
        );
      },
    );

    test('preserves usage output and exit code', () async {
      final result = await _runCli(appRoot, ['--root']);

      expect(result.exitCode, 64);
      expect(result.stdout, isEmpty);
      expect(
        result.stderr,
        'Usage: dart run tool/harness_check.dart [--root <path>]'
        '${Platform.lineTerminator}',
      );
    });
  });
}

void _removeConfigurationFiles(Directory root) {
  File.fromUri(root.uri.resolve('.claude/settings.json')).deleteSync();
  File.fromUri(root.uri.resolve('.mcp.json')).deleteSync();
}

void _expectSuccessfulCli(ProcessResult result) {
  expect(result.exitCode, 0);
  expect(
    result.stdout,
    '[harness-check] AI Harness 静态检查通过。${Platform.lineTerminator}',
  );
  expect(result.stderr, isEmpty);
}

Future<ProcessResult> _runCli(Directory appRoot, List<String> arguments) =>
    Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/harness_check.dart',
      ...arguments,
    ], workingDirectory: appRoot.path);

Future<ProcessResult> _runCliDirect(
  Directory appRoot, {
  required String workingDirectory,
}) => Process.run(Platform.resolvedExecutable, [
  '--packages=${appRoot.uri.resolve('.dart_tool/package_config.json').toFilePath()}',
  appRoot.uri.resolve('tool/harness_check.dart').toFilePath(),
], workingDirectory: workingDirectory);

final class _HarnessFixture {
  _HarnessFixture._(this.materialized);

  final MaterializedHarnessFixture materialized;
  Directory get root => materialized.root;

  Directory createCaseRoot(String label) {
    final parent = Directory.systemTemp.createTempSync(
      'harness validator case $label ',
    );
    final caseRoot = Directory.fromUri(parent.uri.resolve('repo with spaces/'));
    _copyDirectory(root, caseRoot);
    return caseRoot;
  }

  void dispose() => materialized.dispose();
}

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync();
  for (final entity in source.listSync(followLinks: false)) {
    final destinationUri = destination.uri.resolve(_basename(entity.path));
    switch (entity) {
      case final File file:
        file.copySync(destinationUri.toFilePath());
      case final Directory directory:
        _copyDirectory(directory, Directory.fromUri(destinationUri));
      default:
        throw StateError('Harness fixture contains a non-file entry.');
    }
  }
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

const _wireContractPath = 'docs/bridge/contracts/media-capture.wire.json';
const _wireGoldenPath =
    'app/packages/app_media_capture_bridge/test/contracts/'
    'media-capture-v4-v3.golden.json';
const _dartGeneratedPath =
    'app/packages/app_media_capture_bridge/lib/src/media_capture_wire.g.dart';
const _androidGeneratedPath =
    'app/packages/app_media_capture_bridge/android/src/main/kotlin/'
    'com/example/media_capture/MediaCaptureWire.g.kt';
const _iosGeneratedPath =
    'app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/'
    'Sources/MediaCaptureBridgeCore/MediaCaptureWire.generated.swift';

File _fixtureFile(Directory root, String path) =>
    File.fromUri(root.uri.resolve(path));

void _writeJson(File file, Map<String, Object?> value) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

void _expectInvalidContaining(Directory root, String diagnostic) {
  final result = validateHarness(root);
  expect(result.isValid, isFalse);
  expect(result.diagnostics, anyElement(contains(diagnostic)));
}
