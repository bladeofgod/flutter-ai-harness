import 'dart:io';

import 'src/media_capture_wire_generation.dart';

void main(List<String> arguments) {
  final exitCode = runMediaCaptureWireGenerator(
    arguments,
    standardOut: stdout,
    standardError: stderr,
  );
  if (exitCode != 0) {
    exit(exitCode);
  }
}

int runMediaCaptureWireGenerator(
  List<String> arguments, {
  required IOSink standardOut,
  required IOSink standardError,
}) {
  try {
    final options = _GeneratorOptions.parse(arguments);
    final root = options.root ?? _discoverRepositoryRoot();
    final result = MediaCaptureWireGenerator().run(
      root: root,
      runtime: options.runtime,
      outputPath: options.output,
      check: options.check,
    );
    final action = result.checked
        ? 'checked'
        : result.changed
        ? 'generated'
        : 'unchanged';
    standardOut.writeln(
      '[media-capture-wire] $action ${options.runtime.wireName} '
      'output (${result.sourceDigest})',
    );
    return 0;
  } on FormatException catch (error) {
    standardError.writeln('[media-capture-wire] ${error.message}');
    return 64;
  } on StateError catch (error) {
    standardError.writeln('[media-capture-wire] ${error.message}');
    return 1;
  } on FileSystemException catch (error) {
    standardError.writeln(
      '[media-capture-wire] ${error.message}'
      '${error.osError == null ? '' : ': ${error.osError!.message}'}',
    );
    return 74;
  }
}

Directory _discoverRepositoryRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File.fromUri(
          candidate.uri.resolve(mediaCaptureWireContractPath),
        ).existsSync() &&
        File.fromUri(candidate.uri.resolve('app/pubspec.yaml')).existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw const FormatException(
        'Unable to discover repository root; pass --root <path>',
      );
    }
    candidate = parent;
  }
}

final class _GeneratorOptions {
  const _GeneratorOptions({
    required this.runtime,
    required this.output,
    required this.root,
    required this.check,
  });

  final WireRuntime runtime;
  final String? output;
  final Directory? root;
  final bool check;

  static _GeneratorOptions parse(List<String> arguments) {
    WireRuntime? runtime;
    String? output;
    Directory? root;
    var check = false;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      switch (argument) {
        case '--runtime':
          runtime = WireRuntime.parse(_value(arguments, ++index, argument));
        case '--output':
          output = _value(arguments, ++index, argument);
        case '--root':
          root = Directory(_value(arguments, ++index, argument));
        case '--check':
          check = true;
        default:
          throw FormatException('Unknown argument: $argument\n$_usage');
      }
    }
    if (runtime == null) {
      throw const FormatException('Missing --runtime\n$_usage');
    }
    return _GeneratorOptions(
      runtime: runtime,
      output: output,
      root: root,
      check: check,
    );
  }

  static String _value(List<String> arguments, int index, String option) {
    if (index >= arguments.length || arguments[index].startsWith('--')) {
      throw FormatException('Missing value for $option\n$_usage');
    }
    return arguments[index];
  }
}

const String _usage =
    'Usage: dart run tool/generate_media_capture_wire.dart '
    '--runtime dart|android|ios [--output <path>] [--check] [--root <path>]';
