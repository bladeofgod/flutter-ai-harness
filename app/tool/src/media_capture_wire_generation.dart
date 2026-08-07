import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_style/dart_style.dart';

const String mediaCaptureWireContractPath =
    'docs/bridge/contracts/media-capture.wire.json';
const String mediaCaptureWireSchemaPath =
    'docs/bridge/contracts/wire.schema.json';
const String _normalizedWireSchemaDigest =
    '1bb09ff40b4b9caf382016725aa57230cd1c8b35de25c51b12cbb2859db37f1f';

const Map<WireRuntime, String> _registeredOutputPaths = <WireRuntime, String>{
  WireRuntime.dart:
      'app/packages/app_media_capture_bridge/lib/src/media_capture_wire.g.dart',
  WireRuntime.android:
      'app/packages/app_media_capture_bridge/android/src/main/kotlin/'
      'com/example/media_capture/MediaCaptureWire.g.kt',
  WireRuntime.ios:
      'app/packages/app_media_capture_bridge/ios/app_media_capture_bridge/'
      'Sources/MediaCaptureBridgeCore/MediaCaptureWire.generated.swift',
};

enum WireRuntime {
  dart('dart'),
  android('android'),
  ios('ios');

  const WireRuntime(this.wireName);

  final String wireName;

  static WireRuntime parse(String value) => values.firstWhere(
    (runtime) => runtime.wireName == value,
    orElse: () => throw FormatException('Unsupported runtime: $value'),
  );
}

final class WireGenerationOutput {
  const WireGenerationOutput({
    required this.runtime,
    required this.language,
    required this.path,
  });

  final WireRuntime runtime;
  final String language;
  final String path;
}

final class WireFieldDescriptor {
  const WireFieldDescriptor({
    required this.id,
    required this.key,
    required this.wireType,
    required this.required,
    required this.nullable,
    required this.enumValues,
    required this.validation,
  });

  final String id;
  final String key;
  final String wireType;
  final bool required;
  final bool nullable;
  final List<String> enumValues;
  final Map<String, Object?> validation;

  Map<String, Object?> get sourceProjection => <String, Object?>{
    'id': id,
    'key': key,
    'wireType': wireType,
    'required': required,
    'nullable': nullable,
    'enumValues': enumValues,
    'validation': <String, Object?>{
      for (final key in const <String>[
        'finite',
        'minimum',
        'maximum',
        'allowedIntegers',
        'minItems',
        'maxItems',
        'format',
        'boundarySource',
        'outOfRangePolicy',
      ])
        key: validation[key],
    },
  };
}

final class WirePayloadDescriptor {
  const WirePayloadDescriptor({
    required this.id,
    required this.kind,
    required this.fieldIds,
    required this.unknownFieldPolicy,
  });

  final String id;
  final String kind;
  final List<String> fieldIds;
  final String unknownFieldPolicy;

  Map<String, Object?> get sourceProjection => <String, Object?>{
    'id': id,
    'kind': kind,
    'fieldIds': fieldIds,
    'unknownFieldPolicy': unknownFieldPolicy,
  };
}

final class MediaCaptureWireGenerationModel {
  MediaCaptureWireGenerationModel._({
    required this.generatorVersion,
    required this.wireVersion,
    required this.outputs,
    required this.channels,
    required this.methodIds,
    required this.eventIds,
    required this.resultTypeIds,
    required this.failureTypeIds,
    required this.errorCodes,
    required this.errorDescriptors,
    required this.errorDetailDescriptors,
    required this.fields,
    required this.payloads,
    required this.envelopes,
    required this.transportConstraints,
  }) : sourceDigest = _calculateSourceDigest(<String, Object?>{
         'generatorVersion': generatorVersion,
         'wireVersion': wireVersion,
         'channels': <Object?>[
           for (final channel in channels)
             <String, Object?>{'id': channel['id'], 'name': channel['name']},
         ],
         'methodIds': methodIds,
         'eventIds': eventIds,
         'resultTypeIds': resultTypeIds,
         'failureTypeIds': failureTypeIds,
         'errors': errorDescriptors,
         'errorDetails': errorDetailDescriptors,
         'fields': fields.map((field) => field.sourceProjection).toList(),
         'payloads': payloads
             .map((payload) => payload.sourceProjection)
             .toList(),
         'envelopes': _generatedEnvelopeProjection(envelopes),
         'transportConstraints': _generatedTransportProjection(
           transportConstraints,
         ),
       });

  final int generatorVersion;
  final int wireVersion;
  final List<WireGenerationOutput> outputs;
  final List<Map<String, Object?>> channels;
  final List<String> methodIds;
  final List<String> eventIds;
  final List<String> resultTypeIds;
  final List<String> failureTypeIds;
  final List<String> errorCodes;
  final List<Map<String, Object?>> errorDescriptors;
  final List<Map<String, Object?>> errorDetailDescriptors;
  final List<WireFieldDescriptor> fields;
  final List<WirePayloadDescriptor> payloads;
  final Map<String, Object?> envelopes;
  final Map<String, Object?> transportConstraints;
  final String sourceDigest;

  WireGenerationOutput outputFor(WireRuntime runtime) =>
      outputs.singleWhere((output) => output.runtime == runtime);

  static MediaCaptureWireGenerationModel parse(
    Map<String, Object?> contract,
    Map<String, Object?> schema,
  ) {
    _validateSchemaRegistration(schema);
    validateWireContractAgainstSchema(contract, schema);
    final manifest = _object(contract['codeGeneration'], 'codeGeneration');
    _expectExactKeys(manifest, const <String>{
      'generatorVersion',
      'sourceDigestAlgorithm',
      'outputs',
      'generated',
      'manualOnly',
    }, 'codeGeneration');
    final generatorVersion = _positiveInt(
      manifest['generatorVersion'],
      'codeGeneration.generatorVersion',
    );
    if (manifest['sourceDigestAlgorithm'] != 'sha256') {
      throw const FormatException(
        'codeGeneration.sourceDigestAlgorithm must be sha256',
      );
    }

    final outputs = _parseOutputs(manifest['outputs']);
    final generated = _object(
      manifest['generated'],
      'codeGeneration.generated',
    );
    _expectExactKeys(generated, const <String>{
      'wireVersionPointer',
      'channelIds',
      'methodIds',
      'eventIds',
      'resultTypeIds',
      'failureTypeIds',
      'errorCodes',
      'errorPropertyNames',
      'errorDetailKeys',
      'payloadIds',
      'fieldIds',
      'envelopePointers',
      'transportConstraintPointers',
    }, 'codeGeneration.generated');
    if (generated['wireVersionPointer'] != '/wireVersion') {
      throw const FormatException(
        'codeGeneration.generated.wireVersionPointer is invalid',
      );
    }
    final wireVersion = _positiveInt(contract['wireVersion'], 'wireVersion');

    final channels = _objects(contract['channels'], 'channels')
      ..sort(_compareById);
    for (final channel in channels) {
      _expectExactKeys(channel, const <String>{
        'id',
        'kind',
        'name',
      }, 'channel');
      _validateStableId(_id(channel, 'channel'), 'channel.id');
      final kind = _string(channel['kind'], 'channel.kind');
      if (kind != 'method_channel' && kind != 'event_channel') {
        throw FormatException('Unsupported channel kind: $kind');
      }
      final name = _string(channel['name'], 'channel.name');
      if (!RegExp(
        r'^com\.example\.[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$',
      ).hasMatch(name)) {
        throw FormatException('Unsafe channel name: $name');
      }
    }
    _rejectDuplicates(
      channels.map((entry) => _string(entry['name'], 'channel.name')).toList(),
      'channel names',
    );
    final channelIds = channels.map((entry) => _id(entry, 'channels')).toList();
    _validateReferenceSet(generated, 'channelIds', channelIds);

    final methods = _objects(contract['methods'], 'methods')
      ..sort(_compareById);
    final methodIds = methods.map((entry) => _id(entry, 'methods')).toList();
    _validateReferenceSet(generated, 'methodIds', methodIds);
    final resultTypeIds = <String>{};
    for (final method in methods) {
      final resultType = method['resultType'];
      if (resultType is String) {
        resultTypeIds.add(resultType);
      }
      final terminalOutcomes = method['terminalOutcomes'];
      if (terminalOutcomes is List<Object?>) {
        for (final outcome in terminalOutcomes) {
          final result = _object(
            outcome,
            'method.terminalOutcomes',
          )['resultType'];
          if (result is String) {
            resultTypeIds.add(result);
          }
        }
      }
    }
    final sortedResultTypeIds = resultTypeIds.toList()..sort();
    _validateReferenceSet(generated, 'resultTypeIds', sortedResultTypeIds);

    final events = _objects(contract['events'], 'events')..sort(_compareById);
    final eventIds = events.map((entry) => _id(entry, 'events')).toList();
    _validateReferenceSet(generated, 'eventIds', eventIds);
    final failures = _objects(contract['asyncFailures'], 'asyncFailures')
      ..sort(_compareById);
    final failureTypeIds = failures
        .map((entry) => _id(entry, 'asyncFailures'))
        .toList();
    _validateReferenceSet(generated, 'failureTypeIds', failureTypeIds);

    final errors =
        _objects(contract['errors'], 'errors').map(_parseError).toList()..sort(
          (left, right) => _string(
            left['code'],
            'error.code',
          ).compareTo(_string(right['code'], 'error.code')),
        );
    final errorCodes = errors
        .map((entry) => _string(entry['code'], 'error.code'))
        .toList();
    _validateReferenceSet(generated, 'errorCodes', errorCodes);
    final errorPropertyNames = _strings(
      generated['errorPropertyNames'],
      'codeGeneration.generated.errorPropertyNames',
    );
    const expectedErrorProperties = <String>{
      'source',
      'capabilityFailureId',
      'recoverable',
      'terminal',
      'messagePolicy',
      'detailsAllowedKeys',
    };
    if (errorPropertyNames.toSet().length != errorPropertyNames.length ||
        errorPropertyNames
            .toSet()
            .difference(expectedErrorProperties)
            .isNotEmpty ||
        expectedErrorProperties
            .difference(errorPropertyNames.toSet())
            .isNotEmpty) {
      throw const FormatException(
        'codeGeneration.generated.errorPropertyNames is incomplete',
      );
    }
    final details =
        _objects(
          contract['errorDetailFields'],
          'errorDetailFields',
        ).map(_parseErrorDetail).toList()..sort(
          (left, right) => _string(
            left['key'],
            'error detail key',
          ).compareTo(_string(right['key'], 'error detail key')),
        );
    final detailKeys = details
        .map((entry) => _string(entry['key'], 'error detail key'))
        .toList();
    _validateReferenceSet(generated, 'errorDetailKeys', detailKeys);
    final detailKeySet = detailKeys.toSet();
    for (final error in errors) {
      final unknownDetails = _strings(
        error['detailsAllowedKeys'],
        'error.detailsAllowedKeys',
      ).toSet().difference(detailKeySet);
      if (unknownDetails.isNotEmpty) {
        throw FormatException(
          'Error ${error['code']} references unknown detail keys: '
          '${unknownDetails.toList()..sort()}',
        );
      }
    }

    final fieldObjects = _objects(contract['fieldMappings'], 'fieldMappings')
      ..sort(
        (left, right) => _string(
          left['capabilityFieldId'],
          'field id',
        ).compareTo(_string(right['capabilityFieldId'], 'field id')),
      );
    final fields = fieldObjects.map(_parseField).toList();
    _rejectDuplicates(
      fields.map((field) => field.key).toList(),
      'field wire keys',
    );
    _validateReferenceSet(
      generated,
      'fieldIds',
      fields.map((field) => field.id).toList(),
    );
    final fieldIds = fields.map((field) => field.id).toSet();

    final payloadObjects = <Map<String, Object?>>[
      ..._objects(contract['payloads'], 'payloads'),
      ..._objects(contract['failurePayloads'], 'failurePayloads'),
    ]..sort(_compareById);
    final payloads = payloadObjects.map((entry) {
      final isFailurePayload = entry.containsKey('contextFieldIds');
      final fieldReferences = _strings(
        isFailurePayload ? entry['contextFieldIds'] : entry['fieldIds'],
        isFailurePayload
            ? 'failurePayload.contextFieldIds'
            : 'payload.fieldIds',
      );
      final unknown = fieldReferences.toSet().difference(fieldIds);
      if (unknown.isNotEmpty) {
        throw FormatException(
          'Payload references unknown fields: ${unknown.join(', ')}',
        );
      }
      if (entry['unknownFieldPolicy'] != 'reject') {
        throw FormatException(
          'Payload ${entry['id']} must reject unknown fields',
        );
      }
      return WirePayloadDescriptor(
        id: _id(entry, 'payload'),
        kind: isFailurePayload
            ? 'failure'
            : _string(entry['kind'], 'payload.kind'),
        fieldIds: List<String>.unmodifiable(fieldReferences),
        unknownFieldPolicy: 'reject',
      );
    }).toList();
    _validateReferenceSet(
      generated,
      'payloadIds',
      payloads.map((payload) => payload.id).toList(),
    );

    final envelopes = <String, Object?>{};
    for (final pointer in _validatedPointerSet(
      contract,
      generated,
      'envelopePointers',
      const <String>{
        '/lifecycle/requestEnvelope',
        '/lifecycle/resultEnvelope',
        '/lifecycle/eventListenEnvelope',
        '/lifecycle/eventEnvelope',
        '/lifecycle/failureEnvelope',
        '/lifecycle/requestIdPolicy',
      },
    )) {
      envelopes[pointer] = _normalizeGeneratedEnvelope(
        pointer,
        _readJsonPointer(contract, pointer),
      );
    }
    final transportConstraints = <String, Object?>{};
    for (final pointer in _validatedPointerSet(
      contract,
      generated,
      'transportConstraintPointers',
      const <String>{
        '/transportConstraints/signedInteger',
        '/transportConstraints/opaqueHandles',
      },
    )) {
      transportConstraints[pointer] = _normalizeGeneratedTransportConstraint(
        pointer,
        _readJsonPointer(contract, pointer),
      );
    }
    _validateManualOnly(contract, manifest['manualOnly']);
    _validateRuntimeNames(outputs, <String, List<String>>{
      'channel': channelIds,
      'method': methodIds,
      'event': eventIds,
      'result': sortedResultTypeIds,
      'failure': failureTypeIds,
      'error': errorCodes,
      'payload': payloads.map((payload) => payload.id).toList(),
      'field': fields.map((field) => field.id).toList(),
    });

    return MediaCaptureWireGenerationModel._(
      generatorVersion: generatorVersion,
      wireVersion: wireVersion,
      outputs: List<WireGenerationOutput>.unmodifiable(outputs),
      channels: List<Map<String, Object?>>.unmodifiable(
        channels.map((entry) => Map<String, Object?>.unmodifiable(entry)),
      ),
      methodIds: List<String>.unmodifiable(methodIds),
      eventIds: List<String>.unmodifiable(eventIds),
      resultTypeIds: List<String>.unmodifiable(sortedResultTypeIds),
      failureTypeIds: List<String>.unmodifiable(failureTypeIds),
      errorCodes: List<String>.unmodifiable(errorCodes),
      errorDescriptors: List<Map<String, Object?>>.unmodifiable(
        errors.map((entry) => Map<String, Object?>.unmodifiable(entry)),
      ),
      errorDetailDescriptors: List<Map<String, Object?>>.unmodifiable(
        details.map((entry) => Map<String, Object?>.unmodifiable(entry)),
      ),
      fields: List<WireFieldDescriptor>.unmodifiable(fields),
      payloads: List<WirePayloadDescriptor>.unmodifiable(payloads),
      envelopes: Map<String, Object?>.unmodifiable(envelopes),
      transportConstraints: Map<String, Object?>.unmodifiable(
        transportConstraints,
      ),
    );
  }
}

