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
