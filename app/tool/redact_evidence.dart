import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length >= 3 && arguments.first == '--command') {
    final output = File(arguments[1]);
    final command = arguments
        .skip(2)
        .map((argument) => _redact(argument, normalizeTerminalOutput: false))
        .map(_shellQuote)
        .join(' ');
    output.parent.createSync(recursive: true);
    output.writeAsStringSync('$command\n');
    return;
  }

  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/redact_evidence.dart <input> <output>',
    );
    exitCode = 64;
    return;
  }

  final input = File(arguments[0]);
  final output = File(arguments[1]);
  final content = _redact(input.readAsStringSync());

  output.parent.createSync(recursive: true);
  output.writeAsStringSync(content);
}

String _redact(String input, {bool normalizeTerminalOutput = true}) {
  var content = normalizeTerminalOutput
      ? _normalizeTerminalOutput(input)
      : input;

  final repositoryRoot = Platform.environment['EVIDENCE_REPO_ROOT'];
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  if (repositoryRoot != null && repositoryRoot.isNotEmpty) {
    content = content.replaceAll(repositoryRoot, '<repo>');
  }
  if (home != null && home.isNotEmpty) {
    content = content.replaceAll(home, '<home>');
  }

  content = content
      .replaceAll(RegExp(r'/(?:Users|home)/[^/\s]+'), '<home>')
      .replaceAll(
        RegExp(r'[A-Za-z]:\\Users\\[^\\\s]+', caseSensitive: false),
        '<home>',
      )
      .replaceAll(
        RegExp(
          r'-----BEGIN [^-\r\n]*PRIVATE KEY-----[\s\S]*?'
          r'-----END [^-\r\n]*PRIVATE KEY-----',
        ),
        '<redacted-private-key>',
      );

  content = content.replaceAllMapped(
    RegExp(r'\b(authorization\s*:\s*bearer\s+)([^\s]+)', caseSensitive: false),
    (match) => '${match.group(1)}<redacted>',
  );
  content = content.replaceAllMapped(
    RegExp(
      r'\b((?:access[_-]?token|refresh[_-]?token|api[_-]?key|password|'
      r'secret|token)\s*[:=]\s*)([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}<redacted>',
  );
  content = content.replaceAll(
    RegExp(
      r'\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|'
      r'xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,})\b',
    ),
    '<redacted-token>',
  );

  return content;
}

String _normalizeTerminalOutput(String input) {
  final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return normalized
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
      .join('\n');
}

String _shellQuote(String argument) {
  if (argument.isEmpty) {
    return "''";
  }
  if (RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(argument)) {
    return argument;
  }
  if (RegExp(r'[\r\n\t]').hasMatch(argument)) {
    final escaped = argument
        .replaceAll('\\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    return "\$'$escaped'";
  }
  return "'${argument.replaceAll("'", "'\"'\"'")}'";
}