abstract interface class AtomicFileWriter {
  void replace(File target, List<int> bytes);
}

abstract interface class DartSourceFormatter {
  String format(String source, {required bool check});
}

final class SystemDartSourceFormatter implements DartSourceFormatter {
  SystemDartSourceFormatter()
    : _formatter = DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
        lineEnding: '\n',
      );

  final DartFormatter _formatter;

  @override
  String format(String source, {required bool check}) {
    try {
      return _formatter.format(source, uri: '<generated Dart source>');
    } on FormatterException catch (error) {
      throw FormatException(error.message(color: false));
    }
  }
}

typedef AtomicReplace = void Function(File temporary, File target);

final class SystemAtomicFileWriter implements AtomicFileWriter {
  SystemAtomicFileWriter({AtomicReplace? atomicReplace})
    : _atomicReplace = atomicReplace ?? _rename;

  final AtomicReplace _atomicReplace;

  @override
  void replace(File target, List<int> bytes) {
    final random = Random.secure();
    File? temporary;
    try {
      for (var attempt = 0; attempt < 16; attempt += 1) {
        final suffix = random.nextInt(0x7fffffff).toRadixString(16);
        final candidate = File('${target.path}.$pid.$suffix.tmp');
        try {
          candidate.createSync(exclusive: true);
          temporary = candidate;
          break;
        } on FileSystemException {
          if (attempt == 15) {
            rethrow;
          }
        }
      }
      if (temporary == null) {
        throw FileSystemException('Unable to reserve temporary output');
      }
      temporary.writeAsBytesSync(bytes, flush: true);
      _atomicReplace(temporary, target);
      temporary = null;
    } finally {
      if (temporary?.existsSync() ?? false) {
        temporary!.deleteSync();
      }
    }
  }

  static void _rename(File temporary, File target) {
    temporary.renameSync(target.path);
  }
}

final class WireGenerationResult {
  const WireGenerationResult({
    required this.output,
    required this.changed,
    required this.checked,
    required this.sourceDigest,
  });

  final File output;
  final bool changed;
  final bool checked;
  final String sourceDigest;
}

final class MediaCaptureWireGenerator {
  MediaCaptureWireGenerator({
    AtomicFileWriter? writer,
    DartSourceFormatter? dartSourceFormatter,
  }) : _writer = writer ?? SystemAtomicFileWriter(),
       _dartSourceFormatter =
           dartSourceFormatter ?? SystemDartSourceFormatter();

  final AtomicFileWriter _writer;
  final DartSourceFormatter _dartSourceFormatter;

  WireGenerationResult run({
    required Directory root,
    required WireRuntime runtime,
    String? outputPath,
    bool check = false,
  }) {
    final canonicalRoot = _canonicalRoot(root);
    final contractFile = _safeInput(
      canonicalRoot,
      mediaCaptureWireContractPath,
    );
    final schemaFile = _safeInput(canonicalRoot, mediaCaptureWireSchemaPath);
    final contractBytes = contractFile.readAsBytesSync();
    final schemaBytes = schemaFile.readAsBytesSync();
    if (_normalizedTextDigest(schemaBytes) != _normalizedWireSchemaDigest) {
      throw const FormatException(
        'Wire Schema does not match the generator implementation',
      );
    }
    final contractDigest = sha256.convert(contractBytes);
    final schemaDigest = sha256.convert(schemaBytes);
    final contract = _decodeObject(contractBytes, mediaCaptureWireContractPath);
    final schema = _decodeObject(schemaBytes, mediaCaptureWireSchemaPath);
    final model = MediaCaptureWireGenerationModel.parse(contract, schema);
    final registered = model.outputFor(runtime);
    final output = _safeOutput(canonicalRoot, outputPath ?? registered.path);
    final registeredOutput = _safeOutput(canonicalRoot, registered.path);
    if (output.absolute.path != registeredOutput.absolute.path) {
      throw FormatException(
        'Output is not registered for ${runtime.wireName}: ${output.path}',
      );
    }
    final source = _render(runtime, model);
    final formattedSource = runtime == WireRuntime.dart
        ? _dartSourceFormatter.format(source, check: check)
        : source;
    final rendered = utf8.encode(_singleTerminalNewline(formattedSource));
    _assertInputsUnchanged(
      contractFile: contractFile,
      schemaFile: schemaFile,
      contractDigest: contractDigest,
      schemaDigest: schemaDigest,
    );
    final current = output.existsSync() ? output.readAsBytesSync() : null;
    final matches = current != null && _bytesEqual(current, rendered);
    if (check) {
      if (!matches) {
        throw StateError(
          'Generated output is missing or stale: ${registered.path}',
        );
      }
      return WireGenerationResult(
        output: output,
        changed: false,
        checked: true,
        sourceDigest: model.sourceDigest,
      );
    }
    if (matches) {
      return WireGenerationResult(
        output: output,
        changed: false,
        checked: false,
        sourceDigest: model.sourceDigest,
      );
    }
    _assertOrdinaryPath(canonicalRoot, output.path, requireTarget: false);
    _writer.replace(output, rendered);
    return WireGenerationResult(
      output: output,
      changed: true,
      checked: false,
      sourceDigest: model.sourceDigest,
    );
  }
}

void _assertInputsUnchanged({
  required File contractFile,
  required File schemaFile,
  required Digest contractDigest,
  required Digest schemaDigest,
}) {
  if (sha256.convert(contractFile.readAsBytesSync()) != contractDigest ||
      sha256.convert(schemaFile.readAsBytesSync()) != schemaDigest) {
    throw const FileSystemException(
      'Wire Contract or Schema changed during generation',
    );
  }
}

Map<String, Object?> _decodeObject(List<int> bytes, String label) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    return _object(decoded, label);
  } on FormatException catch (error) {
    throw FormatException('$label is invalid JSON: ${error.message}');
  }
}

String _normalizedTextDigest(List<int> bytes) {
  final normalized = utf8.decode(bytes).replaceAll('\r\n', '\n');
  return sha256.convert(utf8.encode(normalized)).toString();
}

Directory _canonicalRoot(Directory root) {
  final absolute = root.absolute;
  if (FileSystemEntity.typeSync(absolute.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw FormatException('Root must be an existing ordinary directory');
  }
  return Directory(absolute.resolveSymbolicLinksSync());
}

File _safeInput(Directory root, String relativePath) {
  final file = File.fromUri(root.uri.resolve(relativePath));
  _assertInsideRoot(root, file.absolute.path, relativePath);
  _assertOrdinaryPath(root, file.absolute.path, requireTarget: true);
  return file;
}

File _safeOutput(Directory root, String path) {
  _validateRelativeOutputPath(path);
  final file = File(
    <String>[root.path, ...path.split('/')].join(Platform.pathSeparator),
  ).absolute;
  _assertInsideRoot(root, file.path, path);
  _assertOrdinaryPath(root, file.path, requireTarget: false);
  return file;
}

void _assertInsideRoot(Directory root, String targetPath, String label) {
  final rootPrefix = '${root.absolute.path}${Platform.pathSeparator}';
  if (!targetPath.startsWith(rootPrefix)) {
    throw FormatException('Path escapes repository root: $label');
  }
}

void _assertOrdinaryPath(
  Directory root,
  String targetPath, {
  required bool requireTarget,
}) {
  final relative = targetPath.substring(root.absolute.path.length + 1);
  var current = root.absolute.path;
  final segments = relative.split(Platform.pathSeparator);
  for (var index = 0; index < segments.length; index += 1) {
    current = '$current${Platform.pathSeparator}${segments[index]}';
    final isTarget = index == segments.length - 1;
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw FormatException('Symbolic links are not allowed: $current');
    }
    if (type == FileSystemEntityType.notFound) {
      if (!isTarget || requireTarget) {
        throw FormatException('Required path component is missing: $current');
      }
      continue;
    }
    if (isTarget) {
      if (type != FileSystemEntityType.file) {
        throw FormatException('Output must be an ordinary file: $current');
      }
    } else if (type != FileSystemEntityType.directory) {
      throw FormatException('Parent must be an ordinary directory: $current');
    }
  }
}

void _validateSchemaRegistration(Map<String, Object?> schema) {
  if (schema[r'$schema'] != 'https://json-schema.org/draft/2020-12/schema' ||
      schema[r'$id'] != 'urn:flutter-ai-harness:schema:bridge-wire:2' ||
      schema['additionalProperties'] != false) {
    throw const FormatException('Unsupported Wire Schema identity');
  }
  final properties = _object(schema['properties'], 'schema.properties');
  final definitions = _object(schema[r'$defs'], r'schema.$defs');
  if (_object(properties['codeGeneration'], 'schema.codeGeneration')[r'$ref'] !=
          r'#/$defs/codeGeneration' ||
      definitions['codeGeneration'] is! Map<String, Object?> ||
      definitions['generatedContractReferences'] is! Map<String, Object?> ||
      definitions['manualContractReference'] is! Map<String, Object?>) {
    throw const FormatException(
      'Wire Schema does not register the closed codeGeneration profile',
    );
  }
}

void validateWireContractAgainstSchema(
  Map<String, Object?> contract,
  Map<String, Object?> schema,
) {
  final diagnostics = <String>[];
  _validateJsonSchemaValue(contract, schema, schema, r'$contract', diagnostics);
  if (diagnostics.isNotEmpty) {
    throw FormatException(
      'Wire Contract does not satisfy Wire Schema: ${diagnostics.first}',
    );
  }
}

void _validateJsonSchemaValue(
  Object? value,
  Map<String, Object?> schema,
  Map<String, Object?> rootSchema,
  String path,
  List<String> diagnostics,
) {
  final reference = schema[r'$ref'];
  if (reference != null) {
    if (reference is! String || !reference.startsWith(r'#/$defs/')) {
      diagnostics.add('$path uses an unsupported schema reference');
      return;
    }
    final name = reference.substring(r'#/$defs/'.length);
    final definitions = rootSchema[r'$defs'];
    final target = definitions is Map<String, Object?>
        ? definitions[name]
        : null;
    if (target is! Map<String, Object?>) {
      diagnostics.add('$path references an unknown schema definition: $name');
      return;
    }
    _validateJsonSchemaValue(value, target, rootSchema, path, diagnostics);
    return;
  }

  final alternatives = schema['oneOf'];
  if (alternatives != null) {
    if (alternatives is! List<Object?> ||
        alternatives.any((entry) => entry is! Map<String, Object?>)) {
      diagnostics.add('$path has an invalid oneOf schema');
      return;
    }
    var matches = 0;
    for (final alternative in alternatives.cast<Map<String, Object?>>()) {
      final branchDiagnostics = <String>[];
      _validateJsonSchemaValue(
        value,
        alternative,
        rootSchema,
        path,
        branchDiagnostics,
      );
      if (branchDiagnostics.isEmpty) {
        matches += 1;
      }
    }
    if (matches != 1) {
      diagnostics.add('$path must satisfy exactly one schema alternative');
    }
    return;
  }

  final declaredType = schema['type'];
  if (declaredType != null) {
    final types = declaredType is String
        ? <String>[declaredType]
        : declaredType is List<Object?> &&
              declaredType.every((entry) => entry is String)
        ? declaredType.cast<String>()
        : null;
    if (types == null || !types.any((type) => _matchesJsonType(value, type))) {
      diagnostics.add('$path has the wrong JSON type');
      return;
    }
  }

  if (schema.containsKey('const') &&
      !_jsonValuesEqual(value, schema['const'])) {
    diagnostics.add('$path does not match the required constant');
  }
  final enumValues = schema['enum'];
  if (enumValues != null &&
      (enumValues is! List<Object?> ||
          !enumValues.any((entry) => _jsonValuesEqual(value, entry)))) {
    diagnostics.add('$path is not in the closed enum');
  }

  if (value is Map<String, Object?>) {
    final required = schema['required'];
    if (required is List<Object?>) {
      for (final key in required) {
        if (key is! String || !value.containsKey(key)) {
          diagnostics.add('$path is missing required property: $key');
        }
      }
    }
    final propertySchemas = schema['properties'];
    final properties = propertySchemas is Map<String, Object?>
        ? propertySchemas
        : const <String, Object?>{};
    for (final entry in value.entries) {
      final propertySchema = properties[entry.key];
      if (propertySchema is Map<String, Object?>) {
        _validateJsonSchemaValue(
          entry.value,
          propertySchema,
          rootSchema,
          '$path.${entry.key}',
          diagnostics,
        );
      } else if (schema['additionalProperties'] == false) {
        diagnostics.add('$path has unknown property: ${entry.key}');
      } else if (schema['additionalProperties'] is Map<String, Object?>) {
        _validateJsonSchemaValue(
          entry.value,
          schema['additionalProperties']! as Map<String, Object?>,
          rootSchema,
          '$path.${entry.key}',
          diagnostics,
        );
      }
    }
  }

  if (value is List<Object?>) {
    final minimum = schema['minItems'];
    final maximum = schema['maxItems'];
    if (minimum is int && value.length < minimum) {
      diagnostics.add('$path has too few items');
    }
    if (maximum is int && value.length > maximum) {
      diagnostics.add('$path has too many items');
    }
    if (schema['uniqueItems'] == true) {
      final canonical = value.map((entry) => jsonEncode(_canonicalJson(entry)));
      if (canonical.toSet().length != value.length) {
        diagnostics.add('$path contains duplicate items');
      }
    }
    final itemSchema = schema['items'];
    if (itemSchema is Map<String, Object?>) {
      for (var index = 0; index < value.length; index += 1) {
        _validateJsonSchemaValue(
          value[index],
          itemSchema,
          rootSchema,
          '$path[$index]',
          diagnostics,
        );
      }
    }
  }

  if (value is String) {
    final minimum = schema['minLength'];
    final maximum = schema['maxLength'];
    final length = value.runes.length;
    if (minimum is int && length < minimum) {
      diagnostics.add('$path is shorter than minLength');
    }
    if (maximum is int && length > maximum) {
      diagnostics.add('$path is longer than maxLength');
    }
    final pattern = schema['pattern'];
    if (pattern is String && !RegExp(pattern).hasMatch(value)) {
      diagnostics.add('$path does not match its pattern');
    }
  }

  if (value is num && value is! bool) {
    final minimum = schema['minimum'];
    final maximum = schema['maximum'];
    if (minimum is num && value < minimum) {
      diagnostics.add('$path is below its minimum');
    }
    if (maximum is num && value > maximum) {
      diagnostics.add('$path is above its maximum');
    }
  }
}

