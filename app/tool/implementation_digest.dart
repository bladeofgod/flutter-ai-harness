import 'dart:io';

import 'package:flutter_ai_harness_workspace/src/implementation_digest.dart';

export 'package:flutter_ai_harness_workspace/src/implementation_digest.dart'
    show calculateImplementationDigest;

void main(List<String> arguments) {
  final parsed = _parseArguments(arguments);
  try {
    stdout.writeln(
      calculateImplementationDigest(parsed.root, parsed.relativePaths),
    );
  } on FileSystemException catch (error) {
    stderr.writeln('错误：${error.message}');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('错误：${error.message}');
    exitCode = 1;
  }
}

({Directory root, List<String> relativePaths}) _parseArguments(
  List<String> arguments,
) {
  var root = Directory.current.parent.absolute;
  var paths = arguments;
  if (arguments.length >= 3 && arguments.first == '--root') {
    root = Directory(arguments[1]).absolute;
    paths = arguments.sublist(2);
  }
  if (paths.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/implementation_digest.dart '
      '[--root <path>] <repository-relative-path>...',
    );
    exit(64);
  }
  return (root: root, relativePaths: paths);
}
