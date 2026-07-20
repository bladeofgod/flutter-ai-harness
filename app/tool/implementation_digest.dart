import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

String calculateImplementationDigest(
  Directory root,
  Iterable<String> relativePaths,
) {
  final paths = relativePaths.toSet().toList()..sort();
  if (paths.isEmpty) {
    throw const FormatException('实现摘要至少需要一个文件');
  }

  final bytes = BytesBuilder(copy: false);
  final rootPath =
      '${root.resolveSymbolicLinksSync()}${Platform.pathSeparator}';
  for (final path in paths) {
    if (File(path).isAbsolute ||
        path.contains('\\') ||
        path.split('/').contains('..')) {
      throw FormatException('实现文件必须使用仓库相对路径：$path');
    }
    final file = File.fromUri(root.uri.resolve(path));
    if (!file.existsSync()) {
      throw FormatException('实现文件不存在：$path');
    }
    if (!file.resolveSymbolicLinksSync().startsWith(rootPath)) {
      throw FormatException('实现文件不得越出仓库：$path');
    }
    bytes
      ..add(utf8.encode(path))
      ..addByte(0)
      ..add(file.readAsBytesSync())
      ..addByte(0);
  }
  return sha256.convert(bytes.takeBytes()).toString();
}

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