bool _matchesJsonType(Object? value, String type) => switch (type) {
  'null' => value == null,
  'object' => value is Map<String, Object?>,
  'array' => value is List<Object?>,
  'string' => value is String,
  'integer' => value is int,
  'number' => value is num && value is! bool,
  'boolean' => value is bool,
  _ => false,
};

bool _jsonValuesEqual(Object? left, Object? right) =>
    jsonEncode(_canonicalJson(left)) == jsonEncode(_canonicalJson(right));

List<WireGenerationOutput> _parseOutputs(Object? value) {
  final values = _objects(value, 'codeGeneration.outputs');
  final outputs = <WireGenerationOutput>[];
  for (final entry in values) {
    _expectExactKeys(entry, const <String>{
      'runtime',
      'language',
      'path',
      'identifierStyle',
      'typeStyle',
    }, 'codeGeneration output');
    final runtime = WireRuntime.parse(_string(entry['runtime'], 'runtime'));
    final language = _string(entry['language'], 'language');
    final expectedLanguage = switch (runtime) {
      WireRuntime.dart => 'dart',
      WireRuntime.android => 'kotlin',
      WireRuntime.ios => 'swift',
    };
    if (language != expectedLanguage ||
        entry['identifierStyle'] != 'lower_camel_case' ||
        entry['typeStyle'] != 'upper_camel_case') {
      throw FormatException('Invalid name mapping for ${runtime.wireName}');
    }
    final path = _string(entry['path'], 'output.path');
    _validateRelativeOutputPath(path);
    if (path != _registeredOutputPaths[runtime]) {
      throw FormatException(
        'Output path is not registered by the generator for '
        '${runtime.wireName}: $path',
      );
    }
    outputs.add(
      WireGenerationOutput(runtime: runtime, language: language, path: path),
    );
  }
  if (outputs.map((output) => output.runtime).toSet().length !=
          WireRuntime.values.length ||
      outputs.length != WireRuntime.values.length ||
      outputs.map((output) => output.path).toSet().length != outputs.length) {
    throw const FormatException(
      'codeGeneration.outputs must register dart, android, and ios once',
    );
  }
  outputs.sort(
    (left, right) => left.runtime.index.compareTo(right.runtime.index),
  );
  return outputs;
}

void _validateRelativeOutputPath(String path) {
  if (!RegExp(r'^app/[A-Za-z0-9_./-]+$').hasMatch(path)) {
    throw FormatException('Invalid registered output path: $path');
  }
  final segments = path.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw FormatException('Invalid registered output path: $path');
  }
}

WireFieldDescriptor _parseField(Map<String, Object?> entry) {
  const allowedTypes = <String>{
    'bool',
    'bytes',
    'double',
    'int',
    'string',
    'list_bool',
    'list_double',
    'list_int',
    'list_string',
  };
  _expectExactKeys(entry, const <String>{
    'capabilityFieldId',
    'key',
    'wireType',
    'required',
    'nullable',
    'enumValues',
    'validation',
  }, 'field mapping');
  final id = _string(entry['capabilityFieldId'], 'field.capabilityFieldId');
  _validateStableId(id, 'field.capabilityFieldId');
  final key = _string(entry['key'], 'field.key');
  if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(key)) {
    throw FormatException('Field key cannot be generated: $key');
  }
  final wireType = _string(entry['wireType'], 'field.wireType');
  if (!allowedTypes.contains(wireType)) {
    throw FormatException('Wire type cannot be generated: $wireType');
  }
  final enumValues = _strings(entry['enumValues'], 'field.enumValues');
  _rejectDuplicates(enumValues, 'field enumValues');
  for (final enumValue in enumValues) {
    _validateStableId(enumValue, 'field enum value');
  }
  final validation = _parseFieldValidation(
    _object(entry['validation'], 'field.validation'),
    wireType,
  );
  return WireFieldDescriptor(
    id: id,
    key: key,
    wireType: wireType,
    required: _boolean(entry['required'], 'field.required'),
    nullable: _boolean(entry['nullable'], 'field.nullable'),
    enumValues: List<String>.unmodifiable(enumValues),
    validation: Map<String, Object?>.unmodifiable(validation),
  );
}

Map<String, Object?> _parseError(Map<String, Object?> entry) {
  _expectExactKeys(entry, const <String>{
    'code',
    'source',
    'capabilityFailureId',
    'recoverable',
    'terminal',
    'messagePolicy',
    'detailsAllowedKeys',
  }, 'error');
  final code = _string(entry['code'], 'error.code');
  _validateStableId(code, 'error.code');
  final source = _string(entry['source'], 'error.source');
  if (source != 'capability_failure' && source != 'wire_protocol') {
    throw FormatException('Unsupported error source: $source');
  }
  final capabilityFailureId = _nullableStableId(
    entry['capabilityFailureId'],
    'error.capabilityFailureId',
  );
  final messagePolicy = _string(entry['messagePolicy'], 'error.messagePolicy');
  if (messagePolicy != 'static_redacted') {
    throw FormatException('Unsupported error message policy: $messagePolicy');
  }
  final details = _strings(
    entry['detailsAllowedKeys'],
    'error.detailsAllowedKeys',
  );
  _rejectDuplicates(details, 'error.detailsAllowedKeys');
  for (final detail in details) {
    if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(detail)) {
      throw FormatException('Unsafe error detail key: $detail');
    }
  }
  return <String, Object?>{
    'code': code,
    'source': source,
    'capabilityFailureId': capabilityFailureId,
    'recoverable': _boolean(entry['recoverable'], 'error.recoverable'),
    'terminal': _boolean(entry['terminal'], 'error.terminal'),
    'messagePolicy': messagePolicy,
    'detailsAllowedKeys': List<String>.unmodifiable(details),
  };
}

Map<String, Object?> _parseErrorDetail(Map<String, Object?> entry) {
  _expectExactKeys(entry, const <String>{
    'key',
    'wireType',
    'source',
    'enumValues',
    'minLength',
    'maxLength',
    'minimum',
    'maximum',
    'redaction',
  }, 'error detail');
  final key = _string(entry['key'], 'error detail key');
  if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(key)) {
    throw FormatException('Unsafe error detail key: $key');
  }
  final wireType = _string(entry['wireType'], 'error detail wireType');
  if (wireType != 'string' && wireType != 'int') {
    throw FormatException('Unsupported error detail wire type: $wireType');
  }
  final source = _string(entry['source'], 'error detail source');
  _validateStableId(source, 'error detail source');
  final enumValues = _strings(entry['enumValues'], 'error detail enumValues');
  _rejectDuplicates(enumValues, 'error detail enumValues');
  for (final enumValue in enumValues) {
    if (!RegExp(r'^[a-z][a-zA-Z0-9_]*$').hasMatch(enumValue)) {
      throw FormatException('Unsafe error detail enum value: $enumValue');
    }
  }
  final minLength = _nullableNonNegativeInt(
    entry['minLength'],
    'error detail minLength',
  );
  final maxLength = _nullableNonNegativeInt(
    entry['maxLength'],
    'error detail maxLength',
  );
  final minimum = _nullableInt(entry['minimum'], 'error detail minimum');
  final maximum = _nullableInt(entry['maximum'], 'error detail maximum');
  _validateOrderedBounds(minLength, maxLength, 'error detail length');
  _validateOrderedBounds(minimum, maximum, 'error detail numeric');
  if (wireType == 'string' && (minimum != null || maximum != null) ||
      wireType == 'int' && (minLength != null || maxLength != null)) {
    throw FormatException('Error detail bounds do not match $wireType: $key');
  }
  if (entry['redaction'] != 'allowlisted_value_only') {
    throw FormatException('Unsupported error detail redaction: $key');
  }
  return <String, Object?>{
    'key': key,
    'wireType': wireType,
    'source': source,
    'enumValues': List<String>.unmodifiable(enumValues),
    'minLength': minLength,
    'maxLength': maxLength,
    'minimum': minimum,
    'maximum': maximum,
    'redaction': 'allowlisted_value_only',
  };
}

Map<String, Object?> _parseFieldValidation(
  Map<String, Object?> entry,
  String wireType,
) {
  _expectExactKeys(entry, const <String>{
    'finite',
    'minimum',
    'maximum',
    'allowedIntegers',
    'minItems',
    'maxItems',
    'format',
    'boundarySource',
    'outOfRangePolicy',
    'conditionalRules',
  }, 'field.validation');
  final minimum = _nullableFiniteNum(entry['minimum'], 'field.minimum');
  final maximum = _nullableFiniteNum(entry['maximum'], 'field.maximum');
  if (wireType == 'int' &&
      (minimum != null && minimum is! int ||
          maximum != null && maximum is! int)) {
    throw const FormatException('Integer field bounds must be integers');
  }
  if (wireType != 'int' &&
      wireType != 'double' &&
      (minimum != null || maximum != null)) {
    throw FormatException('$wireType fields cannot declare numeric bounds');
  }
  _validateOrderedBounds(minimum, maximum, 'field numeric');
  final allowedIntegers = _integers(
    entry['allowedIntegers'],
    'field.allowedIntegers',
  );
  _rejectIntegerDuplicates(allowedIntegers, 'field.allowedIntegers');
  if (wireType != 'int' && allowedIntegers.isNotEmpty) {
    throw FormatException('$wireType fields cannot declare allowed integers');
  }
  for (final value in allowedIntegers) {
    _validateSigned64(value, 'field.allowedIntegers');
  }
  final minItems = _nullableNonNegativeInt(entry['minItems'], 'field.minItems');
  final maxItems = _nullableNonNegativeInt(entry['maxItems'], 'field.maxItems');
  final isSizedCollection = wireType == 'bytes' || wireType.startsWith('list_');
  if (!isSizedCollection && (minItems != null || maxItems != null)) {
    throw FormatException('$wireType fields cannot declare item bounds');
  }
  _validateOrderedBounds(minItems, maxItems, 'field item');
  final format = _string(entry['format'], 'field.format');
  _validateStableId(format, 'field.format');
  final boundarySource = _nullableStableId(
    entry['boundarySource'],
    'field.boundarySource',
  );
  final outOfRangePolicy = _string(
    entry['outOfRangePolicy'],
    'field.outOfRangePolicy',
  );
  if (!const <String>{
    'reject',
    'clamp',
    'not_applicable',
  }.contains(outOfRangePolicy)) {
    throw FormatException('Unsupported out-of-range policy: $outOfRangePolicy');
  }
  final rules = _objects(entry['conditionalRules'], 'field.conditionalRules');
  for (final rule in rules) {
    _validateConditionalRule(rule);
  }
  return <String, Object?>{
    'finite': _boolean(entry['finite'], 'field.finite'),
    'minimum': minimum,
    'maximum': maximum,
    'allowedIntegers': List<int>.unmodifiable(allowedIntegers),
    'minItems': minItems,
    'maxItems': maxItems,
    'format': format,
    'boundarySource': boundarySource,
    'outOfRangePolicy': outOfRangePolicy,
    'conditionalRules': List<Map<String, Object?>>.unmodifiable(rules),
  };
}

void _validateConditionalRule(Map<String, Object?> rule) {
  _expectExactKeys(rule, const <String>{
    'whenFieldId',
    'operator',
    'value',
    'effect',
  }, 'field conditional rule');
  _validateStableId(
    _string(rule['whenFieldId'], 'conditional.whenFieldId'),
    'conditional.whenFieldId',
  );
  if (!const <String>{'equals', 'contains'}.contains(rule['operator'])) {
    throw const FormatException('Unsupported conditional operator');
  }
  final value = rule['value'];
  if (value != null && value is! String && value is! int && value is! bool) {
    throw const FormatException('Unsupported conditional value');
  }
  if (!const <String>{
    'required',
    'must_be_null',
    'must_be_non_null',
  }.contains(rule['effect'])) {
    throw const FormatException('Unsupported conditional effect');
  }
}

void _validateReferenceSet(
  Map<String, Object?> generated,
  String key,
  List<String> actual,
) {
  final references = _strings(generated[key], 'codeGeneration.generated.$key');
  _rejectDuplicates(references, 'codeGeneration.generated.$key');
  _rejectDuplicates(actual, 'Contract $key');
  final expectedSet = actual.toSet();
  final referenceSet = references.toSet();
  final missing = expectedSet.difference(referenceSet);
  final unknown = referenceSet.difference(expectedSet);
  if (missing.isNotEmpty || unknown.isNotEmpty) {
    throw FormatException(
      'codeGeneration.generated.$key does not match Contract IDs; '
      'missing=${missing.toList()..sort()}, unknown=${unknown.toList()..sort()}',
    );
  }
}

