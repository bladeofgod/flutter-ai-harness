import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/media_capture_wire_generation.dart';

void main() {
  group('MediaCaptureWireGenerator', () {
    late _GeneratorFixture fixture;

    setUp(() {
      fixture = _GeneratorFixture.create();
    });

    tearDown(() {
      fixture.dispose();
    });

    test('generates all runtimes deterministically with one source digest', () {
      final digests = <String>{};
      for (final runtime in WireRuntime.values) {
        final first = fixture.generator.run(
          root: fixture.root,
          runtime: runtime,
        );
        final firstBytes = first.output.readAsBytesSync();
        final second = fixture.generator.run(
          root: fixture.root,
          runtime: runtime,
        );
        final checked = fixture.generator.run(
          root: fixture.root,
          runtime: runtime,
          check: true,
        );

        expect(first.changed, isTrue);
        expect(second.changed, isFalse);
        expect(checked.checked, isTrue);
        expect(second.output.readAsBytesSync(), firstBytes);
        final content = utf8.decode(firstBytes);
        expect(content, contains('DO NOT MODIFY BY HAND'));
        expect(content, contains('WirePayloadDescriptor'));
        expect(content, contains('WireErrorDescriptor'));
        expect(content, contains('WireErrorDetailDescriptor'));
        expect(content, contains('EnvelopeRequiredKeys'));
        expect(content, contains('SignedIntegerMinimum'));
        expect(content, contains('OpaqueHandleLengths'));
        expect(content, isNot(contains(fixture.root.path)));
        digests.add(first.sourceDigest);
      }
      expect(digests, hasLength(1));
    });

    test('generated Dart source is valid and formatter-stable', () {
      final output = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output;

      final result = Process.runSync(Platform.resolvedExecutable, <String>[
        'format',
        '--output=none',
        '--set-exit-if-changed',
        output.path,
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });

    test('--check is repository and temporary-filesystem read-only', () {
      final output = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output;
      final repositoryBefore = _treeSnapshot(fixture.root);
      final formatterTemporaryBefore = _formatterTemporaryDirectories();
      final generator = MediaCaptureWireGenerator(
        writer: const _UnexpectedAtomicFileWriter(),
      );

      final result = generator.run(
        root: fixture.root,
        runtime: WireRuntime.dart,
        check: true,
      );

      expect(result.checked, isTrue);
      expect(result.output.path, output.path);
      expect(_treeSnapshot(fixture.root), repositoryBefore);
      expect(_formatterTemporaryDirectories(), formatterTemporaryBefore);
    });

    test('normalizes CRLF inputs and root paths containing spaces', () {
      final baseline = <WireRuntime, List<int>>{};
      for (final runtime in WireRuntime.values) {
        final result = fixture.generator.run(
          root: fixture.root,
          runtime: runtime,
        );
        baseline[runtime] = result.output.readAsBytesSync();
      }

      final crlf = _GeneratorFixture.create();
      addTearDown(crlf.dispose);
      for (final input in <File>[crlf.contractFile, crlf.schemaFile]) {
        input.writeAsStringSync(
          input.readAsStringSync().replaceAll('\n', '\r\n'),
        );
      }
      expect(crlf.root.path, contains(' '));
      for (final runtime in WireRuntime.values) {
        final result = crlf.generator.run(root: crlf.root, runtime: runtime);
        expect(result.output.readAsBytesSync(), baseline[runtime]);
      }
    });

    test('rejects an output that is not registered for the runtime', () {
      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
          outputPath:
              'app/packages/app_media_capture_bridge/lib/src/other.g.dart',
        ),
        throwsFormatException,
      );
    });

    test('rejects a manifest path targeting an unrelated repository file', () {
      final unrelated =
          File.fromUri(fixture.root.uri.resolve('app/pubspec.yaml'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('sentinel');
      fixture.mutateContract((contract) {
        final manifest = contract['codeGeneration'] as Map<String, Object?>;
        final outputs = manifest['outputs'] as List<Object?>;
        final dartOutput = outputs.cast<Map<String, Object?>>().singleWhere(
          (entry) => entry['runtime'] == 'dart',
        );
        dartOutput['path'] = 'app/pubspec.yaml';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
      expect(unrelated.readAsStringSync(), 'sentinel');
    });

    test('rejects percent-encoded dot segments in a manifest path', () {
      fixture.mutateContract((contract) {
        final manifest = contract['codeGeneration'] as Map<String, Object?>;
        final outputs = manifest['outputs'] as List<Object?>;
        final dartOutput = outputs.cast<Map<String, Object?>>().singleWhere(
          (entry) => entry['runtime'] == 'dart',
        );
        dartOutput['path'] = 'app/%2e%2e/outside.dart';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('rejects a symbolic-link output parent that escapes the root', () {
      final output = fixture.outputFile(WireRuntime.dart);
      final parent = output.parent;
      parent.deleteSync(recursive: true);
      final outside = Directory.systemTemp.createTempSync('wire-outside-');
      addTearDown(() => outside.deleteSync(recursive: true));
      Link(parent.path).createSync(outside.path);

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
      expect(outside.listSync(), isEmpty);
    });

    test('rejects unknown manifest contract IDs', () {
      fixture.mutateContract((contract) {
        final generated = _generated(contract);
        (generated['methodIds'] as List<Object?>).add('unknown_method');
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('rejects runtime reserved names', () {
      fixture.mutateContract((contract) {
        final methods = contract['methods'] as List<Object?>;
        (methods.first as Map<String, Object?>)['id'] = 'class';
        final generated = _generated(contract);
        (generated['methodIds'] as List<Object?>)[0] = 'class';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('rejects language-specific reserved names', () {
      for (final entry in const <(WireRuntime, String)>[
        (WireRuntime.dart, 'factory'),
        (WireRuntime.android, 'typeof'),
        (WireRuntime.ios, 'guard'),
      ]) {
        final languageFixture = _GeneratorFixture.create();
        addTearDown(languageFixture.dispose);
        languageFixture.mutateContract((contract) {
          final methods = contract['methods'] as List<Object?>;
          (methods.first as Map<String, Object?>)['id'] = entry.$2;
          final generated = _generated(contract);
          (generated['methodIds'] as List<Object?>)[0] = entry.$2;
        });

        expect(
          () => languageFixture.generator.run(
            root: languageFixture.root,
            runtime: entry.$1,
          ),
          throwsFormatException,
          reason: '${entry.$1} ${entry.$2}',
        );
      }
    });

    test('rejects normalized runtime name collisions', () {
      fixture.mutateContract((contract) {
        final methods = contract['methods'] as List<Object?>;
        (methods[0] as Map<String, Object?>)['id'] = 'same_name';
        (methods[1] as Map<String, Object?>)['id'] = 'same__name';
        final methodIds = _generated(contract)['methodIds'] as List<Object?>;
        methodIds[0] = 'same_name';
        methodIds[1] = 'same__name';
      });

      expect(
        () =>
            fixture.generator.run(root: fixture.root, runtime: WireRuntime.ios),
        throwsFormatException,
      );
    });

    test('rejects normalized channel identifier collisions', () {
      fixture.mutateContract((contract) {
        final channels = contract['channels'] as List<Object?>;
        (channels[0] as Map<String, Object?>)['id'] = 'same_name';
        (channels[1] as Map<String, Object?>)['id'] = 'same__name';
        final channelIds = _generated(contract)['channelIds'] as List<Object?>;
        channelIds[0] = 'same_name';
        channelIds[1] = 'same__name';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate channel names', () {
      fixture.mutateContract((contract) {
        final channels = contract['channels'] as List<Object?>;
        (channels[1] as Map<String, Object?>)['name'] =
            (channels[0] as Map<String, Object?>)['name'];
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.android,
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate field wire keys', () {
      fixture.mutateContract((contract) {
        final fields = contract['fieldMappings'] as List<Object?>;
        (fields[1] as Map<String, Object?>)['key'] =
            (fields[0] as Map<String, Object?>)['key'];
      });

      expect(
        () =>
            fixture.generator.run(root: fixture.root, runtime: WireRuntime.ios),
        throwsFormatException,
      );
    });

    test('rejects duplicate wire values', () {
      fixture.mutateContract((contract) {
        final methods = contract['methods'] as List<Object?>;
        final duplicate = (methods[0] as Map<String, Object?>)['id'];
        (methods[1] as Map<String, Object?>)['id'] = duplicate;
        final methodIds = _generated(contract)['methodIds'] as List<Object?>;
        methodIds[1] = duplicate;
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.android,
        ),
        throwsFormatException,
      );
    });

    test('rejects duplicate closed error detail enum values', () {
      fixture.mutateContract((contract) {
        final details = contract['errorDetailFields'] as List<Object?>;
        final detail = details.first as Map<String, Object?>;
        final values = detail['enumValues'] as List<Object?>;
        values.add(values.first);
      });

      expect(
        () =>
            fixture.generator.run(root: fixture.root, runtime: WireRuntime.ios),
        throwsFormatException,
      );
    });

    test('rejects field types that a runtime cannot express', () {
      fixture.mutateContract((contract) {
        final fields = contract['fieldMappings'] as List<Object?>;
        (fields.first as Map<String, Object?>)['wireType'] = 'map';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.android,
        ),
        throwsFormatException,
      );
    });

    test('rejects unsafe channel text before rendering source code', () {
      fixture.mutateContract((contract) {
        final channels = contract['channels'] as List<Object?>;
        (channels.first as Map<String, Object?>)['name'] =
            'com.example.media_capture.commands"; injected';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('rejects non-boolean error attributes before source rendering', () {
      fixture.mutateContract((contract) {
        final errors = contract['errors'] as List<Object?>;
        (errors.first as Map<String, Object?>)['recoverable'] =
            'true); injectedSource();';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.android,
        ),
        throwsFormatException,
      );
    });

    test('rejects non-numeric field bounds before source rendering', () {
      fixture.mutateContract((contract) {
        final fields = contract['fieldMappings'] as List<Object?>;
        final validation =
            (fields.first as Map<String, Object?>)['validation']
                as Map<String, Object?>;
        validation['minimum'] = '0"); injectedSource(); //';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.android,
        ),
        throwsFormatException,
      );
    });

    test('rejects non-integer request ID lengths before source rendering', () {
      fixture.mutateContract((contract) {
        final lifecycle = contract['lifecycle'] as Map<String, Object?>;
        final policy = lifecycle['requestIdPolicy'] as Map<String, Object?>;
        policy['maxLength'] = '128; injectedSource()';
      });

      expect(
        () =>
            fixture.generator.run(root: fixture.root, runtime: WireRuntime.ios),
        throwsFormatException,
      );
    });

    test('rejects non-boolean field validation before source rendering', () {
      fixture.mutateContract((contract) {
        final fields = contract['fieldMappings'] as List<Object?>;
        final validation =
            (fields.first as Map<String, Object?>)['validation']
                as Map<String, Object?>;
        validation['finite'] = 'false; injectedSource()';
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('rejects non-integer opaque handle lengths before rendering', () {
      fixture.mutateContract((contract) {
        final transport =
            contract['transportConstraints'] as Map<String, Object?>;
        final handles = transport['opaqueHandles'] as List<Object?>;
        (handles.first as Map<String, Object?>)['maxLength'] =
            '128); injectedSource()';
      });

      expect(
        () =>
            fixture.generator.run(root: fixture.root, runtime: WireRuntime.ios),
        throwsFormatException,
      );
    });

    test('rejects coordinated Schema and Contract source injection', () {
      fixture.mutateSchema((schema) {
        final definitions = schema[r'$defs'] as Map<String, Object?>;
        final policy = definitions['requestIdPolicy'] as Map<String, Object?>;
        final properties = policy['properties'] as Map<String, Object?>;
        properties['maxLength'] = <String, Object?>{'type': 'string'};
      });
      fixture.mutateContract((contract) {
        final lifecycle = contract['lifecycle'] as Map<String, Object?>;
        final policy = lifecycle['requestIdPolicy'] as Map<String, Object?>;
        policy['maxLength'] = '128; injectedSource()';
      });
      final output = fixture.outputFile(WireRuntime.android);

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.android,
        ),
        throwsFormatException,
      );
      expect(output.existsSync(), isFalse);
    });

    test('rejects request and handle lengths outside Kotlin Int', () {
      for (final mutateRequest in <bool>[true, false]) {
        final rangeFixture = _GeneratorFixture.create();
        addTearDown(rangeFixture.dispose);
        rangeFixture.mutateContract((contract) {
          if (mutateRequest) {
            final lifecycle = contract['lifecycle'] as Map<String, Object?>;
            final policy = lifecycle['requestIdPolicy'] as Map<String, Object?>;
            policy['maxLength'] = 2147483648;
          } else {
            final transport =
                contract['transportConstraints'] as Map<String, Object?>;
            final handles = transport['opaqueHandles'] as List<Object?>;
            (handles.first as Map<String, Object?>)['maxLength'] = 2147483648;
          }
        });

        expect(
          () => rangeFixture.generator.run(
            root: rangeFixture.root,
            runtime: WireRuntime.android,
          ),
          throwsFormatException,
        );
      }
    });

    test('Kotlin escapes non-ASCII Contract strings as UTF-16', () {
      fixture.mutateContract((contract) {
        final lifecycle = contract['lifecycle'] as Map<String, Object?>;
        final policy = lifecycle['requestIdPolicy'] as Map<String, Object?>;
        policy['pattern'] = 'hello-\u4f60\u597d-\u{1f600}';
      });

      final kotlin = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.android)
          .output
          .readAsStringSync();
      expect(kotlin, contains(r'hello-\u4f60\u597d-\ud83d\ude00'));
    });

    test('all renderers emit scalar and collection range guards', () {
      final dart = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output
          .readAsStringSync();
      expect(dart, contains('value < _generatedSignedIntegerMinimum'));
      expect(dart, contains('value < field.minimum!'));
      expect(dart, contains('collectionLength < field.minItems!'));
      expect(dart, contains("field.type == 'list_string'"));
      expect(dart, contains('value.toSet().length != value.length'));
      expect(dart, contains('!(item as double).isFinite'));
      expect(dart, contains('item < _generatedSignedIntegerMinimum'));

      final kotlin = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.android)
          .output
          .readAsStringSync();
      expect(kotlin, contains('field.minimum?.toDoubleOrNull()'));
      expect(kotlin, contains('field.minimum?.toLongOrNull()'));
      expect(kotlin, contains('collectionSize < field.minItems'));
      expect(kotlin, contains('it is String && it in field.enumValues'));
      expect(kotlin, contains('value.toSet().size != value.size'));
      expect(kotlin, contains('field.type == "list_double"'));

      final swift = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.ios)
          .output
          .readAsStringSync();
      expect(swift, contains('field.minimum.flatMap(Double.init)'));
      expect(swift, contains('field.allowedIntegers.contains(number)'));
      expect(swift, contains('values.count < minimum'));
      expect(swift, contains('bytes.count < minimum'));
      expect(swift, contains('field.enumValues.contains'));
      expect(swift, contains('CFBooleanGetTypeID'));
      expect(swift, contains('CFNumberIsFloatType'));
      expect(swift, contains('Set(strings).count == strings.count'));
    });

    test('atomic replacement failure leaves no partial output', () {
      final generator = MediaCaptureWireGenerator(
        writer: SystemAtomicFileWriter(
          atomicReplace: (temporary, target) {
            throw FileSystemException('simulated replace failure', target.path);
          },
        ),
      );
      final output = fixture.outputFile(WireRuntime.dart);
      output.writeAsStringSync('sentinel');
      output.setLastModifiedSync(DateTime.fromMillisecondsSinceEpoch(100000));
      final beforeModified = output.lastModifiedSync();
      final beforeMode = output.statSync().mode;

      expect(
        () => generator.run(root: fixture.root, runtime: WireRuntime.dart),
        throwsA(isA<FileSystemException>()),
      );
      expect(output.readAsStringSync(), 'sentinel');
      expect(output.lastModifiedSync(), beforeModified);
      expect(output.statSync().mode, beforeMode);
      expect(
        output.parent.listSync().where((entry) => entry.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('--check behavior never repairs stale output', () {
      final output = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output;
      output.writeAsStringSync('stale output');

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
          check: true,
        ),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'stale output');
    });

    test('rejects input changes during formatting before any return', () {
      for (final check in <bool>[false, true]) {
        final changingFixture = _GeneratorFixture.create();
        addTearDown(changingFixture.dispose);
        final output = changingFixture.generator
            .run(root: changingFixture.root, runtime: WireRuntime.dart)
            .output;
        final outputBefore = output.readAsBytesSync();
        final generator = MediaCaptureWireGenerator(
          dartSourceFormatter: _CallbackDartSourceFormatter((source) {
            changingFixture.mutateContract((contract) {
              contract['description'] = 'changed during formatting';
            });
            return source;
          }),
        );

        expect(
          () => generator.run(
            root: changingFixture.root,
            runtime: WireRuntime.dart,
            check: check,
          ),
          throwsA(isA<FileSystemException>()),
          reason: 'check=$check',
        );
        expect(output.readAsBytesSync(), outputBefore);
      }
    });

    test('formatter failure leaves output and filesystem unchanged', () {
      final output = fixture.outputFile(WireRuntime.dart);
      final repositoryBefore = _treeSnapshot(fixture.root);
      final generator = MediaCaptureWireGenerator(
        dartSourceFormatter: const _FailingDartSourceFormatter(),
      );

      expect(
        () => generator.run(root: fixture.root, runtime: WireRuntime.dart),
        throwsFormatException,
      );
      expect(output.existsSync(), isFalse);
      expect(_treeSnapshot(fixture.root), repositoryBefore);
    });

    test('generation atomically replaces a stale ordinary output', () {
      final output = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output;
      output.writeAsStringSync('stale output');

      final result = fixture.generator.run(
        root: fixture.root,
        runtime: WireRuntime.dart,
      );

      expect(result.changed, isTrue);
      expect(output.readAsStringSync(), contains('DO NOT MODIFY BY HAND'));
      expect(
        output.parent.listSync().where((entry) => entry.path.endsWith('.tmp')),
        isEmpty,
      );
    });

    test('manual-only Contract description changes do not drift output', () {
      final before = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.ios)
          .output
          .readAsBytesSync();
      fixture.mutateContract((contract) {
        final security = contract['security'] as Map<String, Object?>;
        final policies = security['policies'] as List<Object?>;
        (policies.first as Map<String, Object?>)['description'] =
            'Updated manual-only policy description.';
      });
      final after = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.ios)
          .output
          .readAsBytesSync();

      expect(after, before);
    });

    test('unrendered transport policy IDs do not drift output', () {
      final before = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.android)
          .output
          .readAsBytesSync();
      fixture.mutateContract((contract) {
        final transport =
            contract['transportConstraints'] as Map<String, Object?>;
        final handles = transport['opaqueHandles'] as List<Object?>;
        (handles.first as Map<String, Object?>)['capabilityHandlePolicyId'] =
            'updated_handle_policy';
      });
      final after = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.android)
          .output
          .readAsBytesSync();

      expect(after, before);
    });

    test('unrendered channel kind does not drift output', () {
      final before = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.ios)
          .output
          .readAsBytesSync();
      fixture.mutateContract((contract) {
        final channels = contract['channels'] as List<Object?>;
        (channels.first as Map<String, Object?>)['kind'] = 'event_channel';
      });
      final after = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.ios)
          .output
          .readAsBytesSync();

      expect(after, before);
    });

    test('rendered field boundary changes drift output', () {
      final before = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output
          .readAsBytesSync();
      fixture.mutateContract((contract) {
        final fields = contract['fieldMappings'] as List<Object?>;
        final field = fields.first as Map<String, Object?>;
        final validation = field['validation'] as Map<String, Object?>;
        validation['boundarySource'] = 'updated_boundary';
      });
      final after = fixture.generator
          .run(root: fixture.root, runtime: WireRuntime.dart)
          .output
          .readAsBytesSync();

      expect(after, isNot(before));
    });

    test('rejects valid but unrelated manual-only pointers', () {
      fixture.mutateContract((contract) {
        final manifest = contract['codeGeneration'] as Map<String, Object?>;
        final manual = manifest['manualOnly'] as List<Object?>;
        final entry = manual.cast<Map<String, Object?>>().singleWhere(
          (item) => item['id'] == 'cross_field_validation',
        );
        entry['contractPointers'] = <Object?>['/wireVersion'];
      });

      expect(
        () => fixture.generator.run(
          root: fixture.root,
          runtime: WireRuntime.dart,
        ),
        throwsFormatException,
      );
    });

    test('base schema allows a contract without events or generation', () {
      final contract =
          jsonDecode(fixture.contractFile.readAsStringSync())
              as Map<String, Object?>;
      final schema =
          jsonDecode(fixture.schemaFile.readAsStringSync())
              as Map<String, Object?>;
      contract
        ..remove('codeGeneration')
        ..['events'] = <Object?>[]
        ..['asyncFailures'] = <Object?>[]
        ..['errorDetailFields'] = <Object?>[];

      expect(
        () => validateWireContractAgainstSchema(contract, schema),
        returnsNormally,
      );
    });

    test(
      'generated text excludes executable lifecycle and native behavior',
      () {
        for (final runtime in WireRuntime.values) {
          final content = fixture.generator
              .run(root: fixture.root, runtime: runtime)
              .output
              .readAsStringSync();
          for (final forbidden in const <String>[
            'linearizationPolicy',
            'lateResultPolicies',
            'callbackThread',
            'ownerGeneration',
            'fileUriPolicy',
            'nativeArtifacts',
            'Activity',
            'ViewController',
            'AVFoundation',
            'CameraX',
          ]) {
            expect(
              content,
              isNot(contains(forbidden)),
              reason: '$runtime $forbidden',
            );
          }
        }
      },
    );
  });
}

Map<String, Object?> _generated(Map<String, Object?> contract) {
  final manifest = contract['codeGeneration'] as Map<String, Object?>;
  return manifest['generated'] as Map<String, Object?>;
}

List<String> _treeSnapshot(Directory root) {
  final entries = root.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  return entries
      .map((entry) {
        final relative = entry.uri.toString().substring(
          root.uri.toString().length,
        );
        final stat = entry.statSync();
        final content = entry is File
            ? base64.encode(entry.readAsBytesSync())
            : entry is Link
            ? entry.targetSync()
            : '';
        return '$relative|${stat.type}|${stat.mode}|'
            '${stat.modified.microsecondsSinceEpoch}|$content';
      })
      .toList(growable: false);
}

Set<String> _formatterTemporaryDirectories() => Directory.systemTemp
    .listSync(followLinks: false)
    .where(
      (entry) =>
          entry is Directory &&
          entry.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last
              .startsWith('media-capture-wire-dart-format-$pid-'),
    )
    .map((entry) => entry.path)
    .toSet();

final class _CallbackDartSourceFormatter implements DartSourceFormatter {
  const _CallbackDartSourceFormatter(this._callback);

  final String Function(String source) _callback;

  @override
  String format(String source, {required bool check}) => _callback(source);
}

final class _FailingDartSourceFormatter implements DartSourceFormatter {
  const _FailingDartSourceFormatter();

  @override
  String format(String source, {required bool check}) {
    throw const FormatException('simulated formatter failure');
  }
}

final class _UnexpectedAtomicFileWriter implements AtomicFileWriter {
  const _UnexpectedAtomicFileWriter();

  @override
  void replace(File target, List<int> bytes) {
    throw StateError('--check invoked the atomic writer');
  }
}

final class _GeneratorFixture {
  _GeneratorFixture._(this.root, this.generator);

  final Directory root;
  final MediaCaptureWireGenerator generator;

  File get contractFile =>
      File.fromUri(root.uri.resolve(mediaCaptureWireContractPath));
  File get schemaFile =>
      File.fromUri(root.uri.resolve(mediaCaptureWireSchemaPath));

  static _GeneratorFixture create() {
    final repository = _repositoryRoot();
    final root = Directory.systemTemp.createTempSync(
      'media capture wire generator with spaces ',
    );
    final contract = File.fromUri(
      root.uri.resolve(mediaCaptureWireContractPath),
    );
    final schema = File.fromUri(root.uri.resolve(mediaCaptureWireSchemaPath));
    contract.parent.createSync(recursive: true);
    File.fromUri(
      repository.uri.resolve(mediaCaptureWireContractPath),
    ).copySync(contract.path);
    File.fromUri(
      repository.uri.resolve(mediaCaptureWireSchemaPath),
    ).copySync(schema.path);
    final fixture = _GeneratorFixture._(root, MediaCaptureWireGenerator());
    for (final runtime in WireRuntime.values) {
      fixture.outputFile(runtime).parent.createSync(recursive: true);
    }
    return fixture;
  }

  File outputFile(WireRuntime runtime) {
    final contract =
        jsonDecode(contractFile.readAsStringSync()) as Map<String, Object?>;
    final manifest = contract['codeGeneration'] as Map<String, Object?>;
    final outputs = manifest['outputs'] as List<Object?>;
    final output = outputs.cast<Map<String, Object?>>().singleWhere(
      (entry) => entry['runtime'] == runtime.wireName,
    );
    return File.fromUri(root.uri.resolve(output['path']! as String));
  }

  void mutateContract(void Function(Map<String, Object?>) mutation) {
    final contract =
        jsonDecode(contractFile.readAsStringSync()) as Map<String, Object?>;
    mutation(contract);
    contractFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(contract),
    );
  }

  void mutateSchema(void Function(Map<String, Object?>) mutation) {
    final schema =
        jsonDecode(schemaFile.readAsStringSync()) as Map<String, Object?>;
    mutation(schema);
    schemaFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(schema),
    );
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

Directory _repositoryRoot() {
  var candidate = Directory.current.absolute;
  while (!File.fromUri(
    candidate.uri.resolve(mediaCaptureWireContractPath),
  ).existsSync()) {
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Repository root not found');
    }
    candidate = parent;
  }
  return candidate;
}
