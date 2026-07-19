import 'dart:convert';
import 'dart:io';

const _allowedDependencies = <String, Set<String>>{
  'app_core': {},
  'app_ui': {},
  'app_data': {'app_core'},
  'app_im': {'app_core'},
  'app_rtc': {'app_core'},
  'app_features': {'app_core', 'app_data', 'app_im', 'app_rtc', 'app_ui'},
  'demo_app': {
    'app_core',
    'app_data',
    'app_features',
    'app_im',
    'app_rtc',
    'app_ui',
  },
};

void main(List<String> arguments) {
  final input = _readInput(arguments);
  final document = jsonDecode(input) as Map<String, Object?>;
  final workspaceRoot = document['root'] as String?;
  final packages = (document['packages'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final workspacePackages = <String, Map<String, Object?>>{};

  for (final package in packages) {
    final name = package['name'] as String;
    if (name == workspaceRoot) {
      continue;
    }
    if (package['kind'] == 'root' && package['source'] == 'root') {
      workspacePackages[name] = package;
    }
  }

  var failed = false;
  final unknown = workspacePackages.keys.toSet()
    ..removeAll(_allowedDependencies.keys);
  if (unknown.isNotEmpty) {
    stderr.writeln(
      '错误：以下 Workspace Package 尚未加入依赖矩阵：'
      '${(unknown.toList()..sort()).join(', ')}',
    );
    failed = true;
  }

  for (final entry in _allowedDependencies.entries) {
    final package = workspacePackages[entry.key];
    if (package == null) {
      stderr.writeln('错误：依赖图缺少 Workspace Package：${entry.key}');
      failed = true;
      continue;
    }

    final dependencies = <String>{
      ..._stringList(package['directDependencies']),
      ..._stringList(package['devDependencies']),
    }..retainAll(workspacePackages.keys);
    final forbidden = dependencies.difference(entry.value);
    if (forbidden.isNotEmpty) {
      stderr.writeln(
        '错误：${entry.key} 不得依赖 '
        '${(forbidden.toList()..sort()).join(', ')}',
      );
      failed = true;
    }
  }

  if (failed) {
    exitCode = 1;
    return;
  }
  stdout.writeln('[lint] Workspace Package 依赖矩阵检查通过。');
}

String _readInput(List<String> arguments) {
  if (arguments.length == 2 && arguments.first == '--input') {
    return File(arguments[1]).readAsStringSync();
  }
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Usage: dart run tool/check_package_dependencies.dart '
      '[--input <pub-deps.json>]',
    );
    exit(64);
  }

  final result = Process.runSync(Platform.resolvedExecutable, [
    'pub',
    'deps',
    '--json',
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
    exit(result.exitCode);
  }
  return result.stdout as String;
}

Iterable<String> _stringList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return value.whereType<String>();
}