List<String> _validatedPointerSet(
  Map<String, Object?> contract,
  Map<String, Object?> generated,
  String key,
  Set<String> expected,
) {
  final pointers = _strings(generated[key], 'codeGeneration.generated.$key');
  _rejectDuplicates(pointers, 'codeGeneration.generated.$key');
  if (pointers.toSet().difference(expected).isNotEmpty ||
      expected.difference(pointers.toSet()).isNotEmpty) {
    throw FormatException('codeGeneration.generated.$key is incomplete');
  }
  for (final pointer in pointers) {
    _readJsonPointer(contract, pointer);
  }
  pointers.sort();
  return pointers;
}

Object _normalizeGeneratedEnvelope(String pointer, Object? value) {
  final entry = _object(value, pointer);
  if (pointer.endsWith('Envelope')) {
    _expectExactKeys(entry, const <String>{
      'requiredKeys',
      'unknownFieldPolicy',
    }, pointer);
    final requiredKeys = _strings(
      entry['requiredKeys'],
      '$pointer.requiredKeys',
    );
    _rejectDuplicates(requiredKeys, '$pointer.requiredKeys');
    for (final key in requiredKeys) {
      if (!RegExp(r'^[a-z][a-zA-Z0-9]*$').hasMatch(key)) {
        throw FormatException('Unsafe envelope key: $key');
      }
    }
    if (entry['unknownFieldPolicy'] != 'reject') {
      throw FormatException('$pointer must reject unknown fields');
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'requiredKeys': List<String>.unmodifiable(requiredKeys),
      'unknownFieldPolicy': 'reject',
    });
  }

  _expectExactKeys(entry, const <String>{
    'wireType',
    'minLength',
    'maxLength',
    'pattern',
    'format',
    'logging',
  }, pointer);
  if (entry['wireType'] != 'string' ||
      entry['format'] != 'ascii_token' ||
      entry['logging'] != 'redact') {
    throw const FormatException('Unsupported request ID policy');
  }
  final minimum = _positiveInt(entry['minLength'], 'requestId.minLength');
  final maximum = _positiveInt(entry['maxLength'], 'requestId.maxLength');
  _validateOrderedBounds(minimum, maximum, 'request ID length');
  _validateKotlinInt(maximum, 'requestId.maxLength');
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    'wireType': 'string',
    'minLength': minimum,
    'maxLength': maximum,
    'pattern': _string(entry['pattern'], 'requestId.pattern'),
    'format': 'ascii_token',
    'logging': 'redact',
  });
}

Object _normalizeGeneratedTransportConstraint(String pointer, Object? value) {
  if (pointer.endsWith('/signedInteger')) {
    final entry = _object(value, pointer);
    _expectExactKeys(entry, const <String>{
      'wireType',
      'bits',
      'minimum',
      'maximum',
      'inboundOutOfRange',
      'outboundOutOfRange',
    }, pointer);
    final minimum = _int(entry['minimum'], 'signedInteger.minimum');
    final maximum = _int(entry['maximum'], 'signedInteger.maximum');
    if (entry['wireType'] != 'int' ||
        entry['bits'] != 64 ||
        minimum != -9223372036854775808 ||
        maximum != 9223372036854775807 ||
        entry['inboundOutOfRange'] != 'invalid_wire_payload' ||
        entry['outboundOutOfRange'] != 'wire_encoding_failed') {
      throw const FormatException(
        'Generated signed integer boundary must remain exact signed-64',
      );
    }
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      'wireType': 'int',
      'bits': 64,
      'minimum': minimum,
      'maximum': maximum,
      'inboundOutOfRange': 'invalid_wire_payload',
      'outboundOutOfRange': 'wire_encoding_failed',
    });
  }

  final handles = _objects(value, pointer);
  final normalized = <Map<String, Object?>>[];
  final ids = <String>{};
  for (final handle in handles) {
    _expectExactKeys(handle, const <String>{
      'capabilityFieldId',
      'capabilityHandlePolicyId',
      'wireType',
      'minLength',
      'maxLength',
      'format',
      'inboundOutOfRange',
      'outboundOutOfRange',
    }, 'opaque handle');
    final id = _string(handle['capabilityFieldId'], 'opaqueHandle.fieldId');
    _validateStableId(id, 'opaqueHandle.fieldId');
    if (!ids.add(id)) {
      throw FormatException('Duplicate opaque handle field: $id');
    }
    final policyId = _string(
      handle['capabilityHandlePolicyId'],
      'opaqueHandle.policyId',
    );
    _validateStableId(policyId, 'opaqueHandle.policyId');
    final minimum = _positiveInt(handle['minLength'], 'opaqueHandle.minLength');
    final maximum = _positiveInt(handle['maxLength'], 'opaqueHandle.maxLength');
    _validateOrderedBounds(minimum, maximum, 'opaque handle length');
    _validateKotlinInt(maximum, 'opaqueHandle.maxLength');
    if (handle['wireType'] != 'string' ||
        handle['format'] != 'opaque_string' ||
        handle['inboundOutOfRange'] != 'invalid_wire_payload' ||
        handle['outboundOutOfRange'] != 'wire_encoding_failed') {
      throw FormatException('Unsupported opaque handle boundary: $id');
    }
    normalized.add(
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'capabilityFieldId': id,
        'capabilityHandlePolicyId': policyId,
        'wireType': 'string',
        'minLength': minimum,
        'maxLength': maximum,
        'format': 'opaque_string',
        'inboundOutOfRange': 'invalid_wire_payload',
        'outboundOutOfRange': 'wire_encoding_failed',
      }),
    );
  }
  normalized.sort(
    (left, right) => _string(
      left['capabilityFieldId'],
      'opaqueHandle.fieldId',
    ).compareTo(_string(right['capabilityFieldId'], 'opaqueHandle.fieldId')),
  );
  return List<Map<String, Object?>>.unmodifiable(normalized);
}

void _validateManualOnly(Map<String, Object?> contract, Object? value) {
  final entries = _objects(value, 'codeGeneration.manualOnly');
  const expectedPointers = <String, Set<String>>{
    'capability_model_mapping': <String>{'/capability', '/coverage'},
    'method_dispatch': <String>{'/methods', '/failureDelivery'},
    'async_completion_and_lifecycle': <String>{
      '/lifecycle/linearizationPolicy',
      '/lifecycle/resultCompletionPolicies',
      '/lifecycle/lateResultPolicies',
    },
    'listener_and_owner_generation': <String>{
      '/lifecycle/listenerPolicy',
      '/lifecycle/boundaries',
    },
    'platform_thread_dispatch': <String>{
      '/lifecycle/callbackThread',
      '/platform',
    },
    'resource_and_transfer_ownership': <String>{
      '/lifecycle/resourceAdoptionPolicies',
      '/transferStore',
    },
    'file_uri_and_native_sdk_behavior': <String>{
      '/transferStore/fileUriPolicy',
      '/coverage/nativeArtifacts',
    },
    'cross_field_validation': <String>{'/fieldMappings'},
    'logging_and_redaction': <String>{'/security', '/transferStore/redaction'},
  };
  final ids = <String>{};
  for (final entry in entries) {
    _expectExactKeys(entry, const <String>{
      'id',
      'contractPointers',
      'reason',
    }, 'codeGeneration.manualOnly entry');
    final id = _id(entry, 'manualOnly');
    if (!ids.add(id)) {
      throw FormatException('Duplicate manual-only ID: $id');
    }
    final reason = _string(entry['reason'], 'manualOnly.reason');
    if (reason.trim().isEmpty) {
      throw FormatException('manualOnly.reason must not be empty: $id');
    }
    final pointers = _strings(entry['contractPointers'], 'contractPointers');
    _rejectDuplicates(pointers, 'manualOnly.contractPointers');
    final requiredPointers = expectedPointers[id];
    if (requiredPointers == null ||
        pointers.toSet().length != requiredPointers.length ||
        !pointers.toSet().containsAll(requiredPointers)) {
      throw FormatException(
        'manualOnly.contractPointers do not match the approved boundary: $id',
      );
    }
    for (final pointer in pointers) {
      _readJsonPointer(contract, pointer);
    }
  }
  if (ids.difference(expectedPointers.keys.toSet()).isNotEmpty ||
      expectedPointers.keys.toSet().difference(ids).isNotEmpty) {
    throw const FormatException('codeGeneration.manualOnly is incomplete');
  }
}

Object? _readJsonPointer(Map<String, Object?> root, String pointer) {
  if (!pointer.startsWith('/') || pointer.contains('~')) {
    throw FormatException('Unsupported Contract JSON pointer: $pointer');
  }
  Object? current = root;
  for (final segment in pointer.substring(1).split('/')) {
    if (current is! Map<String, Object?> || !current.containsKey(segment)) {
      throw FormatException('Unknown Contract JSON pointer: $pointer');
    }
    current = current[segment];
  }
  return current;
}

void _validateRuntimeNames(
  List<WireGenerationOutput> outputs,
  Map<String, List<String>> categories,
) {
  for (final output in outputs) {
    for (final entry in categories.entries) {
      final names = <String, String>{};
      for (final wireValue in entry.value) {
        final name = _runtimeIdentifier(wireValue);
        final prior = names[name];
        if (prior != null) {
          throw FormatException(
            '${output.runtime.wireName} ${entry.key} name collision: '
            '$prior and $wireValue both map to $name',
          );
        }
        if (_reservedWords(output.runtime).contains(name)) {
          throw FormatException(
            '${output.runtime.wireName} reserved ${entry.key} name: $name',
          );
        }
        names[name] = wireValue;
      }
    }
  }
}

String _runtimeIdentifier(String wireValue) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(wireValue)) {
    throw FormatException('Wire value cannot map to an identifier: $wireValue');
  }
  final parts = wireValue.split('_');
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    if (part.isEmpty) {
      continue;
    }
    buffer
      ..write(part[0].toUpperCase())
      ..write(part.substring(1));
  }
  final result = buffer.toString();
  if (result.isEmpty || RegExp(r'^[0-9]').hasMatch(result)) {
    throw FormatException('Wire value cannot map to an identifier: $wireValue');
  }
  return result;
}

Set<String> _reservedWords(WireRuntime runtime) => switch (runtime) {
  WireRuntime.dart => const <String>{
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'get',
    'hide',
    'if',
    'in',
    'implements',
    'import',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  },
  WireRuntime.android => const <String>{
    'abstract',
    'actual',
    'annotation',
    'as',
    'break',
    'by',
    'catch',
    'class',
    'companion',
    'const',
    'constructor',
    'continue',
    'crossinline',
    'data',
    'delegate',
    'do',
    'dynamic',
    'else',
    'enum',
    'expect',
    'external',
    'false',
    'field',
    'file',
    'final',
    'finally',
    'for',
    'fun',
    'get',
    'if',
    'import',
    'in',
    'infix',
    'init',
    'inline',
    'inner',
    'interface',
    'internal',
    'is',
    'it',
    'lateinit',
    'noinline',
    'null',
    'object',
    'open',
    'operator',
    'out',
    'override',
    'package',
    'param',
    'private',
    'property',
    'protected',
    'public',
    'receiver',
    'reified',
    'return',
    'sealed',
    'set',
    'setparam',
    'super',
    'suspend',
    'tailrec',
    'this',
    'throw',
    'true',
    'try',
    'typealias',
    'typeof',
    'val',
    'var',
    'vararg',
    'when',
    'where',
    'while',
  },
  WireRuntime.ios => const <String>{
    'as',
    'associatedtype',
    'associativity',
    'break',
    'case',
    'catch',
    'class',
    'convenience',
    'continue',
    'default',
    'defer',
    'deinit',
    'didSet',
    'do',
    'dynamic',
    'else',
    'enum',
    'extension',
    'fallthrough',
    'false',
    'final',
    'fileprivate',
    'for',
    'func',
    'get',
    'guard',
    'if',
    'import',
    'in',
    'indirect',
    'init',
    'inout',
    'infix',
    'internal',
    'is',
    'lazy',
    'left',
    'let',
    'mutating',
    'nil',
    'none',
    'nonmutating',
    'open',
    'operator',
    'optional',
    'override',
    'postfix',
    'precedence',
    'prefix',
    'private',
    'protocol',
    'public',
    'repeat',
    'required',
    'return',
    'rethrows',
    'right',
    'self',
    'set',
    'static',
    'struct',
    'subscript',
    'super',
    'switch',
    'throw',
    'throws',
    'true',
    'try',
    'typealias',
    'unowned',
    'var',
    'weak',
    'where',
    'while',
    'willSet',
  },
};

String _render(WireRuntime runtime, MediaCaptureWireGenerationModel model) =>
    switch (runtime) {
      WireRuntime.dart => _renderDart(model),
      WireRuntime.android => _renderKotlin(model),
      WireRuntime.ios => _renderSwift(model),
    };

String _singleTerminalNewline(String source) {
  var end = source.length;
  while (end > 0 && source.codeUnitAt(end - 1) == 0x0A) {
    end -= 1;
  }
  return '${source.substring(0, end)}\n';
}

String _header(String comment, MediaCaptureWireGenerationModel model) =>
    '$comment GENERATED CODE - DO NOT MODIFY BY HAND.\n'
    '$comment Generator: media_capture_wire/${model.generatorVersion}\n'
    '$comment Source: $mediaCaptureWireContractPath\n'
    '$comment Source digest (SHA-256): ${model.sourceDigest}\n';

