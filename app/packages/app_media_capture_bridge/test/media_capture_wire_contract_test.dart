import 'package:app_media_capture_bridge/app_media_capture_bridge.dart';
import 'package:app_media_capture_bridge/src/media_capture_wire_codec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/jpeg_fixture.dart';

const Set<MediaCaptureFailureCode> _wireMethodErrors =
    <MediaCaptureFailureCode>{
      MediaCaptureFailureCode.incompatibleWireVersion,
      MediaCaptureFailureCode.invalidWirePayload,
      MediaCaptureFailureCode.duplicateRequest,
      MediaCaptureFailureCode.bridgeUnavailable,
      MediaCaptureFailureCode.bridgeOverloaded,
      MediaCaptureFailureCode.wireEncodingFailed,
    };

const Map<MediaCaptureOperation, Set<MediaCaptureFailureCode>>
_expectedMethodErrors = <MediaCaptureOperation, Set<MediaCaptureFailureCode>>{
  MediaCaptureOperation.startSession: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.sessionConflict,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.takePhoto: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.storageFull,
    MediaCaptureFailureCode.encodingFailed,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.startRecording: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.permissionDenied,
    MediaCaptureFailureCode.permissionRestricted,
    MediaCaptureFailureCode.permissionPermanentlyDenied,
    MediaCaptureFailureCode.resourceInUse,
    MediaCaptureFailureCode.storageFull,
    MediaCaptureFailureCode.encodingFailed,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.stopRecording: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.encodingFailed,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.switchCamera: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.resourceInUse,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.setFlashMode: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.setFocusPoint: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.setZoom: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.retake: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.confirm: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.cancel: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.releaseMedia: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.readMediaThumbnail: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.thumbnailGenerationFailed,
    MediaCaptureFailureCode.thumbnailGenerationCancelled,
    MediaCaptureFailureCode.thumbnailOverloaded,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.presentCaptureFlow: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.permissionDenied,
    MediaCaptureFailureCode.permissionRestricted,
    MediaCaptureFailureCode.permissionPermanentlyDenied,
    MediaCaptureFailureCode.resourceInUse,
    MediaCaptureFailureCode.storageFull,
    MediaCaptureFailureCode.encodingFailed,
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.sessionConflict,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.sessionTimeout,
    MediaCaptureFailureCode.presentationConflict,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.materializeMediaResource: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.mediaExportConflict,
    MediaCaptureFailureCode.mediaExportOverloaded,
    MediaCaptureFailureCode.mediaExportTooLarge,
    MediaCaptureFailureCode.mediaExportSinkRejected,
    MediaCaptureFailureCode.mediaExportReadFailed,
    MediaCaptureFailureCode.mediaExportWriteFailed,
    MediaCaptureFailureCode.mediaExportCancelled,
    MediaCaptureFailureCode.mediaExportTimedOut,
    MediaCaptureFailureCode.transferStoreOverloaded,
    MediaCaptureFailureCode.transferStoreUnavailable,
    ..._wireMethodErrors,
  },
  MediaCaptureOperation.releaseMaterializedMedia: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.materializedMediaInvalid,
    MediaCaptureFailureCode.transferStoreOverloaded,
    MediaCaptureFailureCode.transferStoreUnavailable,
    ..._wireMethodErrors,
  },
};

const Set<MediaCaptureFailureCode> _capabilityErrorCodes =
    <MediaCaptureFailureCode>{
      MediaCaptureFailureCode.permissionDenied,
      MediaCaptureFailureCode.permissionRestricted,
      MediaCaptureFailureCode.permissionPermanentlyDenied,
      MediaCaptureFailureCode.resourceInUse,
      MediaCaptureFailureCode.storageFull,
      MediaCaptureFailureCode.encodingFailed,
      MediaCaptureFailureCode.mediaInvalid,
      MediaCaptureFailureCode.sessionInvalid,
      MediaCaptureFailureCode.unsupportedCapability,
      MediaCaptureFailureCode.systemInterrupted,
      MediaCaptureFailureCode.sessionConflict,
      MediaCaptureFailureCode.invalidState,
      MediaCaptureFailureCode.invalidArgument,
      MediaCaptureFailureCode.sessionTimeout,
      MediaCaptureFailureCode.thumbnailGenerationFailed,
      MediaCaptureFailureCode.thumbnailGenerationCancelled,
      MediaCaptureFailureCode.thumbnailOverloaded,
      MediaCaptureFailureCode.mediaExportConflict,
      MediaCaptureFailureCode.mediaExportOverloaded,
      MediaCaptureFailureCode.mediaExportTooLarge,
      MediaCaptureFailureCode.mediaExportSinkRejected,
      MediaCaptureFailureCode.mediaExportReadFailed,
      MediaCaptureFailureCode.mediaExportWriteFailed,
      MediaCaptureFailureCode.mediaExportCancelled,
      MediaCaptureFailureCode.mediaExportTimedOut,
    };

