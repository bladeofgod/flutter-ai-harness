import 'dart:async';

import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/jpeg_fixture.dart';

const String _exportHandle = 'ABCDEFGHIJKLMNOPQRSTUV';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(mediaCaptureCommandsChannel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  final session = MediaCaptureSession('session-1');
  final mediaHandle = MediaCaptureMediaHandle('media-1');
  final confirmedMedia = MediaCaptureConfirmedMedia(
    mediaHandle: mediaHandle,
    mediaType: MediaCaptureMediaType.photo,
    pixelWidth: 640,
    pixelHeight: 480,
    durationMillis: null,
    orientationDegrees: 0,
    byteLength: 1000,
    leaseExpiresAtMillis: 123456,
  );
  final exportHandle = MediaCaptureExportHandle(_exportHandle);
  final methodCases = <_MethodCase>[
    _MethodCase(
      method: methodStartSession,
      requestKeys: const <String>{
        'enabledMediaTypes',
        'preferredCamera',
        'audioEnabled',
        'maxVideoDurationMillis',
      },
      resultType: 'session_created',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.startSession(_config()),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureSession>>(),
    ),
    _MethodCase(
      method: methodTakePhoto,
      requestKeys: const <String>{'sessionHandle'},
      resultType: 'media_preview',
      resultPayload: _previewPayload(),
      invoke: (client) => client.takePhoto(session),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCapturePreview>>(),
    ),
    _MethodCase(
      method: methodStartRecording,
      requestKeys: const <String>{'sessionHandle'},
      resultType: 'recording_started',
      resultPayload: const <String, Object?>{
        'sessionHandle': 'session-1',
        'audioIncluded': true,
      },
      invoke: (client) => client.startRecording(session),
      resultMatcher:
          isA<MediaCaptureCallSuccess<MediaCaptureRecordingStarted>>(),
    ),
    _MethodCase(
      method: methodStopRecording,
      requestKeys: const <String>{'sessionHandle'},
      resultType: 'media_preview',
      resultPayload: _previewPayload(mediaType: 'video', durationMillis: 1000),
      invoke: (client) => client.stopRecording(session),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCapturePreview>>(),
    ),
    _MethodCase(
      method: methodSwitchCamera,
      requestKeys: const <String>{'sessionHandle'},
      resultType: 'control_applied',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.switchCamera(session),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureControlApplied>>(),
    ),
    _MethodCase(
      method: methodSetFlashMode,
      requestKeys: const <String>{'sessionHandle', 'flashMode'},
      resultType: 'control_applied',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.setFlashMode(
        session: session,
        flashMode: MediaCaptureFlashMode.auto,
      ),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureControlApplied>>(),
    ),
    _MethodCase(
      method: methodSetFocusPoint,
      requestKeys: const <String>{
        'sessionHandle',
        'normalizedX',
        'normalizedY',
      },
      resultType: 'control_applied',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.setFocusPoint(
        session: session,
        normalizedX: 0.25,
        normalizedY: 0.75,
      ),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureControlApplied>>(),
    ),
    _MethodCase(
      method: methodSetZoom,
      requestKeys: const <String>{'sessionHandle', 'zoomFactor'},
      resultType: 'control_applied',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.setZoom(session: session, zoomFactor: 2.0),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureControlApplied>>(),
    ),
    _MethodCase(
      method: methodRetake,
      requestKeys: const <String>{'mediaHandle'},
      resultType: 'retake_ready',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.retake(mediaHandle),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureRetakeReady>>(),
    ),
    _MethodCase(
      method: methodConfirm,
      requestKeys: const <String>{'mediaHandle'},
      resultType: 'confirmed_media',
      resultPayload: _confirmedMediaPayload(),
      invoke: (client) => client.confirm(mediaHandle),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureConfirmedMedia>>(),
    ),
    _MethodCase(
      method: methodCancel,
      requestKeys: const <String>{'sessionHandle'},
      resultType: 'session_cancelled',
      resultPayload: const <String, Object?>{'sessionHandle': 'session-1'},
      invoke: (client) => client.cancel(session),
      resultMatcher:
          isA<MediaCaptureCallSuccess<MediaCaptureSessionCancelled>>(),
    ),
    _MethodCase(
      method: methodReleaseMedia,
      requestKeys: const <String>{'mediaHandle'},
      resultType: 'media_released',
      resultPayload: const <String, Object?>{'mediaHandle': 'media-1'},
      invoke: (client) => client.releaseMedia(mediaHandle),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureMediaReleased>>(),
    ),
    _MethodCase(
      method: methodReadMediaThumbnail,
      requestKeys: const <String>{'mediaHandle', 'maxPixelEdge'},
      resultType: 'media_thumbnail',
      resultPayload: _thumbnailPayload(),
      invoke: (client) => client.readMediaThumbnail(
        MediaCaptureThumbnailRequest(
          mediaHandle: mediaHandle,
          maxPixelEdge: 128,
        ),
      ),
      resultMatcher: isA<MediaCaptureCallSuccess<MediaCaptureThumbnail>>(),
    ),
    _MethodCase(
      method: methodPresentCaptureFlow,
      requestKeys: const <String>{
        'enabledMediaTypes',
        'preferredCamera',
        'audioEnabled',
        'maxVideoDurationMillis',
      },
      resultType: 'capture_flow_confirmed',
      resultPayload: _confirmedMediaPayload(),
      invoke: (client) => client.presentCaptureFlow(_config()),
      resultMatcher: isA<MediaCaptureFlowConfirmed>(),
    ),
    _MethodCase(
      method: methodMaterializeMediaResource,
      requestKeys: const <String>{'mediaHandle'},
      resultType: 'materialized_media_resource',
      resultPayload: _materializedMediaPayload(),
      invoke: (client) => client.materializeMedia(confirmedMedia),
      resultMatcher:
          isA<MediaCaptureCallSuccess<MediaCaptureMaterializedMedia>>(),
    ),
    _MethodCase(
      method: methodReleaseMaterializedMedia,
      requestKeys: const <String>{'exportHandle'},
      resultType: 'materialized_media_released',
      resultPayload: const <String, Object?>{},
      invoke: (client) => client.releaseMaterializedMedia(exportHandle),
      resultMatcher:
          isA<MediaCaptureCallSuccess<MediaCaptureMaterializedMediaReleased>>(),
    ),
  ];

  group('all method success contracts', () {
    for (final methodCase in methodCases) {
      test('${methodCase.method} decodes its exact success result', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              expect(call.method, methodCase.method);
              final envelope = _wireMap(call.arguments);
              expect(
                envelope.keys,
                unorderedEquals(<String>{
                  'wireVersion',
                  'requestId',
                  'payload',
                }),
              );
              final payload = _wireMap(envelope['payload']);
              expect(payload.keys, unorderedEquals(methodCase.requestKeys));
              return _resultEnvelope(
                requestId: _string(envelope['requestId']),
                resultType: methodCase.resultType,
                payload: methodCase.resultPayload,
              );
            });
        final client = _client();

        final result = await methodCase.invoke(client);

        expect(result, methodCase.resultMatcher);
        await client.dispose();
      });
    }

    test('present_capture_flow decodes the cancelled success result', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            final envelope = _wireMap(call.arguments);
            return _resultEnvelope(
              requestId: _string(envelope['requestId']),
              resultType: 'capture_flow_cancelled',
              payload: const <String, Object?>{},
            );
          });
      final client = _client();

      expect(
        await client.presentCaptureFlow(_config()),
        isA<MediaCaptureFlowCancelled>(),
      );
      await client.dispose();
    });

    test(
      'dismisses only the presentation request owned by this client',
      () async {
        final presentationResult = Completer<Object?>();
        String? presentationRequestId;
        var requestIndex = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              final envelope = _wireMap(call.arguments);
              final requestId = _string(envelope['requestId']);
              if (call.method == methodPresentCaptureFlow) {
                presentationRequestId = requestId;
                return presentationResult.future;
              }
              expect(call.method, methodDismissCaptureFlow);
              expect(_wireMap(envelope['payload']), <String, Object?>{
                'presentationRequestId': presentationRequestId,
              });
              presentationResult.complete(
                _resultEnvelope(
                  requestId: presentationRequestId!,
                  resultType: 'capture_flow_cancelled',
                  payload: const <String, Object?>{},
                ),
              );
              return _resultEnvelope(
                requestId: requestId,
                resultType: 'capture_flow_dismissed',
                payload: const <String, Object?>{},
              );
            });
        final client = MediaCaptureClient(
          requestIdFactory: () => 'dismiss-${++requestIndex}',
        );

        final presentation = client.presentCaptureFlow(_config());
        await Future<void>.delayed(Duration.zero);

        expect(await client.dismissActivePresentation(), isTrue);
        expect(await presentation, isA<MediaCaptureFlowCancelled>());
        expect(await client.dismissActivePresentation(), isTrue);
        await client.dispose();
      },
    );

    test(
      'a concurrent presentation cannot replace the active dismiss target',
      () async {
        final presentationResult = Completer<Object?>();
        String? presentationRequestId;
        var requestIndex = 0;
        var presentationCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              final envelope = _wireMap(call.arguments);
              final requestId = _string(envelope['requestId']);
              if (call.method == methodPresentCaptureFlow) {
                presentationCalls += 1;
                presentationRequestId = requestId;
                return presentationResult.future;
              }
              expect(call.method, methodDismissCaptureFlow);
              expect(_wireMap(envelope['payload']), <String, Object?>{
                'presentationRequestId': presentationRequestId,
              });
              presentationResult.complete(
                _resultEnvelope(
                  requestId: presentationRequestId!,
                  resultType: 'capture_flow_cancelled',
                  payload: const <String, Object?>{},
                ),
              );
              return _resultEnvelope(
                requestId: requestId,
                resultType: 'capture_flow_dismissed',
                payload: const <String, Object?>{},
              );
            });
        final client = MediaCaptureClient(
          requestIdFactory: () => 'concurrent-${++requestIndex}',
        );

        final first = client.presentCaptureFlow(_config());
        await Future<void>.delayed(Duration.zero);
        final second = await client.presentCaptureFlow(_config());

        expect(presentationCalls, 1);
        expect(second, isA<MediaCaptureFlowFailure>());
        final failure = (second as MediaCaptureFlowFailure).failure;
        expect(failure.code, MediaCaptureFailureCode.presentationConflict);
        expect(
          failure.diagnostics.capacity,
          MediaCaptureCapacity.activePresentation,
        );
        expect(await client.dismissActivePresentation(), isTrue);
        expect(await first, isA<MediaCaptureFlowCancelled>());
        await client.dispose();
      },
    );

    test('dispose takes precedence over presentation conflict', () async {
      final presentationResult = Completer<Object?>();
      String? presentationRequestId;
      var requestIndex = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            final envelope = _wireMap(call.arguments);
            final requestId = _string(envelope['requestId']);
            if (call.method == methodPresentCaptureFlow) {
              presentationRequestId = requestId;
              return presentationResult.future;
            }
            presentationResult.complete(
              _resultEnvelope(
                requestId: presentationRequestId!,
                resultType: 'capture_flow_cancelled',
                payload: const <String, Object?>{},
              ),
            );
            return _resultEnvelope(
              requestId: requestId,
              resultType: 'capture_flow_dismissed',
              payload: const <String, Object?>{},
            );
          });
      final client = MediaCaptureClient(
        requestIdFactory: () => 'dispose-priority-${++requestIndex}',
      );

      final first = client.presentCaptureFlow(_config());
      await Future<void>.delayed(Duration.zero);
      final disposal = client.dispose();
      final second = await client.presentCaptureFlow(_config());

      expect(second, isA<MediaCaptureFlowFailure>());
      expect(
        (second as MediaCaptureFlowFailure).failure.code,
        MediaCaptureFailureCode.bridgeUnavailable,
      );
      final firstAfterDispose = await first;
      expect(firstAfterDispose, isA<MediaCaptureFlowFailure>());
      expect(
        (firstAfterDispose as MediaCaptureFlowFailure).failure.code,
        MediaCaptureFailureCode.bridgeUnavailable,
      );
      await disposal;
    });
  });

  group('resource identity correlation', () {
    final mismatches = <String, Map<String, Object?>>{
      methodStartRecording: const <String, Object?>{
        'sessionHandle': 'session-other',
        'audioIncluded': true,
      },
      methodSwitchCamera: const <String, Object?>{
        'sessionHandle': 'session-other',
      },
      methodConfirm: <String, Object?>{
        ..._confirmedMediaPayload(),
        'mediaHandle': 'media-other',
      },
      methodCancel: const <String, Object?>{'sessionHandle': 'session-other'},
      methodReleaseMedia: const <String, Object?>{'mediaHandle': 'media-other'},
      methodReadMediaThumbnail: <String, Object?>{
        ..._thumbnailPayload(),
        'mediaHandle': 'media-other',
      },
    };

    for (final entry in mismatches.entries) {
      test('${entry.key} rejects a result for another resource', () async {
        final methodCase = methodCases.firstWhere(
          (item) => item.method == entry.key,
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              final request = _wireMap(call.arguments);
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: methodCase.resultType,
                payload: entry.value,
              );
            });
        final client = _client();

        final result = await methodCase.invoke(client);

        expect(result, isA<MediaCaptureCallFailure<Object?>>());
        expect(
          (result as MediaCaptureCallFailure<Object?>).failure.code,
          MediaCaptureFailureCode.invalidWirePayload,
        );
        await client.dispose();
      });
    }
  });

  group('dispose draining', () {
    final resourceCases = <_MethodCase>[
      methodCases.firstWhere((item) => item.method == methodStartSession),
      methodCases.firstWhere((item) => item.method == methodConfirm),
      methodCases.firstWhere((item) => item.method == methodPresentCaptureFlow),
    ];

    for (final methodCase in resourceCases) {
      test(
        'settles the late $methodCase resource before dispose completes',
        () async {
          final nativeResult = Completer<Object?>();
          String? requestId;
          String? cleanupMethod;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(methodChannel, (call) {
                final request = _wireMap(call.arguments);
                final currentRequestId = _string(request['requestId']);
                if (call.method == methodCase.method) {
                  requestId = currentRequestId;
                  return nativeResult.future;
                }
                cleanupMethod = call.method;
                if (call.method == methodDismissCaptureFlow) {
                  return Future<Object?>.value(
                    _resultEnvelope(
                      requestId: currentRequestId,
                      resultType: 'capture_flow_dismissed',
                      payload: const <String, Object?>{},
                    ),
                  );
                }
                if (call.method == methodCancel) {
                  return Future<Object?>.value(
                    _resultEnvelope(
                      requestId: currentRequestId,
                      resultType: 'session_cancelled',
                      payload: const <String, Object?>{
                        'sessionHandle': 'session-1',
                      },
                    ),
                  );
                }
                if (call.method == methodReleaseMedia) {
                  return Future<Object?>.value(
                    _resultEnvelope(
                      requestId: currentRequestId,
                      resultType: 'media_released',
                      payload: const <String, Object?>{
                        'mediaHandle': 'media-1',
                      },
                    ),
                  );
                }
                fail('Unexpected cleanup method ${call.method}');
              });
          final client = _client();

          final pending = methodCase.invoke(client);
          var disposeCompleted = false;
          final disposing = client.dispose().then(
            (_) => disposeCompleted = true,
          );
          await Future<void>.delayed(Duration.zero);
          expect(disposeCompleted, isFalse);
          nativeResult.complete(
            _resultEnvelope(
              requestId: requestId!,
              resultType: methodCase.resultType,
              payload: methodCase.resultPayload,
            ),
          );

          final result = await pending;
          expect(
            result,
            methodCase.method == methodPresentCaptureFlow
                ? isA<MediaCaptureFlowFailure>()
                : isA<MediaCaptureCallFailure<Object?>>(),
          );
          await disposing;
          expect(disposeCompleted, isTrue);
          expect(
            cleanupMethod,
            methodCase.method == methodStartSession
                ? methodCancel
                : methodReleaseMedia,
          );
          await client.dispose();
        },
      );
    }

    test('retries malformed and failed cleanup acknowledgements', () async {
      final nativeResult = Completer<Object?>();
      String? requestId;
      var cleanupCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) {
            final request = _wireMap(call.arguments);
            final currentRequestId = _string(request['requestId']);
            if (call.method == methodStartSession) {
              requestId = currentRequestId;
              return nativeResult.future;
            }
            expect(call.method, methodCancel);
            cleanupCalls += 1;
            return switch (cleanupCalls) {
              1 => Future<Object?>.error(
                PlatformException(code: 'system_interrupted'),
              ),
              2 => Future<Object?>.value(<String, Object?>{'malformed': true}),
              3 => Future<Object?>.value(
                _resultEnvelope(
                  requestId: currentRequestId,
                  resultType: 'session_cancelled',
                  payload: const <String, Object?>{
                    'sessionHandle': 'wrong-session',
                  },
                ),
              ),
              _ => Future<Object?>.value(
                _resultEnvelope(
                  requestId: currentRequestId,
                  resultType: 'session_cancelled',
                  payload: const <String, Object?>{
                    'sessionHandle': 'session-1',
                  },
                ),
              ),
            };
          });
      final client = _client();

      final pending = client.startSession(_config());
      await Future<void>.delayed(Duration.zero);
      final disposing = client.dispose();
      nativeResult.complete(
        _resultEnvelope(
          requestId: requestId!,
          resultType: 'session_created',
          payload: const <String, Object?>{'sessionHandle': 'session-1'},
        ),
      );

      expect(
        await pending,
        isA<MediaCaptureCallFailure<MediaCaptureSession>>(),
      );
      await disposing;
      expect(cleanupCalls, 4);
    });

    test(
      'failed disposal retains cleanup ownership for a later retry',
      () async {
        final nativeResult = Completer<Object?>();
        String? requestId;
        var cleanupCalls = 0;
        var allowCleanup = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) {
              final request = _wireMap(call.arguments);
              final currentRequestId = _string(request['requestId']);
              if (call.method == methodConfirm) {
                requestId = currentRequestId;
                return nativeResult.future;
              }
              expect(call.method, methodReleaseMedia);
              cleanupCalls += 1;
              if (!allowCleanup) {
                return Future<Object?>.error(
                  PlatformException(code: 'system_interrupted'),
                );
              }
              return Future<Object?>.value(
                _resultEnvelope(
                  requestId: currentRequestId,
                  resultType: 'media_released',
                  payload: const <String, Object?>{'mediaHandle': 'media-1'},
                ),
              );
            });
        final client = _client();

        final pending = client.confirm(MediaCaptureMediaHandle('media-1'));
        await Future<void>.delayed(Duration.zero);
        final firstDispose = expectLater(
          client.dispose(),
          throwsA(isA<MediaCaptureDisposalException>()),
        );
        nativeResult.complete(
          _resultEnvelope(
            requestId: requestId!,
            resultType: 'confirmed_media',
            payload: _confirmedMediaPayload(),
          ),
        );

        expect(
          await pending,
          isA<MediaCaptureCallFailure<MediaCaptureConfirmedMedia>>(),
        );
        await firstDispose;
        expect(cleanupCalls, 4);

        allowCleanup = true;
        await client.dispose();
        expect(cleanupCalls, 5);
      },
    );
  });

  test('public client surface remains fully typed', () {
    final client = _client();
    final Future<MediaCaptureCallResult<MediaCaptureSession>> Function(
      MediaCaptureConfig,
    )
    startSession = client.startSession;
    final Future<MediaCaptureCallResult<MediaCaptureThumbnail>> Function(
      MediaCaptureThumbnailRequest,
    )
    readThumbnail = client.readMediaThumbnail;
    final Future<MediaCaptureFlowOutcome> Function(MediaCaptureConfig)
    presentFlow = client.presentCaptureFlow;
    final Stream<MediaCaptureEvent> Function() events = client.listenEvents;
    final Future<void> Function() dispose = client.dispose;

    expect(startSession, isNotNull);
    expect(readThumbnail, isNotNull);
    expect(presentFlow, isNotNull);
    expect(events, isNotNull);
    expect(dispose, isNotNull);
  });
}