String _renderDart(MediaCaptureWireGenerationModel model) {
  final output = StringBuffer()
    ..write(_header('//', model))
    ..writeln("part of 'media_capture_wire_codec.dart';")
    ..writeln()
    ..writeln(
      'const int _generatedMediaCaptureWireVersion = '
      '${model.wireVersion};',
    );
  for (final channel in model.channels) {
    output.writeln(
      "const String _generated${_upperCamel(_id(channel, 'channel'))}Channel = "
      "'${_escapeDart(_string(channel['name'], 'channel.name'))}';",
    );
  }
  output
    ..writeln()
    ..write(
      _renderDartEnum('_GeneratedMediaCaptureWireMethod', model.methodIds),
    )
    ..write(_renderDartEnum('_GeneratedMediaCaptureWireEvent', model.eventIds))
    ..write(
      _renderDartEnum('_GeneratedMediaCaptureWireResult', model.resultTypeIds),
    )
    ..write(
      _renderDartEnum(
        '_GeneratedMediaCaptureWireFailure',
        model.failureTypeIds,
      ),
    )
    ..write(
      _renderDartEnum('_GeneratedMediaCaptureWireError', model.errorCodes),
    )
    ..writeln('final class _GeneratedWireFieldDescriptor {')
    ..writeln('  const _GeneratedWireFieldDescriptor({')
    ..writeln('    required this.id, required this.key, required this.type,')
    ..writeln('    required this.required, required this.nullable,')
    ..writeln('    required this.enumValues, required this.minimum,')
    ..writeln('    required this.maximum, required this.allowedIntegers,')
    ..writeln('    required this.minItems, required this.maxItems,')
    ..writeln('    required this.finite, required this.format,')
    ..writeln('    required this.boundarySource,')
    ..writeln('    required this.outOfRangePolicy,')
    ..writeln('  });')
    ..writeln('  final String id;')
    ..writeln('  final String key;')
    ..writeln('  final String type;')
    ..writeln('  final bool required;')
    ..writeln('  final bool nullable;')
    ..writeln('  final List<String> enumValues;')
    ..writeln('  final num? minimum;')
    ..writeln('  final num? maximum;')
    ..writeln('  final List<int> allowedIntegers;')
    ..writeln('  final int? minItems;')
    ..writeln('  final int? maxItems;')
    ..writeln('  final bool finite;')
    ..writeln('  final String format;')
    ..writeln('  final String? boundarySource;')
    ..writeln('  final String outOfRangePolicy;')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'const List<_GeneratedWireFieldDescriptor> '
      '_generatedMediaCaptureWireFields = <_GeneratedWireFieldDescriptor>[',
    );
  for (final field in model.fields) {
    final validation = field.validation;
    output
      ..writeln('  _GeneratedWireFieldDescriptor(')
      ..writeln("    id: '${_escapeDart(field.id)}',")
      ..writeln("    key: '${_escapeDart(field.key)}',")
      ..writeln("    type: '${_escapeDart(field.wireType)}',")
      ..writeln('    required: ${field.required}, nullable: ${field.nullable},')
      ..writeln('    enumValues: ${_dartStringList(field.enumValues)},')
      ..writeln('    minimum: ${_dartLiteral(validation['minimum'])},')
      ..writeln('    maximum: ${_dartLiteral(validation['maximum'])},')
      ..writeln(
        '    allowedIntegers: '
        '${_dartIntList(validation['allowedIntegers'])},',
      )
      ..writeln('    minItems: ${_dartLiteral(validation['minItems'])},')
      ..writeln('    maxItems: ${_dartLiteral(validation['maxItems'])},')
      ..writeln('    finite: ${validation['finite']},')
      ..writeln(
        "    format: '${_escapeDart(_string(validation['format'], 'format'))}',",
      )
      ..writeln(
        '    boundarySource: ${_dartLiteral(validation['boundarySource'])},',
      )
      ..writeln(
        "    outOfRangePolicy: '${_escapeDart(_string(validation['outOfRangePolicy'], 'outOfRangePolicy'))}',",
      )
      ..writeln('  ),');
  }
  output
    ..writeln('];')
    ..writeln()
    ..writeln(
      'const Map<String, List<String>> _generatedPayloadFieldIds = '
      '<String, List<String>>{',
    );
  for (final payload in model.payloads) {
    output.writeln(
      "  '${_escapeDart(payload.id)}': ${_dartStringList(payload.fieldIds)},",
    );
  }
  output
    ..writeln('};')
    ..writeln();
  _renderDartProtocolDescriptors(output, model);
  output
    ..writeln('bool _generatedHasExactWireKeys(')
    ..writeln('  Map<Object?, Object?> value, List<String> requiredKeys,')
    ..writeln(') => value.length == requiredKeys.length &&')
    ..writeln('    value.keys.every(requiredKeys.contains);')
    ..writeln()
    ..writeln('bool _generatedMatchesWireFieldPrimitive(')
    ..writeln('  Object? value, _GeneratedWireFieldDescriptor field,')
    ..writeln(') {')
    ..writeln('  if (value == null) return field.nullable;')
    ..writeln('  final validType = switch (field.type) {')
    ..writeln("    'bool' => value is bool,")
    ..writeln("    'bytes' => value is Uint8List,")
    ..writeln("    'double' => value is double,")
    ..writeln("    'int' => value is int,")
    ..writeln("    'string' => value is String,")
    ..writeln(
      "    'list_bool' => value is List && value.every((item) => item is bool),",
    )
    ..writeln(
      "    'list_double' => value is List && value.every((item) => item is double),",
    )
    ..writeln(
      "    'list_int' => value is List && value.every((item) => item is int),",
    )
    ..writeln(
      "    'list_string' => value is List && value.every((item) => item is String),",
    )
    ..writeln('    _ => false,')
    ..writeln('  };')
    ..writeln('  if (!validType) return false;')
    ..writeln(
      '  if (value is double && field.finite && !value.isFinite) return false;',
    )
    ..writeln('  if (value is int &&')
    ..writeln('      (value < _generatedSignedIntegerMinimum ||')
    ..writeln('       value > _generatedSignedIntegerMaximum)) return false;')
    ..writeln(
      '  if (value is num && field.minimum != null && value < field.minimum!) return false;',
    )
    ..writeln(
      '  if (value is num && field.maximum != null && value > field.maximum!) return false;',
    )
    ..writeln('  if (value is int && field.allowedIntegers.isNotEmpty &&')
    ..writeln('      !field.allowedIntegers.contains(value)) return false;')
    ..writeln('  final collectionLength = switch (value) {')
    ..writeln('    Uint8List() => value.length,')
    ..writeln('    List() => value.length,')
    ..writeln('    _ => null,')
    ..writeln('  };')
    ..writeln(
      '  if (collectionLength != null && field.minItems != null && collectionLength < field.minItems!) return false;',
    )
    ..writeln(
      '  if (collectionLength != null && field.maxItems != null && collectionLength > field.maxItems!) return false;',
    )
    ..writeln('  if (value is String && field.enumValues.isNotEmpty &&')
    ..writeln('      !field.enumValues.contains(value)) return false;')
    ..writeln('  if (value is List && field.type == \'list_string\' &&')
    ..writeln('      field.enumValues.isNotEmpty &&')
    ..writeln('      !value.every(field.enumValues.contains)) return false;')
    ..writeln('  if (value is List && field.type == \'list_string\' &&')
    ..writeln('      field.enumValues.isNotEmpty &&')
    ..writeln('      value.toSet().length != value.length) return false;')
    ..writeln('  if (value is List && field.type == \'list_double\' &&')
    ..writeln('      field.finite &&')
    ..writeln(
      '      value.any((item) => !(item as double).isFinite)) return false;',
    )
    ..writeln('  if (value is List && field.type == \'list_int\' &&')
    ..writeln(
      '      value.any((item) => item < _generatedSignedIntegerMinimum ||',
    )
    ..writeln('          item > _generatedSignedIntegerMaximum)) return false;')
    ..writeln('  return true;')
    ..writeln('}')
    ..writeln();
  return output.toString();
}

String _renderDartEnum(String type, List<String> values) {
  final constantPrefix = type.replaceFirst('_Generated', '_generated');
  final output = StringBuffer();
  for (final value in values) {
    output.writeln(
      "const String $constantPrefix${_upperCamel(value)} = "
      "'${_escapeDart(value)}';",
    );
  }
  output
    ..writeln()
    ..writeln('enum $type {');
  for (var index = 0; index < values.length; index += 1) {
    final value = values[index];
    final separator = index == values.length - 1 ? ';' : ',';
    output.writeln(
      '  ${_runtimeIdentifier(value)}('
      '$constantPrefix${_upperCamel(value)})$separator',
    );
  }
  output
    ..writeln('  const $type(this.wireValue);')
    ..writeln('  final String wireValue;')
    ..writeln('}')
    ..writeln();
  return output.toString();
}

void _renderDartProtocolDescriptors(
  StringBuffer output,
  MediaCaptureWireGenerationModel model,
) {
  output
    ..writeln('final class _GeneratedWirePayloadDescriptor {')
    ..writeln('  const _GeneratedWirePayloadDescriptor(')
    ..writeln('    this.id, this.kind, this.fieldIds, this.unknownFieldPolicy,')
    ..writeln('  );')
    ..writeln('  final String id;')
    ..writeln('  final String kind;')
    ..writeln('  final List<String> fieldIds;')
    ..writeln('  final String unknownFieldPolicy;')
    ..writeln('}')
    ..writeln(
      'const List<_GeneratedWirePayloadDescriptor> '
      '_generatedPayloadDescriptors = <_GeneratedWirePayloadDescriptor>[',
    );
  for (final payload in model.payloads) {
    output.writeln(
      "  _GeneratedWirePayloadDescriptor('${_escapeDart(payload.id)}', "
      "'${_escapeDart(payload.kind)}', ${_dartStringList(payload.fieldIds)}, "
      "'${_escapeDart(payload.unknownFieldPolicy)}'),",
    );
  }
  output
    ..writeln('];')
    ..writeln()
    ..writeln('final class _GeneratedWireErrorDescriptor {')
    ..writeln('  const _GeneratedWireErrorDescriptor(')
    ..writeln('    this.code, this.source, this.capabilityFailureId,')
    ..writeln('    this.recoverable, this.terminal, this.messagePolicy,')
    ..writeln('    this.detailsAllowedKeys,')
    ..writeln('  );')
    ..writeln('  final String code;')
    ..writeln('  final String source;')
    ..writeln('  final String? capabilityFailureId;')
    ..writeln('  final bool recoverable;')
    ..writeln('  final bool terminal;')
    ..writeln('  final String messagePolicy;')
    ..writeln('  final List<String> detailsAllowedKeys;')
    ..writeln('}')
    ..writeln(
      'const List<_GeneratedWireErrorDescriptor> '
      '_generatedErrorDescriptors = <_GeneratedWireErrorDescriptor>[',
    );
  for (final error in model.errorDescriptors) {
    output.writeln(
      '  _GeneratedWireErrorDescriptor('
      "'${_escapeDart(_string(error['code'], 'error.code'))}', "
      "'${_escapeDart(_string(error['source'], 'error.source'))}', "
      '${_dartLiteral(error['capabilityFailureId'])}, '
      '${error['recoverable']}, ${error['terminal']}, '
      "'${_escapeDart(_string(error['messagePolicy'], 'messagePolicy'))}', "
      '${_dartStringList(_strings(error['detailsAllowedKeys'], 'details'))}),',
    );
  }
  output
    ..writeln('];')
    ..writeln()
    ..writeln('final class _GeneratedWireErrorDetailDescriptor {')
    ..writeln('  const _GeneratedWireErrorDetailDescriptor(')
    ..writeln('    this.key, this.type, this.source, this.enumValues,')
    ..writeln('    this.minLength, this.maxLength, this.minimum, this.maximum,')
    ..writeln('    this.redaction,')
    ..writeln('  );')
    ..writeln('  final String key;')
    ..writeln('  final String type;')
    ..writeln('  final String source;')
    ..writeln('  final List<String> enumValues;')
    ..writeln('  final int? minLength;')
    ..writeln('  final int? maxLength;')
    ..writeln('  final int? minimum;')
    ..writeln('  final int? maximum;')
    ..writeln('  final String redaction;')
    ..writeln('}')
    ..writeln(
      'const List<_GeneratedWireErrorDetailDescriptor> '
      '_generatedErrorDetailDescriptors = '
      '<_GeneratedWireErrorDetailDescriptor>[',
    );
  for (final detail in model.errorDetailDescriptors) {
    output.writeln(
      '  _GeneratedWireErrorDetailDescriptor('
      "'${_escapeDart(_string(detail['key'], 'detail.key'))}', "
      "'${_escapeDart(_string(detail['wireType'], 'detail.wireType'))}', "
      "'${_escapeDart(_string(detail['source'], 'detail.source'))}', "
      '${_dartStringList(_strings(detail['enumValues'], 'detail.enumValues'))}, '
      '${_dartLiteral(detail['minLength'])}, ${_dartLiteral(detail['maxLength'])}, '
      '${_dartLiteral(detail['minimum'])}, ${_dartLiteral(detail['maximum'])}, '
      "'${_escapeDart(_string(detail['redaction'], 'detail.redaction'))}'),",
    );
  }
  output
    ..writeln('];')
    ..writeln();
  final requestId = _object(
    model.envelopes['/lifecycle/requestIdPolicy'],
    'requestIdPolicy',
  );
  output
    ..writeln(
      "const String _generatedRequestIdWireType = "
      "'${_escapeDart(_string(requestId['wireType'], 'requestId.wireType'))}';",
    )
    ..writeln(
      "const String _generatedRequestIdPattern = "
      "'${_escapeDart(_string(requestId['pattern'], 'requestId.pattern'))}';",
    )
    ..writeln(
      "const String _generatedRequestIdFormat = "
      "'${_escapeDart(_string(requestId['format'], 'requestId.format'))}';",
    )
    ..writeln(
      'const int _generatedRequestIdMinLength = ${requestId['minLength']};',
    )
    ..writeln(
      'const int _generatedRequestIdMaxLength = ${requestId['maxLength']};',
    )
    ..writeln(
      'const Map<String, List<String>> _generatedEnvelopeRequiredKeys = '
      '<String, List<String>>{',
    );
  for (final entry in _envelopeDescriptors(model).entries) {
    output.writeln(
      "  '${_escapeDart(entry.key)}': ${_dartStringList(entry.value)},",
    );
  }
  output
    ..writeln('};')
    ..writeln(
      'const Map<String, String> _generatedEnvelopeUnknownFieldPolicies = '
      '<String, String>{',
    );
  for (final entry in _envelopeUnknownFieldPolicies(model).entries) {
    output.writeln(
      "  '${_escapeDart(entry.key)}': '${_escapeDart(entry.value)}',",
    );
  }
  final signed = _signedIntegerConstraint(model);
  output
    ..writeln('};')
    ..writeln(
      'const int _generatedSignedIntegerMinimum = ${signed['minimum']};',
    )
    ..writeln(
      'const int _generatedSignedIntegerMaximum = ${signed['maximum']};',
    )
    ..writeln(
      'const Map<String, List<int>> _generatedOpaqueHandleLengths = '
      '<String, List<int>>{',
    );
  for (final handle in _opaqueHandleConstraints(model)) {
    output.writeln(
      "  '${_escapeDart(_string(handle['capabilityFieldId'], 'handle.id'))}': "
      '<int>[${handle['minLength']}, ${handle['maxLength']}],',
    );
  }
  output
    ..writeln('};')
    ..writeln();
}

