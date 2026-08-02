import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:app_media_capture_bridge/src/media_capture_wire_codec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _exportHandle = 'ABCDEFGHIJKLMNOPQRSTUV';
const int _nowEpochMillis = 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = MediaCaptureWireCodec();
  const methodChannel = MethodChannel(mediaCaptureCommandsChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('Wire V3 materialized media codec', () {
    test('decodes closed photo and video metadata without exposing it', () {
      final photo = _decode(codec, _materializedPayload());
      final video = _decode(
        codec,
        _materializedPayload(
          mediaType: 'video',
          contentType: 'video/mp4',
          durationMillis: 15000,
          integritySha256: _repeat('a', 64),
        ),
        expectedMediaType: MediaCaptureMediaType.video,
        expectedDurationMillis: 15000,
      );

      expect(
        photo,
        isA<MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>>(),
      );
      final videoValue =
          (video as MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>)
              .value;
      expect(videoValue.mediaType, MediaCaptureMediaType.video);
      expect(videoValue.durationMillis, 15000);
      expect(videoValue.integritySha256, _repeat('a', 64));
      expect(videoValue.toString(), isNot(contains(_exportHandle)));
      expect(videoValue.toString(), isNot(contains('file:///')));
      expect(
        videoValue.exportHandle.toString(),
        isNot(contains(_exportHandle)),
      );
    });

    final mutations = <String, void Function(Map<String, Object?>)>{
      'short export handle': (payload) => payload['exportHandle'] = 'short',
      'wrong photo MIME': (payload) => payload['contentType'] = 'image/png',
      'zero length': (payload) => payload['byteLength'] = 0,
      'over maximum length': (payload) =>
          payload['byteLength'] = mediaCaptureMaxMaterializedBytes + 1,
      'photo duration': (payload) => payload['durationMillis'] = 1,
      'expired TTL': (payload) => payload['expiresAt'] = _nowEpochMillis,
      'overlong TTL': (payload) => payload['expiresAt'] =
          _nowEpochMillis + mediaCaptureMaterializedTtlMillis + 1,
      'uppercase integrity': (payload) =>
          payload['integritySha256'] = _repeat('A', 64),
      'short integrity': (payload) =>
          payload['integritySha256'] = _repeat('a', 63),
      'unknown key': (payload) => payload['path'] = '/private/file',
      'missing field': (payload) => payload.remove('byteLength'),
    };
    for (final entry in mutations.entries) {
      test('rejects ${entry.key}', () {
        final payload = _materializedPayload();
        entry.value(payload);

        final result = _decode(codec, payload);

        expect(
          result,
          isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
        );
        expect(
          (result as MediaCaptureCallFailure<MediaCaptureMaterializedMedia>)
              .failure
              .code,
          MediaCaptureFailureCode.invalidWirePayload,
        );
        expect(result.failure.toString(), isNot(contains('/private/file')));
      });
    }

    test('rejects metadata that does not match the confirmed source', () {
      final wrongType = _decode(
        codec,
        _materializedPayload(
          mediaType: 'video',
          contentType: 'video/mp4',
          durationMillis: 15000,
        ),
      );
      final wrongLength = _decode(
        codec,
        _materializedPayload()..['byteLength'] = 2048,
      );
      final wrongDuration = _decode(
        codec,
        _materializedPayload(
          mediaType: 'video',
          contentType: 'video/mp4',
          durationMillis: 15000,
        ),
        expectedMediaType: MediaCaptureMediaType.video,
        expectedDurationMillis: 14000,
      );

      for (final result
          in <MediaCaptureCallResult<MediaCaptureMaterializedMedia>>[
            wrongType,
            wrongLength,
            wrongDuration,
          ]) {
        expect(
          result,
          isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
        );
        expect(
          (result as MediaCaptureCallFailure<MediaCaptureMaterializedMedia>)
              .failure
              .code,
          MediaCaptureFailureCode.invalidWirePayload,
        );
      }
    });

    test('consumes every shared cross-runtime golden section', () {
      final vectors = _fileUriGoldenVectors();
      final crossRuntime = _crossRuntimeGolden();
      expect(crossRuntime.keys.toSet(), const {
        'schemaVersion',
        'contractId',
        'consumerBindings',
        'current',
        'history',
        'transfer',
        'lifecycle',
        'redaction',
      });
      final current = _objectMap(crossRuntime['current']);
      expect(current['capabilityVersion'], 4);
      expect(current['wireVersion'], mediaCaptureWireVersion);
      expect(
        (_objectList(current['methodIds']).cast<String>()).toSet(),
        MediaCaptureOperation.values
            .where(
              (operation) =>
                  operation != MediaCaptureOperation.unknownOperation,
            )
            .map((operation) => operation.wireName)
            .toSet(),
      );
      expect((_objectList(current['eventIds']).cast<String>()).toSet(), const {
        'session_ready',
        'session_failed',
        'media_preview_ready',
        'media_lease_expired',
        'media_read_revoked',
      });
      expect(
        (_objectList(current['capabilityOperationIds']).cast<String>()).toSet(),
        const {
          'start_session',
          'take_photo',
          'start_recording',
          'stop_recording',
          'switch_camera',
          'set_flash_mode',
          'set_focus_point',
          'set_zoom',
          'retake',
          'confirm',
          'cancel',
          'open_media_read',
          'release_media',
          'attach_live_preview',
          'detach_live_preview',
          'attach_unconfirmed_preview_render',
          'detach_unconfirmed_preview_render',
          'read_media_thumbnail',
          'copy_confirmed_media_to_sink',
        },
      );
      expect(
        (_objectList(current['capabilityEventIds']).cast<String>()).toSet(),
        const {
          'session_ready',
          'session_failed',
          'media_preview_ready',
          'media_lease_expired',
          'media_read_revoked',
          'render_attachment_revoked',
        },
      );
      final capabilityFailures = MediaCaptureCapabilityFailure.values
          .map((value) => value.wireName)
          .toSet();
      final wireFailures = MediaCaptureFailureCode.values
          .map((value) => value.wireName)
          .toSet();
      final mappedCapabilityFailures = (_objectList(
        current['mappedCapabilityFailureIds'],
      ).cast<String>()).toSet();
      final wireProtocolFailures = (_objectList(
        current['wireProtocolFailureIds'],
      ).cast<String>()).toSet();
      expect(
        (_objectList(current['capabilityFailureIds']).cast<String>()).toSet(),
        capabilityFailures,
      );
      expect(
        (_objectList(current['failureIds']).cast<String>()).toSet(),
        wireFailures,
      );
      expect(
        mappedCapabilityFailures,
        capabilityFailures.difference(const {
          'attachment_generation_retired',
          'attachment_target_conflict',
        }),
      );
      expect(
        wireProtocolFailures,
        wireFailures.difference(mappedCapabilityFailures),
      );

      final history = _objectMap(crossRuntime['history']);
      expect(_objectList(history['capability']), const <Object?>[
        {
          'version': 1,
          'operationCount': 13,
          'eventCount': 5,
          'nativeReadScope': true,
          'nativeRenderScope': 'none',
          'boundedExport': false,
        },
        {
          'version': 2,
          'operationCount': 18,
          'eventCount': 6,
          'nativeReadScope': true,
          'nativeRenderScope': 'callback_adapter',
          'boundedExport': false,
        },
        {
          'version': 3,
          'operationCount': 18,
          'eventCount': 6,
          'nativeReadScope': true,
          'nativeRenderScope': 'module_concrete_surface',
          'boundedExport': false,
        },
        {
          'version': 4,
          'operationCount': 19,
          'eventCount': 6,
          'nativeReadScope': true,
          'nativeRenderScope': 'module_concrete_surface',
          'boundedExport': true,
        },
      ]);
      expect(_objectList(history['wire']), const <Object?>[
        {
          'version': 1,
          'compatibleCapabilityVersions': [1],
          'methodCount': 12,
          'eventCount': 5,
          'exposesNativeRead': false,
          'exposesNativeRender': false,
          'exposesTransfer': false,
        },
        {
          'version': 2,
          'compatibleCapabilityVersions': [2, 3],
          'methodCount': 14,
          'eventCount': 5,
          'exposesNativeRead': false,
          'exposesNativeRender': false,
          'exposesTransfer': false,
        },
        {
          'version': 3,
          'compatibleCapabilityVersions': [4],
          'methodCount': 17,
          'eventCount': 5,
          'exposesNativeRead': false,
          'exposesNativeRender': false,
          'exposesTransfer': true,
        },
      ]);

      final transfer = _objectMap(crossRuntime['transfer']);
      expect(_objectMap(transfer['limits']), const {
        'maxFileBytes': mediaCaptureMaxMaterializedBytes,
        'ttlSeconds': mediaCaptureMaterializedTtlMillis ~/ 1000,
        'maxActiveExportsPerEngineAttachment': 4,
        'maxActiveBytesPerEngineAttachment': 104857600,
        'releaseTombstoneSeconds': 300,
        'maxReleaseTombstones': 4096,
      });
      for (final value in _objectList(transfer['mimeCases'])) {
        final item = _objectMap(value);
        final mediaType = _string(item['mediaType']) == 'photo'
            ? MediaCaptureMediaType.photo
            : MediaCaptureMediaType.video;
        final duration = mediaType == MediaCaptureMediaType.video ? 1000 : null;
        final result = _decode(
          codec,
          _materializedPayload(
            mediaType: mediaType.wireName,
            contentType: _string(item['contentType']),
            durationMillis: duration,
          ),
          expectedMediaType: mediaType,
          expectedDurationMillis: duration,
        );
        expect(
          result is MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>,
          item['valid'],
          reason: '${item['mediaType']}/${item['contentType']}',
        );
      }
      final signedMinimum = BigInt.parse('-9223372036854775808');
      final signedMaximum = BigInt.parse('9223372036854775807');
      for (final value in _objectList(transfer['signed64Cases'])) {
        final item = _objectMap(value);
        final parsed = BigInt.tryParse(_string(item['decimal']));
        final valid =
            parsed != null &&
            parsed >= signedMinimum &&
            parsed <= signedMaximum;
        expect(valid, item['valid'], reason: _string(item['decimal']));
      }
      final crossRuntimeVectors = _fileUriVectors(transfer['fileUriCases']);
      expect(crossRuntimeVectors.length, vectors.length);
      for (var index = 0; index < vectors.length; index += 1) {
        expect(crossRuntimeVectors[index], vectors[index]);
      }

      for (final vector in vectors) {
        final payload = _materializedPayload()..['fileUri'] = vector.uri;
        final result = _decode(codec, payload);
        expect(
          result is MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>,
          vector.valid,
          reason: vector.id,
        );
      }
      for (final value in _objectList(transfer['fileUriLengthCases'])) {
        final item = _objectMap(value);
        final length = item['totalLength']! as int;
        final uri = 'file:///${_repeat('a', length - 8)}';
        final result = _decode(
          codec,
          _materializedPayload()..['fileUri'] = uri,
        );
        expect(
          result is MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>,
          item['valid'],
          reason: '$length',
        );
      }

      expect(_objectMap(crossRuntime['lifecycle']), const {
        'cleanupOrder': [
          'import_store_commit',
          'release_transfer',
          'release_source_lease',
        ],
        'lateCompletion': 'cleanup_without_delivery',
        'engineDetach': 'delete_transfer_before_boundary_completion',
        'releaseAfterTombstone': 'idempotent_success',
      });
      expect(_objectMap(crossRuntime['redaction']), const {
        'forbiddenPersistentKeys': [
          'fileUri',
          'mediaHandle',
          'exportHandle',
          'absolutePath',
        ],
        'failureDetailsMayContainLocator': false,
        'logsMayContainLocator': false,
      });
    });

    test('uses ASCII code-unit length at the 4096 boundary', () {
      final maximum =
          'file:///${_repeat('a', mediaCaptureMaxFileUriLength - 8)}';
      final overMaximum = '${maximum}a';

      expect(
        _decode(codec, _materializedPayload()..['fileUri'] = maximum),
        isA<MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>>(),
      );
      expect(
        _decode(codec, _materializedPayload()..['fileUri'] = overMaximum),
        isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
      );
    });

    test('release result requires an empty payload', () {
      final valid = codec.decodeMaterializedMediaReleased(
        _resultEnvelope(
          resultType: 'materialized_media_released',
          payload: const <String, Object?>{},
        ),
        requestId: 'request-1',
      );
      final invalid = codec.decodeMaterializedMediaReleased(
        _resultEnvelope(
          resultType: 'materialized_media_released',
          payload: const <String, Object?>{'exportHandle': _exportHandle},
        ),
        requestId: 'request-1',
      );

      expect(
        valid,
        isA<MediaCaptureCallSuccess<MediaCaptureMaterializedMediaReleased>>(),
      );
      expect(
        invalid,
        isA<MediaCaptureCallFailure<MediaCaptureMaterializedMediaReleased>>(),
      );
    });
  });

  group('MediaCaptureClient transfer lifecycle', () {
    test(
      'sends only the confirmed handle and explicit export handle',
      () async {
        final methods = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              methods.add(call.method);
              final request = _wireMap(call.arguments);
              final payload = _wireMap(request['payload']);
              expect(request['wireVersion'], 3);
              if (call.method == methodMaterializeMediaResource) {
                expect(payload, const <String, Object?>{
                  'mediaHandle': 'media-1',
                });
                return _resultEnvelope(
                  requestId: _string(request['requestId']),
                  resultType: 'materialized_media_resource',
                  payload: _materializedPayload(),
                );
              }
              expect(call.method, methodReleaseMaterializedMedia);
              expect(payload, const <String, Object?>{
                'exportHandle': _exportHandle,
              });
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'materialized_media_released',
                payload: const <String, Object?>{},
              );
            });
        final client = _client();

        final materialized = await client.materializeMedia(_confirmedMedia());
        final value =
            (materialized
                    as MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>)
                .value;
        final released = await client.releaseMaterializedMedia(
          value.exportHandle,
        );

        expect(
          released,
          isA<MediaCaptureCallSuccess<MediaCaptureMaterializedMediaReleased>>(),
        );
        expect(methods, <String>[
          methodMaterializeMediaResource,
          methodReleaseMaterializedMedia,
        ]);
        await client.dispose();
      },
    );

    test('dispose releases a late materialize success exactly once', () async {
      final nativeResult = Completer<Object?>();
      String? materializeRequestId;
      var releaseCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) {
            final request = _wireMap(call.arguments);
            if (call.method == methodMaterializeMediaResource) {
              materializeRequestId = _string(request['requestId']);
              return nativeResult.future;
            }
            expect(call.method, methodReleaseMaterializedMedia);
            releaseCalls += 1;
            return Future<Object?>.value(
              _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'materialized_media_released',
                payload: const <String, Object?>{},
              ),
            );
          });
      final client = _client();

      final pending = client.materializeMedia(_confirmedMedia());
      await Future<void>.delayed(Duration.zero);
      final disposing = client.dispose();
      nativeResult.complete(
        _resultEnvelope(
          requestId: materializeRequestId!,
          resultType: 'materialized_media_resource',
          payload: _materializedPayload(),
        ),
      );

      final result = await pending;
      expect(
        result,
        isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
      );
      expect(
        (result as MediaCaptureCallFailure<MediaCaptureMaterializedMedia>)
            .failure
            .code,
        MediaCaptureFailureCode.bridgeUnavailable,
      );
      await disposing;
      expect(releaseCalls, 1);
    });

    final rejectedPayloads = <String, void Function(Map<String, Object?>)>{
      'invalid file URI': (payload) => payload['fileUri'] = 'https://invalid',
      'invalid MIME': (payload) => payload['contentType'] = 'image/png',
      'expired TTL': (payload) => payload['expiresAt'] = _nowEpochMillis,
      'unknown field': (payload) => payload['path'] = '/private/file',
      'source metadata mismatch': (payload) => payload['byteLength'] = 2048,
    };
    for (final entry in rejectedPayloads.entries) {
      test('releases adopted export after rejecting ${entry.key}', () async {
        var releaseCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              final request = _wireMap(call.arguments);
              if (call.method == methodMaterializeMediaResource) {
                final payload = _materializedPayload();
                entry.value(payload);
                return _resultEnvelope(
                  requestId: _string(request['requestId']),
                  resultType: 'materialized_media_resource',
                  payload: payload,
                );
              }
              expect(call.method, methodReleaseMaterializedMedia);
              releaseCalls += 1;
              expect(_wireMap(request['payload']), const <String, Object?>{
                'exportHandle': _exportHandle,
              });
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'materialized_media_released',
                payload: const <String, Object?>{},
              );
            });
        final client = _client();

        final result = await client.materializeMedia(_confirmedMedia());

        expect(
          result,
          isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
        );
        expect(releaseCalls, 1);
        await client.dispose();
        expect(releaseCalls, 1);
      });
    }

    test(
      'retains a failed rejected-result release for dispose retry',
      () async {
        var releaseCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              final request = _wireMap(call.arguments);
              if (call.method == methodMaterializeMediaResource) {
                return _resultEnvelope(
                  requestId: _string(request['requestId']),
                  resultType: 'materialized_media_resource',
                  payload: _materializedPayload()
                    ..['contentType'] = 'image/png',
                );
              }
              releaseCalls += 1;
              if (releaseCalls == 1) {
                throw PlatformException(code: 'private-release-failure');
              }
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'materialized_media_released',
                payload: const <String, Object?>{},
              );
            });
        final client = _client();

        final result = await client.materializeMedia(_confirmedMedia());

        expect(
          result,
          isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
        );
        expect(releaseCalls, 1);
        await client.dispose();
        expect(releaseCalls, 2);
      },
    );

    test('late rejected result is released before dispose completes', () async {
      final nativeResult = Completer<Object?>();
      String? materializeRequestId;
      var releaseCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            final request = _wireMap(call.arguments);
            if (call.method == methodMaterializeMediaResource) {
              materializeRequestId = _string(request['requestId']);
              return nativeResult.future;
            }
            releaseCalls += 1;
            return _resultEnvelope(
              requestId: _string(request['requestId']),
              resultType: 'materialized_media_released',
              payload: const <String, Object?>{},
            );
          });
      final client = _client();

      final pending = client.materializeMedia(_confirmedMedia());
      await Future<void>.delayed(Duration.zero);
      final disposing = client.dispose();
      nativeResult.complete(
        _resultEnvelope(
          requestId: materializeRequestId!,
          resultType: 'materialized_media_resource',
          payload: _materializedPayload()..['contentType'] = 'image/png',
        ),
      );

      final result = await pending;
      expect(
        (result as MediaCaptureCallFailure<MediaCaptureMaterializedMedia>)
            .failure
            .code,
        MediaCaptureFailureCode.bridgeUnavailable,
      );
      await disposing;
      expect(releaseCalls, 1);
    });

    test(
      'does not release a handle from a mismatched response identity',
      () async {
        var releaseCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              if (call.method == methodReleaseMaterializedMedia) {
                releaseCalls += 1;
              }
              return _resultEnvelope(
                requestId: 'different-request',
                resultType: 'materialized_media_resource',
                payload: _materializedPayload(),
              );
            });
        final client = _client();

        final result = await client.materializeMedia(_confirmedMedia());

        expect(
          result,
          isA<MediaCaptureCallFailure<MediaCaptureMaterializedMedia>>(),
        );
        expect(releaseCalls, 0);
        await client.dispose();
        expect(releaseCalls, 0);
      },
    );

    test('rejects transfer error details containing a locator', () {
      const path = 'file:///private/secret.mp4';
      final failure = codec.platformExceptionToFailure(
        PlatformException(
          code: 'transfer_store_unavailable',
          details: const <String, Object?>{
            'operation': 'materialize_media_resource',
            'lifecycleReason': 'adapter_disposed',
            'fileUri': path,
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.materializeMediaResource,
      );

      expect(failure.code, MediaCaptureFailureCode.invalidWirePayload);
      expect(failure.toString(), isNot(contains(path)));
    });
  });
}

