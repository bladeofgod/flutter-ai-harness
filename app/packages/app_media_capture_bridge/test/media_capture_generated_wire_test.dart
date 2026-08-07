import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.absolute;
  final appRoot = packageRoot.parent.parent;
  final repositoryRoot = appRoot.parent;
  final generatedFile = File.fromUri(
    packageRoot.uri.resolve('lib/src/media_capture_wire.g.dart'),
  );
  final codecFile = File.fromUri(
    packageRoot.uri.resolve('lib/src/media_capture_wire_codec.dart'),
  );

  test('Dart generated Wire output has no drift', () async {
    final result = await Process.run(_dartExecutable(), <String>[
      '--packages=${appRoot.uri.resolve('.dart_tool/package_config.json').toFilePath()}',
      appRoot.uri.resolve('tool/generate_media_capture_wire.dart').toFilePath(),
      '--runtime',
      'dart',
      '--check',
    ], workingDirectory: repositoryRoot.path);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('codec consumes every generated payload descriptor', () {
    final generated = generatedFile.readAsStringSync();
    final codec = codecFile.readAsStringSync();
    final payloadIds = RegExp(
      r"_GeneratedWirePayloadDescriptor\(\s*'([^']+)'",
      multiLine: true,
    ).allMatches(generated).map((match) => match.group(1)!).toSet();

    expect(payloadIds, isNotEmpty);
    for (final payloadId in payloadIds) {
      expect(codec, contains("'$payloadId'"), reason: payloadId);
    }
    expect(codec, contains('_generatedMatchesWireFieldPrimitive'));
    expect(codec, contains('_generatedErrorDescriptors'));
    expect(codec, contains('_generatedEnvelopeRequiredKeys'));
  });

  test('generated descriptor coverage matches the shared neutral golden', () {
    final generated = generatedFile.readAsStringSync();
    final golden =
        jsonDecode(
              File.fromUri(
                packageRoot.uri.resolve(
                  'test/contracts/media-capture-v4-v3.golden.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final generation = golden['generation']! as Map<String, Object?>;

    expect(
      RegExp(
        r'Source digest \(SHA-256\): ([0-9a-f]{64})',
      ).firstMatch(generated)!.group(1),
      generation['normalizedDescriptorDigest'],
    );
    expect(generation['wireVersion'], 3);
    expect(
      RegExp(
        r'^const String _generatedMediaCaptureWireMethod',
        multiLine: true,
      ).allMatches(generated).length,
      generation['methodCount'],
    );
    expect(
      RegExp(
        r'^const String _generatedMediaCaptureWireEvent',
        multiLine: true,
      ).allMatches(generated).length,
      generation['eventCount'],
    );
    expect(
      RegExp(
        r'^const String _generatedMediaCaptureWireResult',
        multiLine: true,
      ).allMatches(generated).length,
      generation['resultTypeCount'],
    );
    expect(
      RegExp(
        r'^const String _generatedMediaCaptureWireFailure',
        multiLine: true,
      ).allMatches(generated).length,
      generation['failureTypeCount'],
    );
    expect(
      RegExp(
        r'^const String _generatedMediaCaptureWireError',
        multiLine: true,
      ).allMatches(generated).length,
      generation['errorCount'],
    );
    expect(
      RegExp(
        r'^      _GeneratedWirePayloadDescriptor\(',
        multiLine: true,
      ).allMatches(generated).length,
      generation['payloadDescriptorCount'],
    );
    expect(
      RegExp(
        r'^      _GeneratedWireFieldDescriptor\(',
        multiLine: true,
      ).allMatches(generated).length,
      generation['fieldDescriptorCount'],
    );
  });

  test('public package surface does not expose generated internals', () {
    final barrel = File.fromUri(
      packageRoot.uri.resolve('lib/app_media_capture_bridge.dart'),
    ).readAsStringSync();
    final constants = File.fromUri(
      packageRoot.uri.resolve('lib/src/media_capture_constants.dart'),
    ).readAsStringSync();

    expect(barrel, isNot(contains('media_capture_wire.g.dart')));
    expect(barrel, isNot(contains('media_capture_wire_codec.dart')));
    expect(constants, contains("export 'media_capture_wire_codec.dart'"));
    expect(constants, contains('show'));
    expect(constants, isNot(contains('_Generated')));
  });
}

String _dartExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final executable = File.fromUri(
      Directory(flutterRoot).uri.resolve('bin/cache/dart-sdk/bin/dart'),
    );
    if (executable.existsSync()) {
      return executable.path;
    }
  }

  final resolved = File(Platform.resolvedExecutable).absolute;
  if (resolved.uri.pathSegments.last == 'dart') {
    return resolved.path;
  }
  var directory = resolved.parent;
  while (directory.parent.path != directory.path) {
    final executable = File.fromUri(directory.uri.resolve('dart-sdk/bin/dart'));
    if (executable.existsSync()) {
      return executable.path;
    }
    directory = directory.parent;
  }
  return 'dart';
}
