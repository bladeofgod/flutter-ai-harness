import 'dart:async';
import 'dart:collection';

import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:app_media_capture_bridge/src/media_capture_wire_codec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/jpeg_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(mediaCaptureCommandsChannel);
  const eventChannel = EventChannel(mediaCaptureEventsChannel);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  group('MethodChannel client', () {
    test('sends a strict request envelope with a secure requestId', () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (methodCall) async {
            call = methodCall;
            final request = _wireMap(methodCall.arguments);
            return _resultEnvelope(
              requestId: _string(request['requestId']),
              resultType: 'session_created',
              payload: <String, Object?>{'sessionHandle': 'session-1'},
            );
          });

      final client = MediaCaptureClient();
      final result = await client.startSession(_config());

      expect(call?.method, methodStartSession);
      final request = _wireMap(call?.arguments);
      expect(
        request.keys,
        unorderedEquals(<String>['wireVersion', 'requestId', 'payload']),
      );
      expect(request['wireVersion'], mediaCaptureWireVersion);
      expect(
        _string(request['requestId']),
        matches(RegExp(r'^[A-Za-z0-9_-]{1,128}$')),
      );
      expect(result, isA<MediaCaptureCallSuccess<MediaCaptureSession>>());
      expect(
        (result as MediaCaptureCallSuccess<MediaCaptureSession>).value.handle,
        'session-1',
      );
    });

    test(
      'exposes direct operation PlatformException as typed failure',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) async {
              throw PlatformException(
                code: 'invalid_state',
                message: 'raw message must not be surfaced',
                details: <String, Object?>{
                  'operation': 'take_photo',
                  'capabilityFailureId': 'invalid_state',
                },
              );
            });

        final client = MediaCaptureClient();
        final result = await client.takePhoto(MediaCaptureSession('session-1'));

        expect(result, isA<MediaCaptureCallFailure<MediaCapturePreview>>());
        final failure =
            (result as MediaCaptureCallFailure<MediaCapturePreview>).failure;
        expect(failure.code, MediaCaptureFailureCode.invalidState);
        expect(failure.diagnostics.operation, MediaCaptureOperation.takePhoto);
        expect(failure.toString(), isNot(contains('raw message')));
      },
    );

    test('rejects malicious PlatformException details', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (methodCall) async {
            throw PlatformException(
              code: 'invalid_state',
              message: 'handle=session-secret',
              details: <String, Object?>{
                'operation': 'take_photo',
                'sessionHandle': 'session-secret',
              },
            );
          });

      final client = MediaCaptureClient();
      final result = await client.takePhoto(MediaCaptureSession('session-1'));
      final failure =
          (result as MediaCaptureCallFailure<MediaCapturePreview>).failure;

      expect(failure.code, MediaCaptureFailureCode.invalidWirePayload);
      expect(failure.toString(), isNot(contains('session-secret')));
    });

    test(
      'presentCaptureFlow returns the three closed terminal outcomes',
      () async {
        final responses = Queue<Object?>()
          ..add(
            _resultEnvelope(
              requestId: 'flow-1',
              resultType: 'capture_flow_confirmed',
              payload: _confirmedMediaPayload(),
            ),
          )
          ..add(
            _resultEnvelope(
              requestId: 'flow-2',
              resultType: 'capture_flow_cancelled',
              payload: <String, Object?>{},
            ),
          )
          ..add(
            PlatformException(
              code: 'presentation_conflict',
              details: <String, Object?>{
                'operation': 'present_capture_flow',
                'capacity': 'active_presentation',
              },
            ),
          );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) async {
              final response = responses.removeFirst();
              if (response is PlatformException) {
                throw response;
              }
              return response;
            });
        final client = MediaCaptureClient(
          requestIdFactory: _sequence(<String>['flow-1', 'flow-2', 'flow-3']),
        );

        expect(
          await client.presentCaptureFlow(_config()),
          isA<MediaCaptureFlowConfirmed>(),
        );
        expect(
          await client.presentCaptureFlow(_config()),
          isA<MediaCaptureFlowCancelled>(),
        );
        final failure = await client.presentCaptureFlow(_config());
        expect(failure, isA<MediaCaptureFlowFailure>());
        expect(
          (failure as MediaCaptureFlowFailure).failure.code,
          MediaCaptureFailureCode.presentationConflict,
        );
      },
    );

    test(
      'validates bounded thumbnail bytes and returns a defensive copy',
      () async {
        final bytes = validSanitizedJpeg();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) async {
              final request = _wireMap(methodCall.arguments);
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'media_thumbnail',
                payload: _thumbnailPayload(bytes: bytes),
              );
            });
        final client = MediaCaptureClient();

        final result = await client.readMediaThumbnail(
          MediaCaptureThumbnailRequest(
            mediaHandle: MediaCaptureMediaHandle('media-1'),
            maxPixelEdge: 128,
          ),
        );

        final thumbnail =
            (result as MediaCaptureCallSuccess<MediaCaptureThumbnail>).value;
        final copy = thumbnail.bytes;
        copy[0] = 99;
        expect(thumbnail.bytes, bytes);
        expect(thumbnail.contentType, 'image/jpeg');
        expect(thumbnail.orientationDegrees, 0);
      },
    );

    test('settles pending preview before completing dispose', () async {
      final nativeCompleter = Completer<Object?>();
      String? requestId;
      var cancelCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (methodCall) {
            final request = _wireMap(methodCall.arguments);
            final currentRequestId = _string(request['requestId']);
            if (methodCall.method == methodTakePhoto) {
              requestId = currentRequestId;
              return nativeCompleter.future;
            }
            expect(methodCall.method, methodCancel);
            cancelCount += 1;
            return Future<Object?>.value(
              _resultEnvelope(
                requestId: currentRequestId,
                resultType: 'session_cancelled',
                payload: <String, Object?>{'sessionHandle': 'session-1'},
              ),
            );
          });
      final client = MediaCaptureClient();

      final pending = client.takePhoto(MediaCaptureSession('session-1'));
      var disposeCompleted = false;
      final disposing = client.dispose().then((_) => disposeCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposeCompleted, isFalse);
      final rejected = await client.takePhoto(MediaCaptureSession('session-1'));
      expect(rejected, isA<MediaCaptureCallFailure<MediaCapturePreview>>());
      nativeCompleter.complete(
        _resultEnvelope(
          requestId: requestId!,
          resultType: 'media_preview',
          payload: _previewPayload(),
        ),
      );
      final result = await pending;

      expect(result, isA<MediaCaptureCallFailure<MediaCapturePreview>>());
      await disposing;
      expect(disposeCompleted, isTrue);
      expect(cancelCount, 1);
      await client.dispose();
    });

    test(
      'rejects duplicate pending and completed requestIds locally',
      () async {
        final nativeResult = Completer<Object?>();
        var nativeCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) {
              nativeCalls += 1;
              return nativeResult.future;
            });
        final client = MediaCaptureClient(
          requestIdFactory: () => 'duplicate-1',
        );

        final first = client.startSession(_config());
        final pendingDuplicate = await client.startSession(_config());

        expect(nativeCalls, 1);
        expect(
          (pendingDuplicate as MediaCaptureCallFailure<MediaCaptureSession>)
              .failure
              .code,
          MediaCaptureFailureCode.duplicateRequest,
        );

        nativeResult.complete(
          _resultEnvelope(
            requestId: 'duplicate-1',
            resultType: 'session_created',
            payload: <String, Object?>{'sessionHandle': 'session-1'},
          ),
        );
        expect(
          await first,
          isA<MediaCaptureCallSuccess<MediaCaptureSession>>(),
        );

        final completedDuplicate = await client.startSession(_config());
        expect(nativeCalls, 1);
        expect(
          (completedDuplicate as MediaCaptureCallFailure<MediaCaptureSession>)
              .failure
              .code,
          MediaCaptureFailureCode.duplicateRequest,
        );
        await client.dispose();
      },
    );

    test(
      'allows requestId reuse only after the 300 second tombstone',
      () async {
        var now = 0;
        var nativeCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) async {
              nativeCalls += 1;
              final request = _wireMap(methodCall.arguments);
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'session_created',
                payload: <String, Object?>{'sessionHandle': 'session-1'},
              );
            });
        final client = MediaCaptureClient(
          requestIdFactory: () => 'reusable-1',
          monotonicMillis: () => now,
        );

        expect(
          await client.startSession(_config()),
          isA<MediaCaptureCallSuccess<MediaCaptureSession>>(),
        );
        expect(
          await client.startSession(_config()),
          isA<MediaCaptureCallFailure<MediaCaptureSession>>(),
        );

        now = 300000;

        expect(
          await client.startSession(_config()),
          isA<MediaCaptureCallSuccess<MediaCaptureSession>>(),
        );
        expect(nativeCalls, 2);
        await client.dispose();
      },
    );

    test(
      'reserves at most 32 pending requests before native invocation',
      () async {
        var nextRequestId = 0;
        final nativeResults = <(String, Completer<Object?>)>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) {
              final requestId = _string(
                _wireMap(methodCall.arguments)['requestId'],
              );
              final result = Completer<Object?>();
              nativeResults.add((requestId, result));
              return result.future;
            });
        final client = MediaCaptureClient(
          requestIdFactory: () => 'pending-${nextRequestId++}',
        );

        final pending =
            List<Future<MediaCaptureCallResult<MediaCaptureSession>>>.generate(
              32,
              (_) => client.startSession(_config()),
            );
        final overloaded = await client.startSession(_config());

        expect(nativeResults, hasLength(32));
        final failure =
            (overloaded as MediaCaptureCallFailure<MediaCaptureSession>)
                .failure;
        expect(failure.code, MediaCaptureFailureCode.bridgeOverloaded);
        expect(
          failure.diagnostics.capacity,
          MediaCaptureCapacity.pendingRequests,
        );

        for (final (requestId, result) in nativeResults) {
          result.complete(
            _resultEnvelope(
              requestId: requestId,
              resultType: 'session_created',
              payload: <String, Object?>{'sessionHandle': 'session-1'},
            ),
          );
        }
        await Future.wait(pending);
        await client.dispose();
      },
    );

    test(
      'does not evict completed tombstones before capacity is full',
      () async {
        var nextRequestId = 0;
        var nativeCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (methodCall) async {
              nativeCalls += 1;
              final request = _wireMap(methodCall.arguments);
              return _resultEnvelope(
                requestId: _string(request['requestId']),
                resultType: 'session_created',
                payload: <String, Object?>{'sessionHandle': 'session-1'},
              );
            });
        final client = MediaCaptureClient(
          requestIdFactory: () => 'completed-${nextRequestId++}',
          monotonicMillis: () => 0,
        );

        for (var index = 0; index < 4096; index += 1) {
          expect(
            await client.startSession(_config()),
            isA<MediaCaptureCallSuccess<MediaCaptureSession>>(),
          );
        }
        final overloaded = await client.startSession(_config());

        expect(nativeCalls, 4096);
        final failure =
            (overloaded as MediaCaptureCallFailure<MediaCaptureSession>)
                .failure;
        expect(failure.code, MediaCaptureFailureCode.bridgeOverloaded);
        expect(
          failure.diagnostics.capacity,
          MediaCaptureCapacity.completedRequestTombstones,
        );
        await client.dispose();
      },
    );

    test('normalizes oversized platform envelopes before decoding', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            methodChannel,
            (_) async => Uint8List(600 * 1024),
          );
      final client = MediaCaptureClient();

      final result = await client.startSession(_config());

      expect(result, isA<MediaCaptureCallFailure<MediaCaptureSession>>());
      expect(
        (result as MediaCaptureCallFailure<MediaCaptureSession>).failure.code,
        MediaCaptureFailureCode.invalidWirePayload,
      );
      await client.dispose();
    });

    testWidgets('dispose is bounded when native never completes a request', (
      tester,
    ) async {
      final never = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (_) => never.future);
      final client = MediaCaptureClient();

      unawaited(client.startSession(_config()));
      final disposing = expectLater(
        client.dispose(),
        throwsA(isA<MediaCaptureDisposalException>()),
      );
      await tester.pump(const Duration(seconds: 5));
      await disposing;

      expect(
        await client.startSession(_config()),
        isA<MediaCaptureCallFailure<MediaCaptureSession>>(),
      );
    });
  });

  group('strict codec', () {
    final malformedCases = <String, Object?>{
      'non map envelope': 7,
      'unknown envelope field': <String, Object?>{
        ..._resultEnvelope(
          requestId: 'r1',
          resultType: 'media_preview',
          payload: _previewPayload(),
        ),
        'extra': true,
      },
      'missing payload': <String, Object?>{
        'wireVersion': mediaCaptureWireVersion,
        'requestId': 'r1',
        'resultType': 'media_preview',
      },
      'wrong version': _resultEnvelope(
        wireVersion: 1,
        requestId: 'r1',
        resultType: 'media_preview',
        payload: _previewPayload(),
      ),
      'result type mismatch': _resultEnvelope(
        requestId: 'r1',
        resultType: 'control_applied',
        payload: <String, Object?>{'sessionHandle': 'session-1'},
      ),
      'oversized handle': _resultEnvelope(
        requestId: 'r1',
        resultType: 'media_preview',
        payload: _previewPayload(
          mediaHandle: List<String>.filled(129, 'x').join(),
        ),
      ),
      'integer overflow encoded as a string': _resultEnvelope(
        requestId: 'r1',
        resultType: 'media_preview',
        payload: <String, Object?>{
          ..._previewPayload(),
          'byteLength': '9223372036854775808',
        },
      ),
      'photo duration present': _resultEnvelope(
        requestId: 'r1',
        resultType: 'media_preview',
        payload: _previewPayload(durationMillis: 1),
      ),
    };

    for (final entry in malformedCases.entries) {
      test('normalizes ${entry.key}', () {
        const codec = MediaCaptureWireCodec();

        final result = codec.decodeMediaPreview(
          entry.value,
          requestId: 'r1',
          operation: methodTakePhoto,
        );

        expect(result, isA<MediaCaptureCallFailure<MediaCapturePreview>>());
        expect(
          (result as MediaCaptureCallFailure<MediaCapturePreview>).failure.code,
          MediaCaptureFailureCode.invalidWirePayload,
        );
      });
    }

    test('rejects malformed thumbnail metadata', () {
      const codec = MediaCaptureWireCodec();
      final result = codec.decodeThumbnail(
        _resultEnvelope(
          requestId: 'thumb-1',
          resultType: 'media_thumbnail',
          payload: _thumbnailPayload(
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            thumbnailByteLength: 2,
          ),
        ),
        requestId: 'thumb-1',
        operation: methodReadMediaThumbnail,
        expectedMediaHandle: 'media-1',
        maxPixelEdge: 128,
      );

      expect(result, isA<MediaCaptureCallFailure<MediaCaptureThumbnail>>());
    });

    test('rejects JPEG metadata segments even when MIME is image/jpeg', () {
      const codec = MediaCaptureWireCodec();
      final result = codec.decodeThumbnail(
        _resultEnvelope(
          requestId: 'thumb-exif',
          resultType: 'media_thumbnail',
          payload: _thumbnailPayload(bytes: jpegWithExifSegment()),
        ),
        requestId: 'thumb-exif',
        operation: methodReadMediaThumbnail,
        expectedMediaHandle: 'media-1',
        maxPixelEdge: 128,
      );

      expect(result, isA<MediaCaptureCallFailure<MediaCaptureThumbnail>>());
      expect(
        (result as MediaCaptureCallFailure<MediaCaptureThumbnail>)
            .failure
            .diagnostics
            .field,
        MediaCaptureFailureField.thumbnailCopy,
      );
    });

    test('normalizes malformed events into failure events', () {
      const codec = MediaCaptureWireCodec();

      final event = codec.decodeEvent(<String, Object?>{
        'wireVersion': mediaCaptureWireVersion,
        'eventType': 'session_ready',
        'payload': <String, Object?>{
          'sessionHandle': 'session-1',
          'activeCamera': 'rear',
          'availableCameras': <String>['rear'],
          'switchCameraSupported': true,
          'supportedFlashModes': <String>['off'],
          'focusPointSupported': true,
          'minZoomFactor': double.nan,
          'maxZoomFactor': 2.0,
        },
      });

      expect(event, isA<MediaCaptureBridgeFailureEvent>());
      expect(
        (event as MediaCaptureBridgeFailureEvent).failure.code,
        MediaCaptureFailureCode.invalidWirePayload,
      );
    });
  });

  group('EventChannel client', () {
    test(
      'does not claim the native listener until the stream is listened',
      () async {
        var listenCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              eventChannel,
              MockStreamHandler.inline(
                onListen: (arguments, events) {
                  listenCount += 1;
                },
              ),
            );
        final client = MediaCaptureClient();

        final stream = client.listenEvents();
        await Future<void>.delayed(Duration.zero);
        expect(listenCount, 0);

        final subscription = stream.listen(null);
        await Future<void>.delayed(Duration.zero);
        expect(listenCount, 1);
        await subscription.cancel();
        await client.dispose();
      },
    );

    test(
      'uses listen envelope, emits events, and allows relisten after cancel',
      () async {
        Object? lastListenArguments;
        late MockStreamHandlerEventSink sink;
        int cancelCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              eventChannel,
              MockStreamHandler.inline(
                onListen: (arguments, events) {
                  lastListenArguments = arguments;
                  sink = events;
                },
                onCancel: (arguments) {
                  cancelCount += 1;
                },
              ),
            );
        final client = MediaCaptureClient();

        final firstEvent = Completer<MediaCaptureEvent>();
        final subscription = client.listenEvents().listen((event) {
          if (!firstEvent.isCompleted) {
            firstEvent.complete(event);
          }
        });
        await Future<void>.delayed(Duration.zero);
        expect(lastListenArguments, <String, Object?>{
          'wireVersion': mediaCaptureWireVersion,
        });
        sink.success(<String, Object?>{
          'wireVersion': mediaCaptureWireVersion,
          'eventType': 'session_ready',
          'payload': <String, Object?>{
            'sessionHandle': 'session-1',
            'activeCamera': 'rear',
            'availableCameras': <String>['rear', 'front'],
            'switchCameraSupported': true,
            'supportedFlashModes': <String>['off', 'auto'],
            'focusPointSupported': true,
            'minZoomFactor': 1.0,
            'maxZoomFactor': 4.0,
          },
        });
        expect(await firstEvent.future, isA<MediaCaptureSessionReady>());
        await subscription.cancel();
        expect(cancelCount, 1);

        final second = client.listenEvents().listen(null);
        await Future<void>.delayed(Duration.zero);
        await second.cancel();
        expect(cancelCount, 2);
      },
    );

    test('rejects a second active listener and drops late events', () async {
      late MockStreamHandlerEventSink sink;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, events) {
                sink = events;
              },
            ),
          );
      final client = MediaCaptureClient();
      final received = <MediaCaptureEvent>[];
      final first = client.listenEvents().listen(received.add);
      await Future<void>.delayed(Duration.zero);

      final secondEvents = await client.listenEvents().toList();
      await first.cancel();
      sink.success(<String, Object?>{
        'wireVersion': mediaCaptureWireVersion,
        'eventType': 'media_lease_expired',
        'payload': <String, Object?>{'mediaHandle': 'media-1'},
      });
      await Future<void>.delayed(Duration.zero);

      expect(secondEvents.single, isA<MediaCaptureBridgeFailureEvent>());
      expect(received, isEmpty);
    });

    test('shares one listener slot across client instances', () async {
      late MockStreamHandlerEventSink sink;
      var listenCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, events) {
                listenCount += 1;
                sink = events;
              },
            ),
          );
      final firstClient = MediaCaptureClient();
      final secondClient = MediaCaptureClient();
      final firstEvent = Completer<MediaCaptureEvent>();
      final first = firstClient.listenEvents().listen(firstEvent.complete);
      await Future<void>.delayed(Duration.zero);

      final rejected = await secondClient.listenEvents().toList();
      sink.success(<String, Object?>{
        'wireVersion': mediaCaptureWireVersion,
        'eventType': 'media_lease_expired',
        'payload': <String, Object?>{'mediaHandle': 'media-1'},
      });

      expect(listenCount, 1);
      expect(rejected.single, isA<MediaCaptureBridgeFailureEvent>());
      expect(
        (rejected.single as MediaCaptureBridgeFailureEvent).failure.code,
        MediaCaptureFailureCode.listenerAlreadyActive,
      );
      expect(await firstEvent.future, isA<MediaCaptureLeaseExpired>());

      await first.cancel();
      await firstClient.dispose();
      await secondClient.dispose();
    });

    test('native done releases the slot and permits relisten', () async {
      final sinks = <MockStreamHandlerEventSink>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, events) {
                sinks.add(events);
              },
            ),
          );
      final client = MediaCaptureClient();
      final firstDone = Completer<void>();
      client.listenEvents().listen(null, onDone: firstDone.complete);
      await Future<void>.delayed(Duration.zero);

      sinks.single.endOfStream();
      await firstDone.future;
      final second = client.listenEvents().listen(null);
      await Future<void>.delayed(Duration.zero);

      expect(sinks, hasLength(2));
      await second.cancel();
      await client.dispose();
    });

    test(
      'native error emits one typed failure, closes, and permits relisten',
      () async {
        final sinks = <MockStreamHandlerEventSink>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              eventChannel,
              MockStreamHandler.inline(
                onListen: (arguments, events) {
                  sinks.add(events);
                },
              ),
            );
        final client = MediaCaptureClient();
        final received = <MediaCaptureEvent>[];
        final firstDone = Completer<void>();
        client.listenEvents().listen(received.add, onDone: firstDone.complete);
        await Future<void>.delayed(Duration.zero);

        sinks.single.error(
          code: 'wire_encoding_failed',
          details: <String, Object?>{
            'operation': 'unknown_operation',
            'field': 'payload',
            'reason': 'native_value_unencodable',
          },
        );
        await firstDone.future;

        expect(received, hasLength(1));
        final failureEvent = received.single as MediaCaptureBridgeFailureEvent;
        expect(
          failureEvent.failure.code,
          MediaCaptureFailureCode.wireEncodingFailed,
        );
        final second = client.listenEvents().listen(null);
        await Future<void>.delayed(Duration.zero);
        expect(sinks, hasLength(2));
        await second.cancel();
        await client.dispose();
      },
    );

    test('dispose cancels and closes the active listener', () async {
      var cancelCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, events) {},
              onCancel: (arguments) {
                cancelCount += 1;
              },
            ),
          );
      final client = MediaCaptureClient();
      final done = Completer<void>();
      client.listenEvents().listen(null, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);

      await client.dispose();

      await done.future;
      expect(cancelCount, 1);
      final afterDispose = await client.listenEvents().toList();
      expect(afterDispose.single, isA<MediaCaptureBridgeFailureEvent>());
      expect(
        (afterDispose.single as MediaCaptureBridgeFailureEvent).failure.code,
        MediaCaptureFailureCode.bridgeUnavailable,
      );
    });

    test(
      'an old cancel must finish before a new native listener can claim',
      () async {
        const eventMethodChannel = MethodChannel(mediaCaptureEventsChannel);
        final firstCancelGate = Completer<void>();
        var listenCount = 0;
        var cancelCount = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(eventMethodChannel, (call) async {
              if (call.method == 'listen') {
                listenCount += 1;
                return;
              }
              if (call.method == 'cancel') {
                cancelCount += 1;
                if (cancelCount == 1) {
                  await firstCancelGate.future;
                }
                return;
              }
              fail('Unexpected EventChannel method ${call.method}');
            });
        final client = MediaCaptureClient();
        final first = client.listenEvents().listen(null);
        await Future<void>.delayed(Duration.zero);

        final firstCancel = first.cancel();
        await Future<void>.delayed(Duration.zero);
        final whileCancellingFuture = client.listenEvents().toList();
        await Future<void>.delayed(Duration.zero);
        expect(listenCount, 1);

        firstCancelGate.complete();
        await firstCancel.timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              throw StateError('first native cancel did not finish'),
        );
        final whileCancelling = await whileCancellingFuture;
        expect(whileCancelling.single, isA<MediaCaptureBridgeFailureEvent>());
        expect(
          (whileCancelling.single as MediaCaptureBridgeFailureEvent)
              .failure
              .code,
          MediaCaptureFailureCode.listenerAlreadyActive,
        );
        final received = Completer<MediaCaptureEvent>();
        final second = client.listenEvents().listen(received.complete);
        await Future<void>.delayed(Duration.zero);
        expect(listenCount, 2);
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              mediaCaptureEventsChannel,
              const StandardMethodCodec().encodeSuccessEnvelope(
                <String, Object?>{
                  'wireVersion': mediaCaptureWireVersion,
                  'eventType': 'media_lease_expired',
                  'payload': <String, Object?>{'mediaHandle': 'media-1'},
                },
              ),
              null,
            );
        expect(
          await received.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError('new listener received no event'),
          ),
          isA<MediaCaptureLeaseExpired>(),
        );
        await second.cancel().timeout(
          const Duration(seconds: 2),
          onTimeout: () =>
              throw StateError('second native cancel did not finish'),
        );
        await client.dispose().timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('client dispose did not finish'),
        );
      },
    );
  });
}