MediaCaptureCallResult<MediaCaptureMaterializedMedia> _decode(
  MediaCaptureWireCodec codec,
  Map<String, Object?> payload, {
  MediaCaptureMediaType expectedMediaType = MediaCaptureMediaType.photo,
  int expectedByteLength = 1024,
  int? expectedDurationMillis,
}) {
  return codec.decodeMaterializedMedia(
    _resultEnvelope(
      resultType: 'materialized_media_resource',
      payload: payload,
    ),
    requestId: 'request-1',
    nowEpochMillis: _nowEpochMillis,
    expectedMediaType: expectedMediaType,
    expectedByteLength: expectedByteLength,
    expectedDurationMillis: expectedDurationMillis,
  );
}

Map<String, Object?> _materializedPayload({
  String mediaType = 'photo',
  String contentType = 'image/jpeg',
  int? durationMillis,
  String? integritySha256,
}) {
  return <String, Object?>{
    'exportHandle': _exportHandle,
    'fileUri': 'file:///data/user/0/app/cache/media-transfer/a.bin',
    'mediaType': mediaType,
    'contentType': contentType,
    'byteLength': 1024,
    'durationMillis': durationMillis,
    'expiresAt': _nowEpochMillis + mediaCaptureMaterializedTtlMillis,
    if (integritySha256 != null) 'integritySha256': integritySha256,
  };
}

