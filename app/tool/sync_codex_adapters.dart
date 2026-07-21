import 'dart:io';

import 'codex_adapters.dart';

void main(List<String> arguments) {
  final options = _parseOptions(arguments);
  if (options == null) {
    exitCode = 64;
    return;
  }

  final manager = CodexAdapterManager(options.root);
  final errors = options.check ? manager.check() : manager.sync();
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('错误：$error');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    options.check
        ? '[codex-adapters] Codex 原生适配同步检查通过。'
        : '[codex-adapters] Codex 原生适配已同步。',
  );
}

_Options? _parseOptions(List<String> arguments) {
  var check = false;
  Directory? root;
  for (var index = 0; index < arguments.length; index += 1) {
    switch (arguments[index]) {
      case '--check':
        check = true;
      case '--root':
        if (index + 1 >= arguments.length ||
            arguments[index + 1].startsWith('--') ||
            root != null) {
          _printUsage();
          return null;
        }
        index += 1;
        root = Directory(arguments[index]).absolute;
      default:
        _printUsage();
        return null;
    }
  }
  return _Options(
    check: check,
    root: root ?? Directory.current.parent.absolute,
  );
}

void _printUsage() {
  stderr.writeln(
    'Usage: dart run tool/sync_codex_adapters.dart '
    '[--check] [--root <path>]',
  );
}

class _Options {
  const _Options({required this.check, required this.root});

  final bool check;
  final Directory root;
}
