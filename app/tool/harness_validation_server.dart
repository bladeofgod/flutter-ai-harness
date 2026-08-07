import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_ai_harness_workspace/harness_validator.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || arguments.first != '--root') {
    stderr.writeln(
      'Usage: dart run tool/harness_validation_server.dart --root <path>',
    );
    exitCode = 64;
    return;
  }

  final root = Directory(arguments[1]).absolute;
  final captureDirectoryPath =
      Platform.environment['HARNESS_FIXTURE_CAPTURE_DIRECTORY'];
  final capture = captureDirectoryPath == null
      ? null
      : _FixtureCatalogCapture(
          root: root,
          output: Directory(captureDirectoryPath).absolute,
        );
  var caseIndex = 0;
  final callSiteCounts = <int, int>{};
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final request = jsonDecode(line);
    if (request is Map<String, Object?> && request['command'] == 'shutdown') {
      return;
    }
    if (request is! Map<String, Object?> || request['command'] != 'validate') {
      stderr.writeln('Invalid Harness validation server request.');
      exitCode = 64;
      return;
    }
    final callSite = request['callSite'];
    if (callSite is! int || callSite <= 0) {
      stderr.writeln('Harness validation request requires callSite.');
      exitCode = 64;
      return;
    }

    caseIndex += 1;
    final callSiteOccurrence = (callSiteCounts[callSite] ?? 0) + 1;
    callSiteCounts[callSite] = callSiteOccurrence;
    final source = 'scripts/quality/test-harness.sh:$callSite';
    final result = validateHarness(root);
    final response = <String, Object?>{
      'id': 'harness-${caseIndex.toString().padLeft(4, '0')}',
      'mutation': '$source#$callSiteOccurrence',
      'callSite': source,
      'diagnostics': result.diagnostics,
    };
    capture?.record(response);
    stdout.writeln(jsonEncode(response));
    await stdout.flush();
  }
}

final class _FixtureCatalogCapture {
  _FixtureCatalogCapture({required this.root, required this.output})
    : blobs = Directory.fromUri(output.uri.resolve('blobs/')),
      catalog = File.fromUri(output.uri.resolve('cases.jsonl')) {
    if (!output.isAbsolute) {
      throw const FormatException(
        'Harness Fixture capture path must be absolute.',
      );
    }
    if (output.existsSync()) {
      throw FileSystemException(
        'Harness Fixture capture directory already exists',
        output.path,
      );
    }
    blobs.createSync(recursive: true);
    catalog.createSync();
  }

  final Directory root;
  final Directory output;
  final Directory blobs;
  final File catalog;
  Map<String, _FixtureEntity>? _latestValidState;
  String? _latestValidId;

  void record(Map<String, Object?> response) {
    final id = response['id']! as String;
    final diagnostics = response['diagnostics']! as List<String>;
    final state = _snapshot();
    final base = _latestValidState ?? const <String, _FixtureEntity>{};
    final writes = <Map<String, Object?>>[];
    final deletes = base.keys.where((path) => !state.containsKey(path)).toList()
      ..sort();
    final paths = state.keys.toList()..sort();
    for (final path in paths) {
      final entity = state[path]!;
      if (entity != base[path]) {
        writes.add(entity.toJson(path));
      }
    }
    catalog.writeAsStringSync(
      '${jsonEncode(<String, Object?>{...response, 'baseId': _latestValidId, 'writes': writes, 'deletes': deletes})}\n',
      mode: FileMode.append,
    );
    if (diagnostics.isEmpty) {
      _latestValidState = state;
      _latestValidId = id;
    }
  }

  Map<String, _FixtureEntity> _snapshot() {
    final state = <String, _FixtureEntity>{};
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      final path = _relativePath(entity.path);
      final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          state[path] = const _FixtureEntity.directory();
        case FileSystemEntityType.file:
          final bytes = File(entity.path).readAsBytesSync();
          final digest = sha256.convert(bytes).toString();
          final blob = File.fromUri(blobs.uri.resolve('$digest.gz'));
          if (!blob.existsSync()) {
            blob.writeAsBytesSync(gzip.encode(bytes), flush: true);
          }
          state[path] = _FixtureEntity.file(digest);
        case FileSystemEntityType.link:
          state[path] = _FixtureEntity.link(Link(entity.path).targetSync());
        default:
          throw FileSystemException(
            'Unsupported Harness Fixture entity type',
            entity.path,
          );
      }
    }
    return Map<String, _FixtureEntity>.unmodifiable(state);
  }

  String _relativePath(String path) {
    final rootPath = '${root.path}${Platform.pathSeparator}';
    if (!path.startsWith(rootPath)) {
      throw FileSystemException('Fixture entity escaped root', path);
    }
    return path.substring(rootPath.length).replaceAll('\\', '/');
  }
}

final class _FixtureEntity {
  const _FixtureEntity._(this.type, this.value);
  const _FixtureEntity.directory() : this._('directory', null);
  const _FixtureEntity.file(String digest) : this._('file', digest);
  const _FixtureEntity.link(String target) : this._('link', target);

  final String type;
  final String? value;

  Map<String, Object?> toJson(String path) => <String, Object?>{
    'path': path,
    'type': type,
    if (type == 'file') 'digest': value,
    if (type == 'link') 'target': value,
  };

  @override
  bool operator ==(Object other) =>
      other is _FixtureEntity && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);
}
