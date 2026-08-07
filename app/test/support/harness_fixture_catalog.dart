import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final class HarnessFixtureCatalog {
  HarnessFixtureCatalog._({required this.blobs, required this.cases});

  final Directory blobs;
  final List<HarnessFixtureCase> cases;

  factory HarnessFixtureCatalog.load(Directory appRoot) {
    final fixtureRoot = Directory.fromUri(
      appRoot.uri.resolve('test/fixtures/harness_cases/'),
    );
    final blobs = Directory.fromUri(fixtureRoot.uri.resolve('blobs/'));
    final catalogFile = File.fromUri(fixtureRoot.uri.resolve('cases.jsonl'));
    if (!blobs.existsSync() || !catalogFile.existsSync()) {
      throw const FormatException('Harness Fixture catalog is incomplete.');
    }

    final validStates = <String, Map<String, HarnessFixtureEntity>>{};
    final cases = <HarnessFixtureCase>[];
    for (final line in catalogFile.readAsLinesSync()) {
      final fixtureCase = HarnessFixtureCase.parse(line, validStates);
      cases.add(fixtureCase);
      if (fixtureCase.diagnostics.isEmpty) {
        validStates[fixtureCase.id] = fixtureCase.state;
      }
    }
    return HarnessFixtureCatalog._(
      blobs: blobs,
      cases: List<HarnessFixtureCase>.unmodifiable(cases),
    );
  }

  MaterializedHarnessFixture materialize(
    HarnessFixtureCase fixtureCase, {
    String? label,
  }) {
    final parent = Directory.systemTemp.createTempSync(
      'harness dart fixture ${label ?? fixtureCase.id} ',
    );
    final root = Directory.fromUri(parent.uri.resolve('repo with spaces/'));
    root.createSync();
    try {
      final entries = fixtureCase.state.entries.toList()
        ..sort((left, right) {
          final depth = _pathDepth(left.key).compareTo(_pathDepth(right.key));
          return depth != 0 ? depth : left.key.compareTo(right.key);
        });
      for (final entry in entries) {
        final target = File.fromUri(root.uri.resolve(entry.key));
        switch (entry.value.type) {
          case HarnessFixtureEntityType.directory:
            Directory(target.path).createSync();
          case HarnessFixtureEntityType.file:
            target.parent.createSync(recursive: true);
            target.writeAsBytesSync(_readBlob(entry.value.value!), flush: true);
          case HarnessFixtureEntityType.link:
            target.parent.createSync(recursive: true);
            Link(target.path).createSync(entry.value.value!);
        }
      }
      return MaterializedHarnessFixture._(root);
    } on Object {
      parent.deleteSync(recursive: true);
      rethrow;
    }
  }

  List<int> _readBlob(String digest) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw FormatException('Invalid Harness Fixture blob digest: $digest');
    }
    final file = File.fromUri(blobs.uri.resolve('$digest.gz'));
    if (!file.existsSync()) {
      throw FormatException('Missing Harness Fixture blob: $digest');
    }
    final bytes = gzip.decode(file.readAsBytesSync());
    if (sha256.convert(bytes).toString() != digest) {
      throw FormatException('Harness Fixture blob digest mismatch: $digest');
    }
    return bytes;
  }
}

final class HarnessFixtureCase {
  HarnessFixtureCase._({
    required this.id,
    required this.mutation,
    required this.callSite,
    required this.diagnostics,
    required this.baseId,
    required this.state,
  });

  final String id;
  final String mutation;
  final String callSite;
  final List<String> diagnostics;
  final String? baseId;
  final Map<String, HarnessFixtureEntity> state;

  factory HarnessFixtureCase.parse(
    String line,
    Map<String, Map<String, HarnessFixtureEntity>> validStates,
  ) {
    final json = jsonDecode(line);
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['mutation'] is! String ||
        json['callSite'] is! String ||
        json['diagnostics'] is! List<Object?> ||
        (json['diagnostics']! as List<Object?>).any(
          (diagnostic) => diagnostic is! String,
        ) ||
        json['writes'] is! List<Object?> ||
        json['deletes'] is! List<Object?>) {
      throw const FormatException('Invalid Harness Fixture catalog entry.');
    }
    final id = json['id']! as String;
    final baseId = json['baseId'];
    if (baseId != null && baseId is! String) {
      throw FormatException('$id has an invalid baseId.');
    }
    final base = baseId == null ? null : validStates[baseId];
    if (baseId != null && base == null) {
      throw FormatException('$id references an unknown valid base: $baseId');
    }
    final state = Map<String, HarnessFixtureEntity>.of(
      base ?? const <String, HarnessFixtureEntity>{},
    );
    for (final value in json['deletes']! as List<Object?>) {
      if (value is! String) {
        throw FormatException('$id contains a non-string delete path.');
      }
      _validateRelativePath(value, id);
      state.removeWhere(
        (path, _) => path == value || path.startsWith('$value/'),
      );
    }
    for (final value in json['writes']! as List<Object?>) {
      final entity = HarnessFixtureEntity.parse(value, id);
      state.removeWhere(
        (path, _) => path == entity.path || path.startsWith('${entity.path}/'),
      );
      state[entity.path] = entity;
    }
    return HarnessFixtureCase._(
      id: id,
      mutation: json['mutation']! as String,
      callSite: json['callSite']! as String,
      diagnostics: List<String>.unmodifiable(
        (json['diagnostics']! as List<Object?>).cast<String>(),
      ),
      baseId: baseId as String?,
      state: Map<String, HarnessFixtureEntity>.unmodifiable(state),
    );
  }
}

enum HarnessFixtureEntityType { directory, file, link }

final class HarnessFixtureEntity {
  const HarnessFixtureEntity._({
    required this.path,
    required this.type,
    required this.value,
  });

  final String path;
  final HarnessFixtureEntityType type;
  final String? value;

  factory HarnessFixtureEntity.parse(Object? value, String caseId) {
    if (value is! Map<String, Object?> ||
        value['path'] is! String ||
        value['type'] is! String) {
      throw FormatException('$caseId contains an invalid write entry.');
    }
    final path = value['path']! as String;
    _validateRelativePath(path, caseId);
    final type = switch (value['type']) {
      'directory' => HarnessFixtureEntityType.directory,
      'file' => HarnessFixtureEntityType.file,
      'link' => HarnessFixtureEntityType.link,
      final Object? type => throw FormatException(
        '$caseId contains an unknown Fixture entity type: $type',
      ),
    };
    final entityValue = switch (type) {
      HarnessFixtureEntityType.directory => null,
      HarnessFixtureEntityType.file => value['digest'],
      HarnessFixtureEntityType.link => value['target'],
    };
    if (entityValue != null && entityValue is! String ||
        type != HarnessFixtureEntityType.directory && entityValue == null) {
      throw FormatException('$caseId contains invalid Fixture entity data.');
    }
    return HarnessFixtureEntity._(
      path: path,
      type: type,
      value: entityValue as String?,
    );
  }
}

final class MaterializedHarnessFixture {
  MaterializedHarnessFixture._(this.root);

  final Directory root;

  void dispose() {
    final parent = root.parent;
    if (parent.existsSync()) {
      parent.deleteSync(recursive: true);
    }
  }
}

void _validateRelativePath(String path, String caseId) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.split('/').any((segment) => segment.isEmpty || segment == '..')) {
    throw FormatException('$caseId contains an unsafe Fixture path: $path');
  }
}

int _pathDepth(String path) => '/'.allMatches(path).length;