MediaCaptureConfig _config() {
  return MediaCaptureConfig(
    enabledMediaTypes: <MediaCaptureMediaType>{MediaCaptureMediaType.photo},
    preferredCamera: MediaCaptureCamera.rear,
    audioEnabled: false,
    maxVideoDurationMillis: 30000,
  );
}

Map<String, Object?> _resultEnvelope({
  int wireVersion = mediaCaptureWireVersion,
  required String requestId,
  required String resultType,
  required Map<String, Object?> payload,
}) {
  return <String, Object?>{
    'wireVersion': wireVersion,
    'requestId': requestId,
    'resultType': resultType,
    'payload': payload,
  };
}

Map<String, Object?> _previewPayload({
  String mediaHandle = 'media-1',
  String mediaType = 'photo',
  int pixelWidth = 640,
  int pixelHeight = 480,
  int? durationMillis,
  int orientationDegrees = 0,
  int byteLength = 1000,
}) {
  return <String, Object?>{
    'mediaHandle': mediaHandle,
    'mediaType': mediaType,
    'pixelWidth': pixelWidth,
    'pixelHeight': pixelHeight,
    'durationMillis': durationMillis,
    'orientationDegrees': orientationDegrees,
    'byteLength': byteLength,
  };
}

Map<String, Object?> _confirmedMediaPayload() {
  return <String, Object?>{..._previewPayload(), 'leaseExpiresAt': 123456};
}

Map<String, Object?> _thumbnailPayload({
  required Uint8List bytes,
  int? thumbnailByteLength,
}) {
  return <String, Object?>{
    'mediaHandle': 'media-1',
    'thumbnailCopy': bytes,
    'thumbnailByteLength': thumbnailByteLength ?? bytes.length,
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

MediaCaptureRequestIdFactory _sequence(List<String> values) {
  var index = 0;
  return () => values[index++];
}