void main() {
  const codec = MediaCaptureWireCodec();

  group('method PlatformException allowlists', () {
    test('matches every method-specific Wire errorCodes set', () {
      for (final entry in _expectedMethodErrors.entries) {
        for (final code in MediaCaptureFailureCode.values) {
          final failure = codec.platformExceptionToFailure(
            PlatformException(
              code: code.wireName,
              details: _errorDetails(code, entry.key),
            ),
            StackTrace.current,
            operation: entry.key,
          );
          final expected = entry.value.contains(code);
          expect(
            failure.code,
            expected ? code : MediaCaptureFailureCode.invalidWirePayload,
            reason: '${entry.key.wireName}/${code.wireName}',
          );
          if (!expected) {
            expect(
              failure.diagnostics.reason,
              MediaCaptureFailureReason.invalidEnum,
              reason: '${entry.key.wireName}/${code.wireName}',
            );
          }
        }
      }
    });

    test('requires details.operation to match the invoked method', () {
      final failure = codec.platformExceptionToFailure(
        PlatformException(
          code: 'invalid_state',
          details: const <String, Object?>{
            'operation': 'stop_recording',
            'capabilityFailureId': 'invalid_state',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.takePhoto,
      );

      expect(failure.code, MediaCaptureFailureCode.invalidWirePayload);
      expect(failure.diagnostics.reason, MediaCaptureFailureReason.invalidEnum);
    });

    test('uses an independent and matching Capability failure set', () {
      final valid = codec.platformExceptionToFailure(
        PlatformException(
          code: 'invalid_state',
          details: const <String, Object?>{
            'operation': 'take_photo',
            'capabilityFailureId': 'invalid_state',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.takePhoto,
      );
      final mismatched = codec.platformExceptionToFailure(
        PlatformException(
          code: 'invalid_state',
          details: const <String, Object?>{
            'operation': 'take_photo',
            'capabilityFailureId': 'invalid_argument',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.takePhoto,
      );
      final nativeOnly = codec.platformExceptionToFailure(
        PlatformException(
          code: 'invalid_state',
          details: const <String, Object?>{
            'operation': 'take_photo',
            'capabilityFailureId': 'attachment_generation_retired',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.takePhoto,
      );
      final wireMasquerade = codec.platformExceptionToFailure(
        PlatformException(
          code: 'duplicate_request',
          details: const <String, Object?>{
            'operation': 'take_photo',
            'capabilityFailureId': 'invalid_argument',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.takePhoto,
      );

      expect(
        valid.diagnostics.capabilityFailure,
        MediaCaptureCapabilityFailure.invalidState,
      );
      expect(mismatched.code, MediaCaptureFailureCode.invalidWirePayload);
      expect(nativeOnly.code, MediaCaptureFailureCode.invalidWirePayload);
      expect(wireMasquerade.code, MediaCaptureFailureCode.invalidWirePayload);
    });

    test('accepts transferable signed-64 detail boundaries', () {
      final minSigned64 = -9223372036854775807 - 1;
      const maxSigned64 = 9223372036854775807;
      final failure = codec.platformExceptionToFailure(
        PlatformException(
          code: 'incompatible_wire_version',
          details: <String, Object?>{
            'actualWireVersion': minSigned64,
            'expectedWireVersion': maxSigned64,
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.startSession,
      );

      expect(failure.code, MediaCaptureFailureCode.incompatibleWireVersion);
      expect(failure.diagnostics.actualWireVersion, minSigned64);
      expect(failure.diagnostics.expectedWireVersion, maxSigned64);
    });

    test('rejects capacity values that do not match the error code', () {
      final overloaded = codec.platformExceptionToFailure(
        PlatformException(
          code: 'bridge_overloaded',
          details: const <String, Object?>{
            'operation': 'start_session',
            'capacity': 'active_presentation',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.startSession,
      );
      final conflict = codec.platformExceptionToFailure(
        PlatformException(
          code: 'presentation_conflict',
          details: const <String, Object?>{
            'operation': 'present_capture_flow',
            'capacity': 'pending_requests',
          },
        ),
        StackTrace.current,
        operation: MediaCaptureOperation.presentCaptureFlow,
      );

      expect(overloaded.code, MediaCaptureFailureCode.invalidWirePayload);
      expect(conflict.code, MediaCaptureFailureCode.invalidWirePayload);
    });
  });

  group('event and async failure envelopes', () {
    final cases = <({Map<String, Object?> envelope, Matcher matcher})>[
      (
        envelope: _eventEnvelope('session_ready', <String, Object?>{
          'sessionHandle': 'session-1',
          'activeCamera': 'rear',
          'availableCameras': <String>['rear', 'front'],
          'switchCameraSupported': true,
          'supportedFlashModes': <String>['off', 'auto'],
          'focusPointSupported': true,
          'minZoomFactor': 1.0,
          'maxZoomFactor': 4.0,
        }),
        matcher: isA<MediaCaptureSessionReady>(),
      ),
      (
        envelope: _eventEnvelope('session_failed', const <String, Object?>{
          'sessionHandle': 'session-1',
          'terminalFailureId': 'system_interrupted',
        }),
        matcher: isA<MediaCaptureSessionFailed>(),
      ),
      (
        envelope: _eventEnvelope('media_preview_ready', <String, Object?>{
          'sessionHandle': 'session-1',
          ..._previewPayload(mediaType: 'video', durationMillis: 1000),
        }),
        matcher: isA<MediaCapturePreviewReady>(),
      ),
      (
        envelope: _eventEnvelope('media_lease_expired', const <String, Object?>{
          'mediaHandle': 'media-1',
        }),
        matcher: isA<MediaCaptureLeaseExpired>(),
      ),
      (
        envelope: _eventEnvelope('media_read_revoked', const <String, Object?>{
          'mediaHandle': 'media-1',
        }),
        matcher: isA<MediaCaptureReadRevoked>(),
      ),
      (
        envelope: <String, Object?>{
          'wireVersion': mediaCaptureWireVersion,
          'failureType': 'session_timeout',
          'payload': const <String, Object?>{'sessionHandle': 'session-1'},
        },
        matcher: isA<MediaCaptureAsyncFailure>(),
      ),
    ];

    for (var index = 0; index < cases.length; index += 1) {
      test('decodes closed event/failure case $index', () {
        expect(codec.decodeEvent(cases[index].envelope), cases[index].matcher);
      });
    }

    for (final eventType in <String>[
      'media_lease_expired',
      'media_read_revoked',
    ]) {
      test('$eventType rejects unknown payload keys', () {
        final event = codec.decodeEvent(
          _eventEnvelope(eventType, const <String, Object?>{
            'mediaHandle': 'media-1',
            'sessionHandle': 'session-1',
          }),
        );

        expect(event, isA<MediaCaptureBridgeFailureEvent>());
        expect(
          (event as MediaCaptureBridgeFailureEvent).failure.diagnostics.reason,
          MediaCaptureFailureReason.unknownField,
        );
      });
    }

    test('rejects int values for Wire double fields', () {
      final event = codec.decodeEvent(
        _eventEnvelope('session_ready', <String, Object?>{
          'sessionHandle': 'session-1',
          'activeCamera': 'rear',
          'availableCameras': <String>['rear'],
          'switchCameraSupported': false,
          'supportedFlashModes': <String>['off'],
          'focusPointSupported': true,
          'minZoomFactor': 1,
          'maxZoomFactor': 4.0,
        }),
      );

      expect(event, isA<MediaCaptureBridgeFailureEvent>());
      final failure = (event as MediaCaptureBridgeFailureEvent).failure;
      expect(failure.diagnostics.field, MediaCaptureFailureField.minZoomFactor);
      expect(
        failure.diagnostics.reason,
        MediaCaptureFailureReason.typeMismatch,
      );
    });

    test('native stream errors use a closed event-channel allowlist', () {
      final valid = codec.eventChannelExceptionToFailure(
        PlatformException(code: 'listener_already_active'),
        StackTrace.current,
      );
      final invalid = codec.eventChannelExceptionToFailure(
        PlatformException(
          code: 'invalid_state',
          details: const <String, Object?>{
            'operation': 'unknown_operation',
            'capabilityFailureId': 'invalid_state',
          },
        ),
        StackTrace.current,
      );

      expect(valid.code, MediaCaptureFailureCode.listenerAlreadyActive);
      expect(invalid.code, MediaCaptureFailureCode.invalidWirePayload);
    });
  });

  group('strict result and thumbnail boundaries', () {
    test('rejects requestId mismatch and unknown payload keys', () {
      final requestMismatch = codec.decodeMediaPreview(
        _resultEnvelope(
          requestId: 'other-request',
          resultType: 'media_preview',
          payload: _previewPayload(),
        ),
        requestId: 'expected-request',
        operation: methodTakePhoto,
      );
      final unknownPayload = codec.decodeMediaPreview(
        _resultEnvelope(
          requestId: 'request-1',
          resultType: 'media_preview',
          payload: <String, Object?>{..._previewPayload(), 'unknown': true},
        ),
        requestId: 'request-1',
        operation: methodTakePhoto,
      );

      expect(
        (requestMismatch as MediaCaptureCallFailure<MediaCapturePreview>)
            .failure
            .diagnostics
            .field,
        MediaCaptureFailureField.requestId,
      );
      expect(
        (unknownPayload as MediaCaptureCallFailure<MediaCapturePreview>)
            .failure
            .diagnostics
            .reason,
        MediaCaptureFailureReason.unknownField,
      );
    });

    test(
      'accepts the largest signed-64 result int and rejects double-as-int',
      () {
        const maxSigned64 = 9223372036854775807;
        final accepted = codec.decodeConfirmedMedia(
          _resultEnvelope(
            requestId: 'request-1',
            resultType: 'confirmed_media',
            payload: <String, Object?>{
              ..._previewPayload(),
              'leaseExpiresAt': maxSigned64,
            },
          ),
          requestId: 'request-1',
          operation: methodConfirm,
          expectedMediaHandle: 'media-1',
        );
        final rejected = codec.decodeMediaPreview(
          _resultEnvelope(
            requestId: 'request-2',
            resultType: 'media_preview',
            payload: <String, Object?>{..._previewPayload(), 'byteLength': 1.0},
          ),
          requestId: 'request-2',
          operation: methodTakePhoto,
        );

        expect(
          (accepted as MediaCaptureCallSuccess<MediaCaptureConfirmedMedia>)
              .value
              .leaseExpiresAtMillis,
          maxSigned64,
        );
        expect(
          (rejected as MediaCaptureCallFailure<MediaCapturePreview>)
              .failure
              .diagnostics
              .reason,
          MediaCaptureFailureReason.typeMismatch,
        );
      },
    );

    final thumbnailCases = <String, Map<String, Object?>>{
      'unknown key': <String, Object?>{..._thumbnailPayload(), 'unknown': true},
      'non Uint8List bytes': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailCopy': <int>[1, 2, 3],
      },
      'non-JPEG bytes with JPEG MIME': _thumbnailPayload(
        bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xd9]),
      ),
      'EXIF metadata segment': _thumbnailPayload(bytes: jpegWithExifSegment()),
      'JFIF segment with arbitrary suffix': _thumbnailPayload(
        bytes: jpegWithJfifSuffix(),
      ),
      'ICC profile segment': _thumbnailPayload(bytes: jpegWithIccSegment()),
      'scan before frame': _thumbnailPayload(bytes: jpegWithScanBeforeFrame()),
      'JPEG dimension mismatch': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailPixelWidth': 2,
      },
      'empty bytes': _thumbnailPayload(bytes: Uint8List(0)),
      'oversized bytes': _thumbnailPayload(
        bytes: Uint8List(mediaCaptureMaxThumbnailBytes + 1),
      ),
      'length mismatch': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailByteLength': 2,
      },
      'width exceeds request': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailPixelWidth': 129,
      },
      'height exceeds global max': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailPixelHeight': 513,
      },
      'wrong content type': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailContentType': 'image/png',
      },
      'non-upright orientation': <String, Object?>{
        ..._thumbnailPayload(),
        'thumbnailOrientationDegrees': 90,
      },
      'photo poster frame': <String, Object?>{
        ..._thumbnailPayload(),
        'posterFrameMillis': 0,
      },
      'video missing poster frame': <String, Object?>{
        ..._thumbnailPayload(),
        'mediaType': 'video',
      },
    };

    for (final entry in thumbnailCases.entries) {
      test('rejects thumbnail ${entry.key}', () {
        final result = codec.decodeThumbnail(
          _resultEnvelope(
            requestId: 'thumb-1',
            resultType: 'media_thumbnail',
            payload: entry.value,
          ),
          requestId: 'thumb-1',
          operation: methodReadMediaThumbnail,
          expectedMediaHandle: 'media-1',
          maxPixelEdge: 128,
        );

        expect(result, isA<MediaCaptureCallFailure<MediaCaptureThumbnail>>());
      });
    }
  });

  test('SessionReady owns defensive immutable sets', () {
    final cameras = <MediaCaptureCamera>{MediaCaptureCamera.rear};
    final flashModes = <MediaCaptureFlashMode>{MediaCaptureFlashMode.off};
    final ready = MediaCaptureSessionReady(
      session: MediaCaptureSession('session-1'),
      activeCamera: MediaCaptureCamera.rear,
      availableCameras: cameras,
      switchCameraSupported: false,
      supportedFlashModes: flashModes,
      focusPointSupported: true,
      minZoomFactor: 1.0,
      maxZoomFactor: 4.0,
    );

    cameras.add(MediaCaptureCamera.front);
    flashModes.add(MediaCaptureFlashMode.auto);

    expect(ready.availableCameras, <MediaCaptureCamera>{
      MediaCaptureCamera.rear,
    });
    expect(ready.supportedFlashModes, <MediaCaptureFlashMode>{
      MediaCaptureFlashMode.off,
    });
    expect(
      () => ready.availableCameras.add(MediaCaptureCamera.front),
      throwsUnsupportedError,
    );
    expect(
      () => ready.supportedFlashModes.add(MediaCaptureFlashMode.auto),
      throwsUnsupportedError,
    );
  });
}

Map<String, Object?> _errorDetails(
  MediaCaptureFailureCode code,
  MediaCaptureOperation operation,
) {
  if (_capabilityErrorCodes.contains(code)) {
    return <String, Object?>{
      'operation': operation.wireName,
      'capabilityFailureId': code.wireName,
    };
  }
  return switch (code) {
    MediaCaptureFailureCode.incompatibleWireVersion => <String, Object?>{
      'actualWireVersion': 1,
      'expectedWireVersion': mediaCaptureWireVersion,
    },
    MediaCaptureFailureCode.invalidWirePayload ||
    MediaCaptureFailureCode.wireEncodingFailed => <String, Object?>{
      'operation': operation.wireName,
      'field': 'payload',
      'reason': 'type_mismatch',
    },
    MediaCaptureFailureCode.duplicateRequest => <String, Object?>{
      'operation': operation.wireName,
    },
    MediaCaptureFailureCode.bridgeUnavailable => <String, Object?>{
      'operation': operation.wireName,
      'lifecycleReason': 'adapter_disposed',
    },
    MediaCaptureFailureCode.bridgeOverloaded => <String, Object?>{
      'operation': operation.wireName,
      'capacity': 'pending_requests',
    },
    MediaCaptureFailureCode.listenerAlreadyActive => const <String, Object?>{},
    MediaCaptureFailureCode.presentationConflict => <String, Object?>{
      'operation': operation.wireName,
      'capacity': 'active_presentation',
    },
    MediaCaptureFailureCode.transferStoreOverloaded => <String, Object?>{
      'operation': operation.wireName,
      'capacity': operation == MediaCaptureOperation.releaseMaterializedMedia
          ? 'release_tombstones'
          : 'active_exports',
    },
    MediaCaptureFailureCode.transferStoreUnavailable => <String, Object?>{
      'operation': operation.wireName,
      'lifecycleReason': 'adapter_disposed',
    },
    MediaCaptureFailureCode.materializedMediaInvalid => <String, Object?>{
      'operation': operation.wireName,
    },
    _ => throw StateError('Unhandled failure code ${code.wireName}'),
  };
}

Map<String, Object?> _eventEnvelope(
  String eventType,
  Map<String, Object?> payload,
) {
  return <String, Object?>{
    'wireVersion': mediaCaptureWireVersion,
    'eventType': eventType,
    'payload': payload,
  };
}

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

Map<String, Object?> _thumbnailPayload({Uint8List? bytes}) {
  final value = bytes ?? validSanitizedJpeg();
  return <String, Object?>{
    'mediaHandle': 'media-1',
    'thumbnailCopy': value,
    'thumbnailByteLength': value.length,
    'thumbnailPixelWidth': 1,
    'thumbnailPixelHeight': 1,
    'thumbnailContentType': 'image/jpeg',
    'thumbnailOrientationDegrees': 0,
    'mediaType': 'photo',
    'posterFrameMillis': null,
  };
}
