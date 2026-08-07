import 'dart:io';

import 'package:flutter_ai_harness_workspace/harness_validator.dart';

void main(List<String> arguments) {
  final root = _parseRoot(arguments);
  if (root == null) {
    exitCode = 64;
    return;
  }

  final result = validateHarness(root);
  if (!result.isValid) {
    for (final diagnostic in result.diagnostics) {
      stderr.writeln('错误：$diagnostic');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('[harness-check] AI Harness 静态检查通过。');
}

Directory? _parseRoot(List<String> arguments) {
  if (arguments.isEmpty) {
    return Directory.current.parent.absolute;
  }
  if (arguments.length == 2 && arguments.first == '--root') {
    return Directory(arguments[1]).absolute;
  }
  stderr.writeln('Usage: dart run tool/harness_check.dart [--root <path>]');
  return null;
}