String _renderKotlin(MediaCaptureWireGenerationModel model) {
  final output = StringBuffer()
    ..write(_header('//', model))
    ..writeln('package com.example.media_capture')
    ..writeln()
    ..writeln(
      'internal const val generatedMediaCaptureWireVersion: Int = '
      '${model.wireVersion}',
    );
  for (final channel in model.channels) {
    output.writeln(
      'internal const val generated${_upperCamel(_id(channel, 'channel'))}Channel: String = '
      '"${_escapeQuoted(_string(channel['name'], 'channel.name'), escapeDollar: true)}"',
    );
  }
  output.writeln();
  _renderKotlinEnum(output, 'GeneratedMediaCaptureWireMethod', model.methodIds);
  _renderKotlinEnum(output, 'GeneratedMediaCaptureWireEvent', model.eventIds);
  _renderKotlinEnum(
    output,
    'GeneratedMediaCaptureWireResult',
    model.resultTypeIds,
  );
  _renderKotlinEnum(
    output,
    'GeneratedMediaCaptureWireFailure',
    model.failureTypeIds,
  );
  _renderKotlinEnum(output, 'GeneratedMediaCaptureWireError', model.errorCodes);
  output
    ..writeln('internal data class GeneratedWireFieldDescriptor(')
    ..writeln('    val id: String,')
    ..writeln('    val key: String,')
    ..writeln('    val type: String,')
    ..writeln('    val required: Boolean,')
    ..writeln('    val nullable: Boolean,')
    ..writeln('    val enumValues: Set<String>,')
    ..writeln('    val minimum: String?,')
    ..writeln('    val maximum: String?,')
    ..writeln('    val allowedIntegers: Set<Long>,')
    ..writeln('    val minItems: Int?,')
    ..writeln('    val maxItems: Int?,')
    ..writeln('    val finite: Boolean,')
    ..writeln('    val format: String,')
    ..writeln('    val boundarySource: String?,')
    ..writeln('    val outOfRangePolicy: String,')
    ..writeln(')')
    ..writeln()
    ..writeln(
      'internal val generatedMediaCaptureWireFields: '
      'List<GeneratedWireFieldDescriptor> = listOf(',
    );
  for (final field in model.fields) {
    final validation = field.validation;
    output
      ..writeln('    GeneratedWireFieldDescriptor(')
      ..writeln(
        '        id = "${_escapeQuoted(field.id, escapeDollar: true)}",',
      )
      ..writeln(
        '        key = "${_escapeQuoted(field.key, escapeDollar: true)}",',
      )
      ..writeln(
        '        type = "${_escapeQuoted(field.wireType, escapeDollar: true)}",',
      )
      ..writeln(
        '        required = ${field.required}, nullable = ${field.nullable},',
      )
      ..writeln('        enumValues = ${_kotlinStringSet(field.enumValues)},')
      ..writeln('        minimum = ${_quotedNumber(validation['minimum'])},')
      ..writeln('        maximum = ${_quotedNumber(validation['maximum'])},')
      ..writeln(
        '        allowedIntegers = ${_kotlinLongSet(validation['allowedIntegers'])},',
      )
      ..writeln(
        '        minItems = ${_kotlinNullableInt(validation['minItems'])},',
      )
      ..writeln(
        '        maxItems = ${_kotlinNullableInt(validation['maxItems'])},',
      )
      ..writeln('        finite = ${validation['finite']},')
      ..writeln(
        '        format = "${_escapeQuoted(_string(validation['format'], 'format'), escapeDollar: true)}",',
      )
      ..writeln(
        '        boundarySource = ${_kotlinNullableString(validation['boundarySource'])},',
      )
      ..writeln(
        '        outOfRangePolicy = "${_escapeQuoted(_string(validation['outOfRangePolicy'], 'outOfRangePolicy'), escapeDollar: true)}",',
      )
      ..writeln('    ),');
  }
  output
    ..writeln(')')
    ..writeln()
    ..writeln(
      'internal val generatedPayloadFieldIds: Map<String, Set<String>> = mapOf(',
    );
  for (final payload in model.payloads) {
    output.writeln(
      '    "${_escapeQuoted(payload.id, escapeDollar: true)}" to '
      '${_kotlinStringSet(payload.fieldIds)},',
    );
  }
  output
    ..writeln(')')
    ..writeln();
  _renderKotlinProtocolDescriptors(output, model);
  output
    ..writeln('internal fun generatedHasExactWireKeys(')
    ..writeln('    value: Map<*, *>, requiredKeys: Set<String>,')
    ..writeln(
      '): Boolean = value.size == requiredKeys.size && value.keys.all { it in requiredKeys }',
    )
    ..writeln()
    ..writeln('internal fun generatedMatchesWireFieldPrimitive(')
    ..writeln('    value: Any?, field: GeneratedWireFieldDescriptor,')
    ..writeln('): Boolean {')
    ..writeln('    if (value == null) return field.nullable')
    ..writeln('    val validType = when (field.type) {')
    ..writeln('        "bool" -> value is Boolean')
    ..writeln('        "bytes" -> value is ByteArray')
    ..writeln('        "double" -> value is Double')
    ..writeln('        "int" -> value is Int || value is Long')
    ..writeln('        "string" -> value is String')
    ..writeln(
      '        "list_bool" -> value is List<*> && value.all { it is Boolean }',
    )
    ..writeln(
      '        "list_double" -> value is List<*> && value.all { it is Double }',
    )
    ..writeln(
      '        "list_int" -> value is List<*> && value.all { it is Int || it is Long }',
    )
    ..writeln(
      '        "list_string" -> value is List<*> && value.all { it is String }',
    )
    ..writeln('        else -> false')
    ..writeln('    }')
    ..writeln('    if (!validType) return false')
    ..writeln(
      '    if (value is Double && field.finite && !value.isFinite()) return false',
    )
    ..writeln('    if (value is Double) {')
    ..writeln(
      '        if (field.minimum?.toDoubleOrNull()?.let { value < it } == true) return false',
    )
    ..writeln(
      '        if (field.maximum?.toDoubleOrNull()?.let { value > it } == true) return false',
    )
    ..writeln('    }')
    ..writeln('    val integer = when (value) {')
    ..writeln('        is Int -> value.toLong()')
    ..writeln('        is Long -> value')
    ..writeln('        else -> null')
    ..writeln('    }')
    ..writeln('    if (integer != null) {')
    ..writeln(
      '        if (field.minimum?.toLongOrNull()?.let { integer < it } == true) return false',
    )
    ..writeln(
      '        if (field.maximum?.toLongOrNull()?.let { integer > it } == true) return false',
    )
    ..writeln('    }')
    ..writeln(
      '    if (value is Long && field.allowedIntegers.isNotEmpty() && value !in field.allowedIntegers) return false',
    )
    ..writeln(
      '    if (value is Int && field.allowedIntegers.isNotEmpty() && value.toLong() !in field.allowedIntegers) return false',
    )
    ..writeln('    val collectionSize = when (value) {')
    ..writeln('        is ByteArray -> value.size')
    ..writeln('        is Collection<*> -> value.size')
    ..writeln('        else -> null')
    ..writeln('    }')
    ..writeln(
      '    if (collectionSize != null && field.minItems != null && collectionSize < field.minItems) return false',
    )
    ..writeln(
      '    if (collectionSize != null && field.maxItems != null && collectionSize > field.maxItems) return false',
    )
    ..writeln(
      '    if (value is String && field.enumValues.isNotEmpty() && value !in field.enumValues) return false',
    )
    ..writeln(
      '    if (value is List<*> && field.type == "list_string" && field.enumValues.isNotEmpty() && !value.all { it is String && it in field.enumValues }) return false',
    )
    ..writeln(
      '    if (value is List<*> && field.type == "list_string" && field.enumValues.isNotEmpty() && value.toSet().size != value.size) return false',
    )
    ..writeln(
      '    if (value is List<*> && field.type == "list_double" && field.finite && value.any { it is Double && !it.isFinite() }) return false',
    )
    ..writeln('    return true')
    ..writeln('}')
    ..writeln();
  return output.toString();
}

void _renderKotlinEnum(StringBuffer output, String type, List<String> values) {
  output.writeln('internal enum class $type(val wireValue: String) {');
  for (var index = 0; index < values.length; index += 1) {
    final value = values[index];
    final suffix = index == values.length - 1 ? ';' : ',';
    output.writeln(
      '    ${_runtimeIdentifier(value)}('
      '"${_escapeQuoted(value, escapeDollar: true)}")$suffix',
    );
  }
  output
    ..writeln('}')
    ..writeln();
}

void _renderKotlinProtocolDescriptors(
  StringBuffer output,
  MediaCaptureWireGenerationModel model,
) {
  output
    ..writeln('internal data class GeneratedWirePayloadDescriptor(')
    ..writeln('    val id: String, val kind: String,')
    ..writeln('    val fieldIds: Set<String>, val unknownFieldPolicy: String,')
    ..writeln(')')
    ..writeln('internal val generatedPayloadDescriptors = listOf(');
  for (final payload in model.payloads) {
    output.writeln(
      '    GeneratedWirePayloadDescriptor('
      '"${_escapeQuoted(payload.id, escapeDollar: true)}", '
      '"${_escapeQuoted(payload.kind, escapeDollar: true)}", '
      '${_kotlinStringSet(payload.fieldIds)}, '
      '"${_escapeQuoted(payload.unknownFieldPolicy, escapeDollar: true)}"),',
    );
  }
  output
    ..writeln(')')
    ..writeln('internal data class GeneratedWireErrorDescriptor(')
    ..writeln('    val code: String, val source: String,')
    ..writeln('    val capabilityFailureId: String?,')
    ..writeln('    val recoverable: Boolean, val terminal: Boolean,')
    ..writeln(
      '    val messagePolicy: String, val detailsAllowedKeys: Set<String>,',
    )
    ..writeln(')')
    ..writeln('internal val generatedErrorDescriptors = listOf(');
  for (final error in model.errorDescriptors) {
    output.writeln(
      '    GeneratedWireErrorDescriptor('
      '"${_escapeQuoted(_string(error['code'], 'error.code'), escapeDollar: true)}", '
      '"${_escapeQuoted(_string(error['source'], 'error.source'), escapeDollar: true)}", '
      '${_kotlinNullableString(error['capabilityFailureId'])}, '
      '${error['recoverable']}, ${error['terminal']}, '
      '"${_escapeQuoted(_string(error['messagePolicy'], 'messagePolicy'), escapeDollar: true)}", '
      '${_kotlinStringSet(_strings(error['detailsAllowedKeys'], 'details'))}),',
    );
  }
  output
    ..writeln(')')
    ..writeln('internal data class GeneratedWireErrorDetailDescriptor(')
    ..writeln('    val key: String, val type: String, val source: String,')
    ..writeln('    val enumValues: Set<String>,')
    ..writeln('    val minLength: Int?, val maxLength: Int?,')
    ..writeln('    val minimum: String?, val maximum: String?,')
    ..writeln('    val redaction: String,')
    ..writeln(')')
    ..writeln('internal val generatedErrorDetailDescriptors = listOf(');
  for (final detail in model.errorDetailDescriptors) {
    output.writeln(
      '    GeneratedWireErrorDetailDescriptor('
      '"${_escapeQuoted(_string(detail['key'], 'detail.key'), escapeDollar: true)}", '
      '"${_escapeQuoted(_string(detail['wireType'], 'detail.type'), escapeDollar: true)}", '
      '"${_escapeQuoted(_string(detail['source'], 'detail.source'), escapeDollar: true)}", '
      '${_kotlinStringSet(_strings(detail['enumValues'], 'detail.enumValues'))}, '
      '${_kotlinNullableInt(detail['minLength'])}, ${_kotlinNullableInt(detail['maxLength'])}, '
      '${_quotedNumber(detail['minimum'])}, ${_quotedNumber(detail['maximum'])}, '
      '"${_escapeQuoted(_string(detail['redaction'], 'redaction'), escapeDollar: true)}"),',
    );
  }
  final requestId = _object(
    model.envelopes['/lifecycle/requestIdPolicy'],
    'requestIdPolicy',
  );
  final signed = _signedIntegerConstraint(model);
  output
    ..writeln(')')
    ..writeln(
      'internal const val generatedRequestIdWireType: String = '
      '"${_escapeQuoted(_string(requestId['wireType'], 'requestId.wireType'), escapeDollar: true)}"',
    )
    ..writeln(
      'internal const val generatedRequestIdPattern: String = '
      '"${_escapeQuoted(_string(requestId['pattern'], 'requestId.pattern'), escapeDollar: true)}"',
    )
    ..writeln(
      'internal const val generatedRequestIdFormat: String = '
      '"${_escapeQuoted(_string(requestId['format'], 'requestId.format'), escapeDollar: true)}"',
    )
    ..writeln(
      'internal const val generatedRequestIdMinLength: Int = '
      '${requestId['minLength']}',
    )
    ..writeln(
      'internal const val generatedRequestIdMaxLength: Int = '
      '${requestId['maxLength']}',
    )
    ..writeln(
      'internal val generatedEnvelopeRequiredKeys: '
      'Map<String, Set<String>> = mapOf(',
    );
  for (final entry in _envelopeDescriptors(model).entries) {
    output.writeln(
      '    "${_escapeQuoted(entry.key, escapeDollar: true)}" to '
      '${_kotlinStringSet(entry.value)},',
    );
  }
  output
    ..writeln(')')
    ..writeln(
      'internal val generatedEnvelopeUnknownFieldPolicies: '
      'Map<String, String> = mapOf(',
    );
  for (final entry in _envelopeUnknownFieldPolicies(model).entries) {
    output.writeln(
      '    "${_escapeQuoted(entry.key, escapeDollar: true)}" to '
      '"${_escapeQuoted(entry.value, escapeDollar: true)}",',
    );
  }
  output
    ..writeln(')')
    ..writeln(
      'internal const val generatedSignedIntegerMinimum: Long = '
      '${_kotlinLong(_int(signed['minimum'], 'signed minimum'))}',
    )
    ..writeln(
      'internal const val generatedSignedIntegerMaximum: Long = '
      '${_kotlinLong(_int(signed['maximum'], 'signed maximum'))}',
    )
    ..writeln(
      'internal val generatedOpaqueHandleLengths: '
      'Map<String, IntRange> = mapOf(',
    );
  for (final handle in _opaqueHandleConstraints(model)) {
    output.writeln(
      '    "${_escapeQuoted(_string(handle['capabilityFieldId'], 'handle.id'), escapeDollar: true)}" to '
      '${handle['minLength']}..${handle['maxLength']},',
    );
  }
  output
    ..writeln(')')
    ..writeln();
}