Map<String, Object?> _resultEnvelope({
  String requestId = 'request-1',
  required String resultType,
  required Map<String, Object?> payload,
}) {
  return <String, Object?>{
    'wireVersion': mediaCaptureWireVersion,
    'requestId': requestId,
    'resultType': resultType,
    'payload': payload,
  };
}

MediaCaptureClient _client() =>
    MediaCaptureClient(epochMillis: () => _nowEpochMillis);

MediaCaptureConfirmedMedia _confirmedMedia() {
  return MediaCaptureConfirmedMedia(
    mediaHandle: MediaCaptureMediaHandle('media-1'),
    mediaType: MediaCaptureMediaType.photo,
    pixelWidth: 1,
    pixelHeight: 1,
    durationMillis: null,
    orientationDegrees: 0,
    byteLength: 1024,
    leaseExpiresAtMillis: 999999,
  );
}

List<({String id, String uri, bool valid})> _fileUriGoldenVectors() {
  final directory = _repositoryRoot();
  final contract = jsonDecode(
    File(
      '${directory.path}/docs/bridge/contracts/media-capture.wire.json',
    ).readAsStringSync(),
  );
  final root = _objectMap(contract);
  final transferStore = _objectMap(root['transferStore']);
  return _fileUriVectors(transferStore['fileUriGoldenVectors']);
}

