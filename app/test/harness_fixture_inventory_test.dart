import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final appRoot = Directory.current.absolute;
  final repositoryRoot = appRoot.parent;
  final inventoryFile = File.fromUri(
    appRoot.uri.resolve('test/fixtures/harness_fixture_inventory.jsonl'),
  );
  final scriptFile = File.fromUri(
    repositoryRoot.uri.resolve('scripts/quality/test-harness.sh'),
  );
  final cases = inventoryFile
      .readAsLinesSync()
      .map(_HarnessFixtureCase.parse)
      .toList(growable: false);
  final scriptLines = scriptFile.readAsLinesSync();

  group('Harness Fixture inventory', () {
    test('is complete, ordered, and uniquely classified', () {
      expect(cases, hasLength(578));
      expect(cases.where((entry) => entry.diagnostics.isEmpty), hasLength(37));
      expect(
        cases.where((entry) => entry.diagnostics.isNotEmpty),
        hasLength(541),
      );
      expect(cases.map((entry) => entry.id).toSet(), hasLength(cases.length));
      expect(
        cases.map((entry) => entry.mutation).toSet(),
        hasLength(cases.length),
      );
    });

    for (var index = 0; index < cases.length; index += 1) {
      final fixtureCase = cases[index];
      test(fixtureCase.id, () {
        expect(
          fixtureCase.id,
          'harness-${(index + 1).toString().padLeft(4, '0')}',
        );
        expect(fixtureCase.mutation, startsWith('${fixtureCase.callSite}#'));

        final line = int.parse(fixtureCase.callSite.split(':').last);
        expect(line, inInclusiveRange(1, scriptLines.length));
        expect(scriptLines[line - 1], contains('run_check'));
        expect(
          fixtureCase.diagnostics,
          everyElement(
            isA<String>().having((value) => value, 'value', isNotEmpty),
          ),
        );
      });
    }
  });
}

final class _HarnessFixtureCase {
  const _HarnessFixtureCase({
    required this.id,
    required this.mutation,
    required this.callSite,
    required this.diagnostics,
  });

  final String id;
  final String mutation;
  final String callSite;
  final List<String> diagnostics;

  factory _HarnessFixtureCase.parse(String line) {
    final json = jsonDecode(line);
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['mutation'] is! String ||
        json['callSite'] is! String ||
        json['diagnostics'] is! List<Object?> ||
        (json['diagnostics']! as List<Object?>).any(
          (diagnostic) => diagnostic is! String,
        )) {
      throw const FormatException('Invalid Harness Fixture inventory entry.');
    }
    return _HarnessFixtureCase(
      id: json['id']! as String,
      mutation: json['mutation']! as String,
      callSite: json['callSite']! as String,
      diagnostics: List<String>.unmodifiable(
        (json['diagnostics']! as List<Object?>).cast<String>(),
      ),
    );
  }
}
