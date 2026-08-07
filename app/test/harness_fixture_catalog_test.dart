import 'dart:io';

import 'package:flutter_ai_harness_workspace/harness_validator.dart';
import 'package:test/test.dart';

import 'support/harness_fixture_catalog.dart';

void main() {
  final appRoot = Directory.current.absolute;
  final catalog = HarnessFixtureCatalog.load(appRoot);

  group('Harness parameterized Fixture catalog', () {
    test('preserves the complete legacy inventory', () {
      expect(catalog.cases, hasLength(578));
      expect(
        catalog.cases.where((fixtureCase) => fixtureCase.diagnostics.isEmpty),
        hasLength(37),
      );
      expect(
        catalog.cases.where(
          (fixtureCase) => fixtureCase.diagnostics.isNotEmpty,
        ),
        hasLength(541),
      );
      expect(
        catalog.cases.map((fixtureCase) => fixtureCase.id).toSet(),
        hasLength(catalog.cases.length),
      );
    });

    for (final fixtureCase in catalog.cases) {
      test('${fixtureCase.id} ${fixtureCase.mutation}', () {
        final fixture = catalog.materialize(fixtureCase);
        addTearDown(fixture.dispose);

        final result = validateHarness(fixture.root);

        expect(
          result.diagnostics,
          orderedEquals(fixtureCase.diagnostics),
          reason: fixtureCase.mutation,
        );
        expect(
          result.isValid,
          fixtureCase.diagnostics.isEmpty,
          reason: fixtureCase.mutation,
        );
      });
    }
  });
}
