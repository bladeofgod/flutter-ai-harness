import 'dart:convert';
import 'dart:io';

const _pluginName = 'app_media_capture_bridge';
const _packageComponents = ['packages', _pluginName];

void main(List<String> arguments) {
  final options = _parseOptions(arguments);
  try {
    final Object? decoded = jsonDecode(
      File(options.inputPath).readAsStringSync(),
    );
    final document = _stringMap(decoded, 'document');
    final plugins = _stringMap(document['plugins'], 'plugins');
    final android = _objectList(plugins['android'], 'plugins.android');
    final matches = android
        .map((entry) => _stringMap(entry, 'plugins.android entry'))
        .where((entry) => entry['name'] == _pluginName)
        .toList(growable: false);

    _require(matches.length == 1, 'Android plugin entry must be unique.');
    final plugin = matches.single;
    _require(plugin['native_build'] == true, 'Android plugin must be native.');
    _require(
      plugin['dev_dependency'] == false,
      'Android plugin must be a production dependency.',
    );

    final discoveredPath = plugin['path'];
    _require(discoveredPath is String, 'Android plugin path must be a string.');
    final workspaceRoot = Directory(
      options.workspaceRoot,
    ).resolveSymbolicLinksSync();
    var expectedPath = workspaceRoot;
    for (final component in _packageComponents) {
      expectedPath = '$expectedPath${Platform.pathSeparator}$component';
      _require(
        FileSystemEntity.typeSync(expectedPath, followLinks: false) ==
            FileSystemEntityType.directory,
        'Expected plugin path must contain only regular directories.',
      );
    }
    final expectedRoot = Directory(expectedPath).resolveSymbolicLinksSync();
    _require(
      expectedRoot.startsWith('$workspaceRoot${Platform.pathSeparator}'),
      'Expected plugin path must remain inside the workspace.',
    );
    final actualRoot = Directory(
      discoveredPath as String,
    ).resolveSymbolicLinksSync();
    _require(actualRoot == expectedRoot, 'Android plugin path is unexpected.');

    final dependencyGraph = _objectList(
      document['dependencyGraph'],
      'dependencyGraph',
    );
    final graphMatches = dependencyGraph
        .map((entry) => _stringMap(entry, 'dependencyGraph entry'))
        .where((entry) => entry['name'] == _pluginName)
        .toList(growable: false);
    _require(
      graphMatches.length == 1,
      'Plugin dependency graph entry must be unique.',
    );

    stdout.writeln('[lint] Media Capture Android plugin discovery 检查通过。');
  } on FormatException {
    _fail('Plugin discovery JSON is malformed.');
  } on FileSystemException {
    _fail('Plugin discovery input is unavailable.');
  } on _ValidationFailure catch (failure) {
    _fail(failure.message);
  }
}

_Options _parseOptions(List<String> arguments) {
  if (arguments.length != 4 ||
      arguments[0] != '--input' ||
      arguments[2] != '--workspace-root') {
    stderr.writeln(
      'Usage: dart run tool/check_flutter_plugin_discovery.dart '
      '--input <json> --workspace-root <directory>',
    );
    exit(64);
  }
  return _Options(inputPath: arguments[1], workspaceRoot: arguments[3]);
}

Map<String, Object?> _stringMap(Object? value, String label) {
  _require(value is Map<Object?, Object?>, '$label must be an object.');
  final result = <String, Object?>{};
  for (final entry in (value as Map<Object?, Object?>).entries) {
    _require(entry.key is String, '$label keys must be strings.');
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _objectList(Object? value, String label) {
  _require(value is List<Object?>, '$label must be a list.');
  return value! as List<Object?>;
}

Never _fail(String message) {
  stderr.writeln('错误：$message');
  exit(1);
}

void _require(bool condition, String message) {
  if (!condition) {
    throw _ValidationFailure(message);
  }
}

final class _Options {
  const _Options({required this.inputPath, required this.workspaceRoot});

  final String inputPath;
  final String workspaceRoot;
}

final class _ValidationFailure implements Exception {
  const _ValidationFailure(this.message);

  final String message;
}