final class _MethodCase {
  const _MethodCase({
    required this.method,
    required this.requestKeys,
    required this.resultType,
    required this.resultPayload,
    required this.invoke,
    required this.resultMatcher,
  });

  final String method;
  final Set<String> requestKeys;
  final String resultType;
  final Map<String, Object?> resultPayload;
  final Future<Object?> Function(MediaCaptureClient client) invoke;
  final Matcher resultMatcher;

  @override
  String toString() => method;
}

MediaCaptureConfig _config() {
  return MediaCaptureConfig(
    enabledMediaTypes: <MediaCaptureMediaType>{MediaCaptureMediaType.photo},
    preferredCamera: MediaCaptureCamera.rear,
    audioEnabled: false,
    maxVideoDurationMillis: 30000,
  );
}

MediaCaptureClient _client() => MediaCaptureClient(epochMillis: () => 1000);

Map<String, Object?> _resultEnvelope({
  required String requestId,
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

Map<String, Object?> _previewPayload({
  String mediaType = 'photo',
  int? durationMillis,
}) {
  return <String, Object?>{
    'mediaHandle': 'media-1',
    'mediaType': mediaType,
    'pixelWidth': 640,
    'pixelHeight': 480,
    'durationMillis': durationMillis,
    'orientationDegrees': 0,
    'byteLength': 1000,
  };
}

Map<String, Object?> _confirmedMediaPayload() {
  return <String, Object?>{..._previewPayload(), 'leaseExpiresAt': 123456};
}

Map<String, Object?> _materializedMediaPayload() {
  return const <String, Object?>{
    'exportHandle': _exportHandle,
    'fileUri': 'file:///data/user/0/app/cache/media-transfer/a.jpg',
    'mediaType': 'photo',
    'contentType': 'image/jpeg',
    'byteLength': 1000,
    'durationMillis': null,
    'expiresAt': 301000,
  };
}

Map<String, Object?> _thumbnailPayload() {
  final bytes = validSanitizedJpeg();
  return <String, Object?>{
    'mediaHandle': 'media-1',
    'thumbnailCopy': bytes,
    'thumbnailByteLength': bytes.length,
    'thumbnailPixelWidth': 1,
    'thumbnailPixelHeight': 1,
    'thumbnailContentType': 'image/jpeg',
    'thumbnailOrientationDegrees': 0,
    'mediaType': 'photo',
    'posterFrameMillis': null,
  };
}

Map<String, Object?> _wireMap(Object? value) {
  expect(value, isA<Map<Object?, Object?>>());
  final source = value! as Map<Object?, Object?>;
  return <String, Object?>{
    for (final entry in source.entries) entry.key! as String: entry.value,
  };
}

String _string(Object? value) {
  expect(value, isA<String>());
  return value! as String;
}