String _renderSwift(MediaCaptureWireGenerationModel model) {
  final output = StringBuffer()
    ..write(_header('//', model))
    ..writeln('import Foundation')
    ..writeln('import CoreFoundation')
    ..writeln()
    ..writeln(
      'internal let generatedMediaCaptureWireVersion = '
      '${model.wireVersion}',
    );
  for (final channel in model.channels) {
    output.writeln(
      'internal let generated${_upperCamel(_id(channel, 'channel'))}Channel = '
      '"${_escapeQuoted(_string(channel['name'], 'channel.name'))}"',
    );
  }
  output.writeln();
  _renderSwiftEnum(output, 'GeneratedMediaCaptureWireMethod', model.methodIds);
  _renderSwiftEnum(output, 'GeneratedMediaCaptureWireEvent', model.eventIds);
  _renderSwiftEnum(
    output,
    'GeneratedMediaCaptureWireResult',
    model.resultTypeIds,
  );
  _renderSwiftEnum(
    output,
    'GeneratedMediaCaptureWireFailure',
    model.failureTypeIds,
  );
  _renderSwiftEnum(output, 'GeneratedMediaCaptureWireError', model.errorCodes);
  output
    ..writeln('internal struct GeneratedWireFieldDescriptor: Sendable {')
    ..writeln('    let id: String')
    ..writeln('    let key: String')
    ..writeln('    let type: String')
    ..writeln('    let required: Bool')
    ..writeln('    let nullable: Bool')
    ..writeln('    let enumValues: Set<String>')
    ..writeln('    let minimum: String?')
    ..writeln('    let maximum: String?')
    ..writeln('    let allowedIntegers: Set<Int64>')
    ..writeln('    let minItems: Int?')
    ..writeln('    let maxItems: Int?')
    ..writeln('    let finite: Bool')
    ..writeln('    let format: String')
    ..writeln('    let boundarySource: String?')
    ..writeln('    let outOfRangePolicy: String')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'internal let generatedMediaCaptureWireFields: '
      '[GeneratedWireFieldDescriptor] = [',
    );
  for (final field in model.fields) {
    final validation = field.validation;
    output
      ..writeln('    GeneratedWireFieldDescriptor(')
      ..writeln(
        '        id: "${_escapeQuoted(field.id)}", '
        'key: "${_escapeQuoted(field.key)}", '
        'type: "${_escapeQuoted(field.wireType)}",',
      )
      ..writeln(
        '        required: ${_swiftBool(field.required)}, '
        'nullable: ${_swiftBool(field.nullable)},',
      )
      ..writeln('        enumValues: ${_swiftStringSet(field.enumValues)},')
      ..writeln(
        '        minimum: ${_swiftNullableNumberString(validation['minimum'])}, '
        'maximum: ${_swiftNullableNumberString(validation['maximum'])},',
      )
      ..writeln(
        '        allowedIntegers: ${_swiftIntSet(validation['allowedIntegers'])},',
      )
      ..writeln(
        '        minItems: ${_swiftLiteral(validation['minItems'])}, '
        'maxItems: ${_swiftLiteral(validation['maxItems'])},',
      )
      ..writeln(
        '        finite: ${_swiftBool(validation['finite'] == true)}, '
        'format: "${_escapeQuoted(_string(validation['format'], 'format'))}",',
      )
      ..writeln(
        '        boundarySource: ${_swiftNullableString(validation['boundarySource'])}, '
        'outOfRangePolicy: "${_escapeQuoted(_string(validation['outOfRangePolicy'], 'outOfRangePolicy'))}"',
      )
      ..writeln('    ),');
  }
  output
    ..writeln(']')
    ..writeln()
    ..writeln(
      'internal let generatedPayloadFieldIds: [String: Set<String>] = [',
    );
  for (final payload in model.payloads) {
    output.writeln(
      '    "${_escapeQuoted(payload.id)}": '
      '${_swiftStringSet(payload.fieldIds)},',
    );
  }
  output
    ..writeln(']')
    ..writeln();
  _renderSwiftProtocolDescriptors(output, model);
  output
    ..writeln('internal func generatedHasExactWireKeys(')
    ..writeln('    _ value: [String: Any], requiredKeys: Set<String>')
    ..writeln(') -> Bool {')
    ..writeln(
      '    value.count == requiredKeys.count && Set(value.keys) == requiredKeys',
    )
    ..writeln('}')
    ..writeln()
    ..writeln('internal func generatedIsWireBoolean(_ value: Any) -> Bool {')
    ..writeln('    guard let number = value as? NSNumber else { return false }')
    ..writeln('    return CFGetTypeID(number) == CFBooleanGetTypeID()')
    ..writeln('}')
    ..writeln()
    ..writeln('internal func generatedWireDouble(_ value: Any) -> Double? {')
    ..writeln('    guard let number = value as? NSNumber,')
    ..writeln('          CFGetTypeID(number) != CFBooleanGetTypeID(),')
    ..writeln(
      '          CFNumberIsFloatType(number as CFNumber) else { return nil }',
    )
    ..writeln('    return number.doubleValue')
    ..writeln('}')
    ..writeln()
    ..writeln('internal func generatedWireInteger(_ value: Any) -> Int64? {')
    ..writeln('    guard let number = value as? NSNumber,')
    ..writeln('          CFGetTypeID(number) != CFBooleanGetTypeID(),')
    ..writeln(
      '          !CFNumberIsFloatType(number as CFNumber) else { return nil }',
    )
    ..writeln('    return number.int64Value')
    ..writeln('}')
    ..writeln()
    ..writeln('internal func generatedMatchesWireFieldPrimitive(')
    ..writeln('    _ value: Any?, field: GeneratedWireFieldDescriptor')
    ..writeln(') -> Bool {')
    ..writeln('    guard let value else { return field.nullable }')
    ..writeln('    if let bytes = value as? Data {')
    ..writeln(
      '        if let minimum = field.minItems, bytes.count < minimum { return false }',
    )
    ..writeln(
      '        if let maximum = field.maxItems, bytes.count > maximum { return false }',
    )
    ..writeln('    }')
    ..writeln('    switch field.type {')
    ..writeln('    case "bool": return generatedIsWireBoolean(value)')
    ..writeln('    case "bytes": return value is Data')
    ..writeln('    case "double":')
    ..writeln(
      '        guard let number = generatedWireDouble(value) else { return false }',
    )
    ..writeln('        if field.finite && !number.isFinite { return false }')
    ..writeln(
      '        if let minimum = field.minimum.flatMap(Double.init), number < minimum { return false }',
    )
    ..writeln(
      '        if let maximum = field.maximum.flatMap(Double.init), number > maximum { return false }',
    )
    ..writeln('        return true')
    ..writeln('    case "int":')
    ..writeln(
      '        guard let number = generatedWireInteger(value) else { return false }',
    )
    ..writeln(
      '        if let minimum = field.minimum.flatMap(Int64.init), number < minimum { return false }',
    )
    ..writeln(
      '        if let maximum = field.maximum.flatMap(Int64.init), number > maximum { return false }',
    )
    ..writeln(
      '        return field.allowedIntegers.isEmpty || field.allowedIntegers.contains(number)',
    )
    ..writeln('    case "string":')
    ..writeln(
      '        guard let string = value as? String else { return false }',
    )
    ..writeln(
      '        return field.enumValues.isEmpty || field.enumValues.contains(string)',
    )
    ..writeln('    case "list_bool", "list_double", "list_int", "list_string":')
    ..writeln(
      '        guard let values = value as? [Any] else { return false }',
    )
    ..writeln(
      '        if let minimum = field.minItems, values.count < minimum { return false }',
    )
    ..writeln(
      '        if let maximum = field.maxItems, values.count > maximum { return false }',
    )
    ..writeln('        switch field.type {')
    ..writeln(
      r'        case "list_bool": return values.allSatisfy(generatedIsWireBoolean)',
    )
    ..writeln(r'        case "list_double":')
    ..writeln(
      '            let numbers = values.compactMap(generatedWireDouble)',
    )
    ..writeln(
      '            guard numbers.count == values.count else { return false }',
    )
    ..writeln(
      '            return !field.finite || numbers.allSatisfy(\\.isFinite)',
    )
    ..writeln(
      r'        case "list_int": return values.allSatisfy { generatedWireInteger($0) != nil }',
    )
    ..writeln('        default:')
    ..writeln(
      r'            guard values.allSatisfy({ $0 is String }) else { return false }',
    )
    ..writeln(r'            let strings = values.map { $0 as! String }')
    ..writeln(
      '            guard field.enumValues.isEmpty || strings.allSatisfy(field.enumValues.contains) else { return false }',
    )
    ..writeln(
      '            return field.enumValues.isEmpty || Set(strings).count == strings.count',
    )
    ..writeln('        }')
    ..writeln('    default: return false')
    ..writeln('    }')
    ..writeln('}')
    ..writeln();
  return output.toString();
}

void _renderSwiftEnum(StringBuffer output, String type, List<String> values) {
  output.writeln('internal enum $type: String, CaseIterable, Sendable {');
  for (final value in values) {
    output.writeln(
      '    case ${_runtimeIdentifier(value)} = "${_escapeQuoted(value)}"',
    );
  }
  output
    ..writeln('}')
    ..writeln();
}

void _renderSwiftProtocolDescriptors(
  StringBuffer output,
  MediaCaptureWireGenerationModel model,
) {
  output
    ..writeln('internal struct GeneratedWirePayloadDescriptor: Sendable {')
    ..writeln('    let id: String')
    ..writeln('    let kind: String')
    ..writeln('    let fieldIds: Set<String>')
    ..writeln('    let unknownFieldPolicy: String')
    ..writeln('}')
    ..writeln('internal let generatedPayloadDescriptors = [');
  for (final payload in model.payloads) {
    output.writeln(
      '    GeneratedWirePayloadDescriptor('
      'id: "${_escapeQuoted(payload.id)}", '
      'kind: "${_escapeQuoted(payload.kind)}", '
      'fieldIds: ${_swiftStringSet(payload.fieldIds)}, '
      'unknownFieldPolicy: "${_escapeQuoted(payload.unknownFieldPolicy)}"),',
    );
  }
  output
    ..writeln(']')
    ..writeln('internal struct GeneratedWireErrorDescriptor: Sendable {')
    ..writeln('    let code: String')
    ..writeln('    let source: String')
    ..writeln('    let capabilityFailureId: String?')
    ..writeln('    let recoverable: Bool')
    ..writeln('    let terminal: Bool')
    ..writeln('    let messagePolicy: String')
    ..writeln('    let detailsAllowedKeys: Set<String>')
    ..writeln('}')
    ..writeln('internal let generatedErrorDescriptors = [');
  for (final error in model.errorDescriptors) {
    output.writeln(
      '    GeneratedWireErrorDescriptor('
      'code: "${_escapeQuoted(_string(error['code'], 'error.code'))}", '
      'source: "${_escapeQuoted(_string(error['source'], 'error.source'))}", '
      'capabilityFailureId: ${_swiftNullableString(error['capabilityFailureId'])}, '
      'recoverable: ${_swiftBool(error['recoverable'] == true)}, '
      'terminal: ${_swiftBool(error['terminal'] == true)}, '
      'messagePolicy: "${_escapeQuoted(_string(error['messagePolicy'], 'messagePolicy'))}", '
      'detailsAllowedKeys: ${_swiftStringSet(_strings(error['detailsAllowedKeys'], 'details'))}),',
    );
  }
  output
    ..writeln(']')
    ..writeln('internal struct GeneratedWireErrorDetailDescriptor: Sendable {')
    ..writeln('    let key: String')
    ..writeln('    let type: String')
    ..writeln('    let source: String')
    ..writeln('    let enumValues: Set<String>')
    ..writeln('    let minLength: Int?')
    ..writeln('    let maxLength: Int?')
    ..writeln('    let minimum: String?')
    ..writeln('    let maximum: String?')
    ..writeln('    let redaction: String')
    ..writeln('}')
    ..writeln('internal let generatedErrorDetailDescriptors = [');
  for (final detail in model.errorDetailDescriptors) {
    output.writeln(
      '    GeneratedWireErrorDetailDescriptor('
      'key: "${_escapeQuoted(_string(detail['key'], 'detail.key'))}", '
      'type: "${_escapeQuoted(_string(detail['wireType'], 'detail.type'))}", '
      'source: "${_escapeQuoted(_string(detail['source'], 'detail.source'))}", '
      'enumValues: ${_swiftStringSet(_strings(detail['enumValues'], 'detail.enumValues'))}, '
      'minLength: ${_swiftLiteral(detail['minLength'])}, '
      'maxLength: ${_swiftLiteral(detail['maxLength'])}, '
      'minimum: ${_swiftNullableNumberString(detail['minimum'])}, '
      'maximum: ${_swiftNullableNumberString(detail['maximum'])}, '
      'redaction: "${_escapeQuoted(_string(detail['redaction'], 'redaction'))}"),',
    );
  }
  final requestId = _object(
    model.envelopes['/lifecycle/requestIdPolicy'],
    'requestIdPolicy',
  );
  final signed = _signedIntegerConstraint(model);
  output
    ..writeln(']')
    ..writeln(
      'internal let generatedRequestIdWireType = '
      '"${_escapeQuoted(_string(requestId['wireType'], 'requestId.wireType'))}"',
    )
    ..writeln(
      'internal let generatedRequestIdPattern = '
      '"${_escapeQuoted(_string(requestId['pattern'], 'requestId.pattern'))}"',
    )
    ..writeln(
      'internal let generatedRequestIdFormat = '
      '"${_escapeQuoted(_string(requestId['format'], 'requestId.format'))}"',
    )
    ..writeln(
      'internal let generatedRequestIdMinLength = ${requestId['minLength']}',
    )
    ..writeln(
      'internal let generatedRequestIdMaxLength = ${requestId['maxLength']}',
    )
    ..writeln(
      'internal let generatedEnvelopeRequiredKeys: '
      '[String: Set<String>] = [',
    );
  for (final entry in _envelopeDescriptors(model).entries) {
    output.writeln(
      '    "${_escapeQuoted(entry.key)}": ${_swiftStringSet(entry.value)},',
    );
  }
  output
    ..writeln(']')
    ..writeln(
      'internal let generatedEnvelopeUnknownFieldPolicies: '
      '[String: String] = [',
    );
  for (final entry in _envelopeUnknownFieldPolicies(model).entries) {
    output.writeln(
      '    "${_escapeQuoted(entry.key)}": "${_escapeQuoted(entry.value)}",',
    );
  }
  output
    ..writeln(']')
    ..writeln('internal let generatedSignedIntegerMinimum: Int64 = Int64.min')
    ..writeln('internal let generatedSignedIntegerMaximum: Int64 = Int64.max')
    ..writeln(
      'internal let generatedOpaqueHandleLengths: '
      '[String: ClosedRange<Int>] = [',
    );
  for (final handle in _opaqueHandleConstraints(model)) {
    output.writeln(
      '    "${_escapeQuoted(_string(handle['capabilityFieldId'], 'handle.id'))}": '
      '${handle['minLength']}...${handle['maxLength']},',
    );
  }
  output
    ..writeln(']')
    ..writeln();
  if (signed['minimum'] != -9223372036854775808 ||
      signed['maximum'] != 9223372036854775807) {
    throw const FormatException('Swift renderer requires signed 64-bit bounds');
  }
}