Map<String, Object?> _crossRuntimeGolden() {
  final directory = _repositoryRoot();
  return _objectMap(
    jsonDecode(
      File(
        '${directory.path}/app/packages/app_media_capture_bridge/'
        'test/contracts/media-capture-v4-v3.golden.json',
      ).readAsStringSync(),
    ),
  );
}

Directory _repositoryRoot() {
  var directory = Directory.current.absolute;
  while (!File(
    '${directory.path}/docs/bridge/contracts/media-capture.wire.json',
  ).existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Repository root not found');
    }
    directory = parent;
  }
  return directory;
}

List<({String id, String uri, bool valid})> _fileUriVectors(Object? value) {
  final vectors = _objectList(value);
  return <({String id, String uri, bool valid})>[
    for (final item in vectors)
      (
        id: _string(_objectMap(item)['id']),
        uri: _string(_objectMap(item)['uri']),
        valid: _objectMap(item)['valid']! as bool,
      ),
  ];
}

List<Object?> _objectList(Object? value) => value! as List<Object?>;

Map<String, Object?> _wireMap(Object? value) => _objectMap(value);

Map<String, Object?> _objectMap(Object? value) {
  final source = value! as Map<Object?, Object?>;
  return <String, Object?>{
    for (final entry in source.entries) entry.key! as String: entry.value,
  };
}

String _string(Object? value) => value! as String;

String _repeat(String value, int count) =>
    List<String>.filled(count, value, growable: false).join();