String _calculateSourceDigest(Map<String, Object?> projection) {
  final canonical = jsonEncode(_canonicalJson(projection));
  return sha256.convert(utf8.encode(canonical)).toString();
}

Map<String, Object?> _generatedEnvelopeProjection(
  Map<String, Object?> envelopes,
) {
  final projection = <String, Object?>{};
  final entries = envelopes.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in entries) {
    final value = _object(entry.value, entry.key);
    if (entry.key.endsWith('Envelope')) {
      projection[entry.key] = <String, Object?>{
        'requiredKeys': _strings(value['requiredKeys'], entry.key),
        'unknownFieldPolicy': _string(
          value['unknownFieldPolicy'],
          '${entry.key}.unknownFieldPolicy',
        ),
      };
    } else {
      projection[entry.key] = <String, Object?>{
        for (final key in const <String>[
          'wireType',
          'minLength',
          'maxLength',
          'pattern',
          'format',
        ])
          key: value[key],
      };
    }
  }
  return projection;
}

Map<String, Object?> _generatedTransportProjection(
  Map<String, Object?> constraints,
) {
  final signed = _object(
    constraints['/transportConstraints/signedInteger'],
    'signedInteger',
  );
  final handles =
      _objects(
        constraints['/transportConstraints/opaqueHandles'],
        'opaqueHandles',
      )..sort(
        (left, right) => _string(
          left['capabilityFieldId'],
          'handle.id',
        ).compareTo(_string(right['capabilityFieldId'], 'handle.id')),
      );
  return <String, Object?>{
    '/transportConstraints/signedInteger': <String, Object?>{
      'minimum': signed['minimum'],
      'maximum': signed['maximum'],
    },
    '/transportConstraints/opaqueHandles': <Object?>[
      for (final handle in handles)
        <String, Object?>{
          'capabilityFieldId': handle['capabilityFieldId'],
          'minLength': handle['minLength'],
          'maxLength': handle['maxLength'],
        },
    ],
  };
}

Map<String, List<String>> _envelopeDescriptors(
  MediaCaptureWireGenerationModel model,
) {
  final result = <String, List<String>>{};
  final entries = model.envelopes.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in entries) {
    if (!entry.key.endsWith('Envelope')) {
      continue;
    }
    final envelope = _object(entry.value, entry.key);
    if (envelope['unknownFieldPolicy'] != 'reject') {
      throw FormatException('${entry.key} must reject unknown fields');
    }
    result[entry.key] = _strings(envelope['requiredKeys'], entry.key);
  }
  return result;
}

Map<String, String> _envelopeUnknownFieldPolicies(
  MediaCaptureWireGenerationModel model,
) {
  final result = <String, String>{};
  final entries = model.envelopes.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in entries) {
    if (!entry.key.endsWith('Envelope')) {
      continue;
    }
    final envelope = _object(entry.value, entry.key);
    result[entry.key] = _string(
      envelope['unknownFieldPolicy'],
      '${entry.key}.unknownFieldPolicy',
    );
  }
  return result;
}

Map<String, Object?> _signedIntegerConstraint(
  MediaCaptureWireGenerationModel model,
) => _object(
  model.transportConstraints['/transportConstraints/signedInteger'],
  'signedInteger',
);

List<Map<String, Object?>> _opaqueHandleConstraints(
  MediaCaptureWireGenerationModel model,
) =>
    _objects(
      model.transportConstraints['/transportConstraints/opaqueHandles'],
      'opaqueHandles',
    )..sort(
      (left, right) => _string(
        left['capabilityFieldId'],
        'handle.id',
      ).compareTo(_string(right['capabilityFieldId'], 'handle.id')),
    );

Object? _canonicalJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalJson(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_canonicalJson).toList(growable: false);
  }
  return value;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$label must be an object');
  }
  return value;
}

List<Map<String, Object?>> _objects(Object? value, String label) {
  if (value is! List<Object?>) {
    throw FormatException('$label must be an array');
  }
  return value
      .map((entry) => _object(entry, '$label entry'))
      .toList(growable: true);
}

List<String> _strings(Object? value, String label) {
  if (value is! List<Object?> || value.any((entry) => entry is! String)) {
    throw FormatException('$label must be a string array');
  }
  return value.cast<String>().toList(growable: true);
}

List<int> _integers(Object? value, String label) {
  if (value is! List<Object?> || value.any((entry) => entry is! int)) {
    throw FormatException('$label must be an integer array');
  }
  return value.cast<int>().toList(growable: true);
}

String _string(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$label must be a non-empty string');
  }
  return value;
}

bool _boolean(Object? value, String label) {
  if (value is! bool) {
    throw FormatException('$label must be a boolean');
  }
  return value;
}

int _positiveInt(Object? value, String label) {
  if (value is! int || value < 1) {
    throw FormatException('$label must be a positive integer');
  }
  return value;
}

int _int(Object? value, String label) {
  if (value is! int) {
    throw FormatException('$label must be an integer');
  }
  return value;
}

int? _nullableInt(Object? value, String label) {
  if (value == null) {
    return null;
  }
  return _int(value, label);
}

int? _nullableNonNegativeInt(Object? value, String label) {
  final result = _nullableInt(value, label);
  if (result != null && result < 0) {
    throw FormatException('$label must be non-negative');
  }
  return result;
}

num? _nullableFiniteNum(Object? value, String label) {
  if (value == null) {
    return null;
  }
  if (value is! num || !value.isFinite) {
    throw FormatException('$label must be a finite number');
  }
  return value;
}

String? _nullableStableId(Object? value, String label) {
  if (value == null) {
    return null;
  }
  final result = _string(value, label);
  _validateStableId(result, label);
  return result;
}

void _validateOrderedBounds(num? minimum, num? maximum, String label) {
  if (minimum != null && maximum != null && minimum > maximum) {
    throw FormatException('$label minimum exceeds maximum');
  }
}

void _validateSigned64(int value, String label) {
  if (value < -9223372036854775808 || value > 9223372036854775807) {
    throw FormatException('$label must fit a signed 64-bit integer');
  }
}

void _validateKotlinInt(int value, String label) {
  if (value < -2147483648 || value > 2147483647) {
    throw FormatException('$label must fit a Kotlin Int');
  }
}

String _id(Map<String, Object?> value, String label) =>
    _string(value['id'], '$label.id');

int _compareById(Map<String, Object?> left, Map<String, Object?> right) =>
    _id(left, 'entry').compareTo(_id(right, 'entry'));

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String label,
) {
  final actual = value.keys.toSet();
  if (actual.difference(expected).isNotEmpty ||
      expected.difference(actual).isNotEmpty) {
    throw FormatException(
      '$label has invalid keys: ${actual.toList()..sort()}',
    );
  }
}

void _rejectDuplicates(List<String> values, String label) {
  if (values.toSet().length != values.length) {
    throw FormatException('$label contains duplicate wire values');
  }
}

void _rejectIntegerDuplicates(List<int> values, String label) {
  if (values.toSet().length != values.length) {
    throw FormatException('$label contains duplicate wire values');
  }
}

void _validateStableId(String value, String label) {
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(value)) {
    throw FormatException('$label is not a stable snake_case ID: $value');
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _upperCamel(String wireValue) {
  final lower = _runtimeIdentifier(wireValue);
  return '${lower[0].toUpperCase()}${lower.substring(1)}';
}

String _escapeDart(String value) {
  final output = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x5c:
        output.write(r'\\');
      case 0x27:
        output.write(r"\'");
      case 0x24:
        output.write(r'\$');
      case 0x0a:
        output.write(r'\n');
      case 0x0d:
        output.write(r'\r');
      case 0x09:
        output.write(r'\t');
      default:
        if (rune < 0x20 || rune > 0x7e) {
          output.write('\\u{${rune.toRadixString(16)}}');
        } else {
          output.writeCharCode(rune);
        }
    }
  }
  return output.toString();
}

String _escapeQuoted(String value, {bool escapeDollar = false}) {
  final output = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x5c:
        output.write(r'\\');
      case 0x22:
        output.write(r'\"');
      case 0x24 when escapeDollar:
        output.write(r'\$');
      case 0x0a:
        output.write(r'\n');
      case 0x0d:
        output.write(r'\r');
      case 0x09:
        output.write(r'\t');
      default:
        if (rune < 0x20 || rune > 0x7e) {
          if (escapeDollar) {
            if (rune <= 0xffff) {
              output.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
            } else {
              final scalar = rune - 0x10000;
              final high = 0xd800 + (scalar >> 10);
              final low = 0xdc00 + (scalar & 0x3ff);
              output
                ..write('\\u${high.toRadixString(16).padLeft(4, '0')}')
                ..write('\\u${low.toRadixString(16).padLeft(4, '0')}');
            }
          } else {
            output.write('\\u{${rune.toRadixString(16)}}');
          }
        } else {
          output.writeCharCode(rune);
        }
    }
  }
  return output.toString();
}

String _dartLiteral(Object? value) => switch (value) {
  null => 'null',
  bool() || num() => value.toString(),
  String() => "'${_escapeDart(value)}'",
  _ => throw FormatException('Cannot render Dart literal: $value'),
};

String _dartStringList(List<String> values) => values.isEmpty
    ? 'const <String>[]'
    : "const <String>[${values.map((value) => "'${_escapeDart(value)}'").join(', ')}]";

String _dartIntList(Object? value) {
  if (value is! List<Object?> || value.any((entry) => entry is! int)) {
    throw const FormatException('allowedIntegers must be an integer array');
  }
  return value.isEmpty ? 'const <int>[]' : 'const <int>[${value.join(', ')}]';
}

String _kotlinStringSet(List<String> values) => values.isEmpty
    ? 'emptySet()'
    : 'setOf(${values.map((value) => '"${_escapeQuoted(value, escapeDollar: true)}"').join(', ')})';

String _kotlinNullableString(Object? value) => value == null
    ? 'null'
    : '"${_escapeQuoted(_string(value, 'string'), escapeDollar: true)}"';

String _kotlinLongSet(Object? value) {
  if (value is! List<Object?> || value.any((entry) => entry is! int)) {
    throw const FormatException('allowedIntegers must be an integer array');
  }
  if (value.isEmpty) {
    return 'emptySet()';
  }
  return 'setOf(${value.cast<int>().map(_kotlinLong).join(', ')})';
}

String _kotlinLong(int value) {
  if (value == -9223372036854775808) {
    return 'Long.MIN_VALUE';
  }
  if (value == 9223372036854775807) {
    return 'Long.MAX_VALUE';
  }
  return '${value}L';
}

String _kotlinNullableInt(Object? value) =>
    value == null ? 'null' : _positiveOrZeroInt(value).toString();

int _positiveOrZeroInt(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Expected a non-negative integer');
  }
  return value;
}

String _quotedNumber(Object? value) =>
    value == null ? 'null' : '"${value.toString()}"';

String _swiftStringSet(List<String> values) => values.isEmpty
    ? '[]'
    : '[${values.map((value) => '"${_escapeQuoted(value)}"').join(', ')}]';

String _swiftNullableString(Object? value) =>
    value == null ? 'nil' : '"${_escapeQuoted(_string(value, 'string'))}"';

String _swiftLiteral(Object? value) => switch (value) {
  null => 'nil',
  bool() || num() => value.toString(),
  String() => '"${_escapeQuoted(value)}"',
  _ => throw FormatException('Cannot render Swift literal: $value'),
};

String _swiftNullableNumberString(Object? value) => value == null
    ? 'nil'
    : '"${_escapeQuoted(_string(value.toString(), 'number'))}"';

String _swiftIntSet(Object? value) {
  if (value is! List<Object?> || value.any((entry) => entry is! int)) {
    throw const FormatException('allowedIntegers must be an integer array');
  }
  return value.isEmpty ? '[]' : '[${value.join(', ')}]';
}

String _swiftBool(bool value) => value ? 'true' : 'false';
