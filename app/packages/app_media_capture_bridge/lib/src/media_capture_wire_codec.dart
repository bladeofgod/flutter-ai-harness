import 'package:flutter/services.dart';

import 'media_capture_constants.dart';
import 'media_capture_models.dart';

typedef WireMap = Map<String, Object?>;

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
const int _minSigned64 = -9223372036854775808;
const int _maxSigned64 = 9223372036854775807;

const Map<MediaCaptureOperation, Set<MediaCaptureFailureCode>>
_methodErrorCodes = <MediaCaptureOperation, Set<MediaCaptureFailureCode>>{
  MediaCaptureOperation.startSession: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.sessionConflict,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.takePhoto: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.storageFull,
    MediaCaptureFailureCode.encodingFailed,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
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
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.stopRecording: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.encodingFailed,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.switchCamera: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.resourceInUse,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.setFlashMode: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.setFocusPoint: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.setZoom: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.unsupportedCapability,
    MediaCaptureFailureCode.systemInterrupted,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.retake: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.confirm: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.cancel: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.sessionInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.releaseMedia: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.readMediaThumbnail: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.mediaInvalid,
    MediaCaptureFailureCode.invalidState,
    MediaCaptureFailureCode.invalidArgument,
    MediaCaptureFailureCode.thumbnailGenerationFailed,
    MediaCaptureFailureCode.thumbnailGenerationCancelled,
    MediaCaptureFailureCode.thumbnailOverloaded,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
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
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.dismissCaptureFlow: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
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
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
  MediaCaptureOperation.releaseMaterializedMedia: <MediaCaptureFailureCode>{
    MediaCaptureFailureCode.materializedMediaInvalid,
    MediaCaptureFailureCode.transferStoreOverloaded,
    MediaCaptureFailureCode.transferStoreUnavailable,
    MediaCaptureFailureCode.incompatibleWireVersion,
    MediaCaptureFailureCode.invalidWirePayload,
    MediaCaptureFailureCode.duplicateRequest,
    MediaCaptureFailureCode.bridgeUnavailable,
    MediaCaptureFailureCode.bridgeOverloaded,
    MediaCaptureFailureCode.wireEncodingFailed,
  },
};

const Set<MediaCaptureFailureCode> _eventChannelErrorCodes =
    <MediaCaptureFailureCode>{
      MediaCaptureFailureCode.incompatibleWireVersion,
      MediaCaptureFailureCode.invalidWirePayload,
      MediaCaptureFailureCode.bridgeUnavailable,
      MediaCaptureFailureCode.wireEncodingFailed,
      MediaCaptureFailureCode.listenerAlreadyActive,
    };

final class MediaCaptureWireCodec {
  const MediaCaptureWireCodec();

  WireMap listenEnvelope() => const <String, Object?>{
    'wireVersion': mediaCaptureWireVersion,
  };

  WireMap requestEnvelope({
    required String requestId,
    required WireMap payload,
  }) {
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const MediaCaptureWireEncodeException(
        field: MediaCaptureFailureField.requestId,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
    return <String, Object?>{
      'wireVersion': mediaCaptureWireVersion,
      'requestId': requestId,
      'payload': payload,
    };
  }

  WireMap startSessionPayload(MediaCaptureConfig config) {
    return <String, Object?>{
      'enabledMediaTypes': config.enabledMediaTypes
          .map((type) => type.wireName)
          .toList(growable: false),
      'preferredCamera': config.preferredCamera.wireName,
      'audioEnabled': config.audioEnabled,
      'maxVideoDurationMillis': config.maxVideoDurationMillis,
    };
  }

  WireMap sessionActionPayload(MediaCaptureSession session) {
    return <String, Object?>{'sessionHandle': session.handle};
  }

  WireMap flashModePayload({
    required MediaCaptureSession session,
    required MediaCaptureFlashMode flashMode,
  }) {
    return <String, Object?>{
      'sessionHandle': session.handle,
      'flashMode': flashMode.wireName,
    };
  }

  WireMap focusPointPayload({
    required MediaCaptureSession session,
    required double normalizedX,
    required double normalizedY,
  }) {
    _checkDoubleRange(
      normalizedX,
      field: MediaCaptureFailureField.normalizedX,
      min: 0,
      max: 1,
    );
    _checkDoubleRange(
      normalizedY,
      field: MediaCaptureFailureField.normalizedY,
      min: 0,
      max: 1,
    );
    return <String, Object?>{
      'sessionHandle': session.handle,
      'normalizedX': normalizedX,
      'normalizedY': normalizedY,
    };
  }

  WireMap zoomPayload({
    required MediaCaptureSession session,
    required double zoomFactor,
  }) {
    _checkDoubleRange(
      zoomFactor,
      field: MediaCaptureFailureField.zoomFactor,
      min: 0.01,
      max: null,
    );
    return <String, Object?>{
      'sessionHandle': session.handle,
      'zoomFactor': zoomFactor,
    };
  }

  WireMap mediaHandlePayload(MediaCaptureMediaHandle mediaHandle) {
    return <String, Object?>{'mediaHandle': mediaHandle.value};
  }

  WireMap exportHandlePayload(MediaCaptureExportHandle exportHandle) {
    return <String, Object?>{'exportHandle': exportHandle.value};
  }

  WireMap presentationRequestPayload(String presentationRequestId) {
    if (!_requestIdPattern.hasMatch(presentationRequestId)) {
      throw const MediaCaptureWireEncodeException(
        field: MediaCaptureFailureField.requestId,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
    return <String, Object?>{'presentationRequestId': presentationRequestId};
  }

  WireMap thumbnailPayload(MediaCaptureThumbnailRequest request) {
    return <String, Object?>{
      'mediaHandle': request.mediaHandle.value,
      'maxPixelEdge': request.maxPixelEdge,
    };
  }

  MediaCaptureCallResult<MediaCaptureSession> decodeSessionCreated(
    Object? value, {
    required String requestId,
    required String operation,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'session_created',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: _decodeSessionCreatedPayload,
    );
  }

  MediaCaptureCallResult<MediaCaptureControlApplied> decodeControlApplied(
    Object? value, {
    required String requestId,
    required String operation,
    required String expectedSessionHandle,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'control_applied',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeControlAppliedPayload(payload);
        _checkExpectedHandle(
          actual: decoded.session.handle,
          expected: expectedSessionHandle,
          field: MediaCaptureFailureField.sessionHandle,
        );
        return decoded;
      },
    );
  }

  MediaCaptureCallResult<MediaCaptureRecordingStarted> decodeRecordingStarted(
    Object? value, {
    required String requestId,
    required String operation,
    required String expectedSessionHandle,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'recording_started',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeRecordingStartedPayload(payload);
        _checkExpectedHandle(
          actual: decoded.session.handle,
          expected: expectedSessionHandle,
          field: MediaCaptureFailureField.sessionHandle,
        );
        return decoded;
      },
    );
  }

  MediaCaptureCallResult<MediaCapturePreview> decodeMediaPreview(
    Object? value, {
    required String requestId,
    required String operation,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'media_preview',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: _decodeMediaPreviewPayload,
    );
  }

  MediaCaptureCallResult<MediaCaptureRetakeReady> decodeRetakeReady(
    Object? value, {
    required String requestId,
    required String operation,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'retake_ready',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: _decodeRetakeReadyPayload,
    );
  }

  MediaCaptureCallResult<MediaCaptureConfirmedMedia> decodeConfirmedMedia(
    Object? value, {
    required String requestId,
    required String operation,
    required String expectedMediaHandle,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'confirmed_media',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeConfirmedMediaPayload(payload);
        _checkExpectedHandle(
          actual: decoded.mediaHandle.value,
          expected: expectedMediaHandle,
          field: MediaCaptureFailureField.mediaHandle,
        );
        return decoded;
      },
    );
  }

  MediaCaptureCallResult<MediaCaptureSessionCancelled> decodeSessionCancelled(
    Object? value, {
    required String requestId,
    required String operation,
    required String expectedSessionHandle,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'session_cancelled',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeSessionCancelledPayload(payload);
        _checkExpectedHandle(
          actual: decoded.session.handle,
          expected: expectedSessionHandle,
          field: MediaCaptureFailureField.sessionHandle,
        );
        return decoded;
      },
    );
  }

  MediaCaptureCallResult<MediaCaptureMediaReleased> decodeMediaReleased(
    Object? value, {
    required String requestId,
    required String operation,
    required String expectedMediaHandle,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'media_released',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeMediaReleasedPayload(payload);
        _checkExpectedHandle(
          actual: decoded.mediaHandle.value,
          expected: expectedMediaHandle,
          field: MediaCaptureFailureField.mediaHandle,
        );
        return decoded;
      },
    );
  }

  MediaCaptureCallResult<MediaCaptureThumbnail> decodeThumbnail(
    Object? value, {
    required String requestId,
    required String operation,
    required String expectedMediaHandle,
    required int maxPixelEdge,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'media_thumbnail',
      operation: operation,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeThumbnailPayload(
          payload,
          maxPixelEdge: maxPixelEdge,
        );
        _checkExpectedHandle(
          actual: decoded.mediaHandle.value,
          expected: expectedMediaHandle,
          field: MediaCaptureFailureField.mediaHandle,
        );
        return decoded;
      },
    );
  }

  MediaCaptureCallResult<MediaCaptureMaterializedMedia> decodeMaterializedMedia(
    Object? value, {
    required String requestId,
    required int nowEpochMillis,
    required MediaCaptureMediaType expectedMediaType,
    required int expectedByteLength,
    required int? expectedDurationMillis,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'materialized_media_resource',
      operation: methodMaterializeMediaResource,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        final decoded = _decodeMaterializedMediaPayload(
          payload,
          nowEpochMillis: nowEpochMillis,
        );
        if (decoded.mediaType != expectedMediaType) {
          throw const MediaCaptureWireDecodeException(
            field: MediaCaptureFailureField.mediaType,
            reason: MediaCaptureFailureReason.invalidFormat,
          );
        }
        if (decoded.byteLength != expectedByteLength) {
          throw const MediaCaptureWireDecodeException(
            field: MediaCaptureFailureField.byteLength,
            reason: MediaCaptureFailureReason.invalidFormat,
          );
        }
        if (decoded.durationMillis != expectedDurationMillis) {
          throw const MediaCaptureWireDecodeException(
            field: MediaCaptureFailureField.durationMillis,
            reason: MediaCaptureFailureReason.invalidFormat,
          );
        }
        return decoded;
      },
    );
  }

  MediaCaptureExportHandle? materializedExportHandleForCleanup(
    Object? value, {
    required String requestId,
  }) {
    try {
      final envelope = _readMap(value, MediaCaptureFailureField.payload);
      _checkWireVersion(envelope['wireVersion']);
      _checkRequestId(envelope['requestId'], expected: requestId);
      final resultType = _readString(
        envelope,
        'resultType',
        MediaCaptureFailureField.resultType,
      );
      if (resultType != 'materialized_media_resource') return null;
      final payload = _readMap(
        envelope['payload'],
        MediaCaptureFailureField.payload,
      );
      return MediaCaptureExportHandle(
        _readString(
          payload,
          'exportHandle',
          MediaCaptureFailureField.exportHandle,
        ),
      );
    } on Object {
      return null;
    }
  }

  MediaCaptureCallResult<MediaCaptureMaterializedMediaReleased>
  decodeMaterializedMediaReleased(
    Object? value, {
    required String requestId,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'materialized_media_released',
      operation: methodReleaseMaterializedMedia,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        _requireExactKeys(payload, const <String>{});
        return const MediaCaptureMaterializedMediaReleased();
      },
    );
  }

  MediaCaptureCallResult<bool> decodeCaptureFlowDismissed(
    Object? value, {
    required String requestId,
    StackTrace? stackTrace,
  }) {
    return _decodeResult(
      value,
      requestId: requestId,
      expectedResultType: 'capture_flow_dismissed',
      operation: methodDismissCaptureFlow,
      stackTrace: stackTrace,
      payloadDecoder: (payload) {
        _requireExactKeys(payload, const <String>{});
        return true;
      },
    );
  }

  MediaCaptureFlowOutcome decodeCaptureFlow(
    Object? value, {
    required String requestId,
    StackTrace? stackTrace,
  }) {
    try {
      final envelope = _readMap(value, MediaCaptureFailureField.payload);
      _requireExactKeys(envelope, const <String>{
        'wireVersion',
        'requestId',
        'resultType',
        'payload',
      });
      _checkWireVersion(envelope['wireVersion']);
      _checkRequestId(envelope['requestId'], expected: requestId);
      final resultType = _readString(
        envelope,
        'resultType',
        MediaCaptureFailureField.resultType,
      );
      if (resultType == 'capture_flow_cancelled') {
        final payload = _readMap(
          envelope['payload'],
          MediaCaptureFailureField.payload,
        );
        _requireExactKeys(payload, const <String>{});
        return const MediaCaptureFlowCancelled();
      }
      if (resultType == 'capture_flow_confirmed') {
        final payload = _readMap(
          envelope['payload'],
          MediaCaptureFailureField.payload,
        );
        return MediaCaptureFlowConfirmed(_decodeConfirmedMediaPayload(payload));
      }
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.resultType,
        reason: MediaCaptureFailureReason.resultTypeMismatch,
      );
    } on MediaCaptureWireDecodeException catch (error) {
      return MediaCaptureFlowFailure(error.toFailure(stackTrace: stackTrace));
    }
  }

  MediaCaptureEvent decodeEvent(Object? value, {StackTrace? stackTrace}) {
    try {
      final envelope = _readMap(value, MediaCaptureFailureField.payload);
      if (envelope.containsKey('eventType')) {
        _requireExactKeys(envelope, const <String>{
          'wireVersion',
          'eventType',
          'payload',
        });
        _checkWireVersion(envelope['wireVersion']);
        final eventType = _readString(
          envelope,
          'eventType',
          MediaCaptureFailureField.eventType,
        );
        final payload = _readMap(
          envelope['payload'],
          MediaCaptureFailureField.payload,
        );
        return switch (eventType) {
          'session_ready' => _decodeSessionReadyPayload(payload),
          'session_failed' => _decodeSessionFailedPayload(payload),
          'media_preview_ready' => _decodePreviewReadyPayload(payload),
          'media_lease_expired' => _decodeLeaseExpiredPayload(payload),
          'media_read_revoked' => _decodeReadRevokedPayload(payload),
          _ => throw const MediaCaptureWireDecodeException(
            field: MediaCaptureFailureField.eventType,
            reason: MediaCaptureFailureReason.invalidEnum,
          ),
        };
      }
      if (envelope.containsKey('failureType')) {
        _requireExactKeys(envelope, const <String>{
          'wireVersion',
          'failureType',
          'payload',
        });
        _checkWireVersion(envelope['wireVersion']);
        final failureType = _readString(
          envelope,
          'failureType',
          MediaCaptureFailureField.failureType,
        );
        if (failureType != 'session_timeout') {
          throw const MediaCaptureWireDecodeException(
            field: MediaCaptureFailureField.failureType,
            reason: MediaCaptureFailureReason.invalidEnum,
          );
        }
        final payload = _readMap(
          envelope['payload'],
          MediaCaptureFailureField.payload,
        );
        _requireExactKeys(payload, const <String>{'sessionHandle'});
        final session = MediaCaptureSession(
          _readHandle(
            payload,
            'sessionHandle',
            MediaCaptureFailureField.sessionHandle,
          ),
        );
        return MediaCaptureAsyncFailure(
          failure: const MediaCaptureFailure(
            code: MediaCaptureFailureCode.sessionTimeout,
          ),
          session: session,
        );
      }
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.eventType,
        reason: MediaCaptureFailureReason.missingRequiredField,
      );
    } on MediaCaptureWireDecodeException catch (error) {
      return MediaCaptureBridgeFailureEvent(
        error.toFailure(stackTrace: stackTrace),
      );
    }
  }

  MediaCaptureFailure platformExceptionToFailure(
    PlatformException error,
    StackTrace stackTrace, {
    required MediaCaptureOperation operation,
  }) {
    final allowedCodes = _methodErrorCodes[operation];
    return _platformExceptionToFailure(
      error,
      stackTrace,
      operation: operation,
      allowedCodes: allowedCodes ?? const <MediaCaptureFailureCode>{},
    );
  }

  MediaCaptureFailure eventChannelExceptionToFailure(
    PlatformException error,
    StackTrace stackTrace,
  ) {
    return _platformExceptionToFailure(
      error,
      stackTrace,
      operation: MediaCaptureOperation.unknownOperation,
      allowedCodes: _eventChannelErrorCodes,
    );
  }

  MediaCaptureFailure _platformExceptionToFailure(
    PlatformException error,
    StackTrace stackTrace, {
    required MediaCaptureOperation operation,
    required Set<MediaCaptureFailureCode> allowedCodes,
  }) {
    final code = _failureCodeByWireName(error.code);
    if (code == null || !allowedCodes.contains(code)) {
      return _invalidWireFailure(
        field: MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.invalidEnum,
        stackTrace: stackTrace,
      );
    }
    try {
      final diagnostics = _decodeFailureDiagnostics(
        error.details,
        code: code,
        operation: operation,
        allowedKeys: _allowedDetailKeys(code),
      );
      return MediaCaptureFailure(code: code, diagnostics: diagnostics);
    } on MediaCaptureWireDecodeException catch (decodeError) {
      return decodeError.toFailure(stackTrace: stackTrace);
    }
  }
}

final class MediaCaptureWireEncodeException implements Exception {
  const MediaCaptureWireEncodeException({
    required this.field,
    required this.reason,
  });

  final MediaCaptureFailureField field;
  final MediaCaptureFailureReason reason;

  MediaCaptureFailure toFailure({
    required String operation,
    StackTrace? stackTrace,
  }) {
    return MediaCaptureFailure(
      code: MediaCaptureFailureCode.wireEncodingFailed,
      diagnostics: MediaCaptureFailureDiagnostics(
        operation: _operationByWireName(operation),
        field: field,
        reason: reason,
      ),
    );
  }
}

final class MediaCaptureWireDecodeException implements Exception {
  const MediaCaptureWireDecodeException({
    required this.field,
    required this.reason,
  });

  final MediaCaptureFailureField field;
  final MediaCaptureFailureReason reason;

  MediaCaptureFailure toFailure({StackTrace? stackTrace}) {
    return MediaCaptureFailure(
      code: MediaCaptureFailureCode.invalidWirePayload,
      diagnostics: MediaCaptureFailureDiagnostics(field: field, reason: reason),
    );
  }
}

MediaCaptureFailure _invalidWireFailure({
  required MediaCaptureFailureField field,
  required MediaCaptureFailureReason reason,
  StackTrace? stackTrace,
}) {
  return MediaCaptureFailure(
    code: MediaCaptureFailureCode.invalidWirePayload,
    diagnostics: MediaCaptureFailureDiagnostics(field: field, reason: reason),
  );
}

MediaCaptureCallResult<T> _decodeResult<T>(
  Object? value, {
  required String requestId,
  required String expectedResultType,
  required String operation,
  required T Function(WireMap payload) payloadDecoder,
  StackTrace? stackTrace,
}) {
  try {
    final envelope = _readMap(value, MediaCaptureFailureField.payload);
    _requireExactKeys(envelope, const <String>{
      'wireVersion',
      'requestId',
      'resultType',
      'payload',
    });
    _checkWireVersion(envelope['wireVersion']);
    _checkRequestId(envelope['requestId'], expected: requestId);
    final resultType = _readString(
      envelope,
      'resultType',
      MediaCaptureFailureField.resultType,
    );
    if (resultType != expectedResultType) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.resultType,
        reason: MediaCaptureFailureReason.resultTypeMismatch,
      );
    }
    final payload = _readMap(
      envelope['payload'],
      MediaCaptureFailureField.payload,
    );
    return MediaCaptureCallResult<T>.success(payloadDecoder(payload));
  } on MediaCaptureWireDecodeException catch (error) {
    return MediaCaptureCallResult<T>.failure(
      error.toFailure(stackTrace: stackTrace),
    );
  }
}

MediaCaptureSession _decodeSessionCreatedPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{'sessionHandle'});
  return MediaCaptureSession(
    _readHandle(
      payload,
      'sessionHandle',
      MediaCaptureFailureField.sessionHandle,
    ),
  );
}

MediaCaptureControlApplied _decodeControlAppliedPayload(WireMap payload) {
  return MediaCaptureControlApplied(_decodeSessionCreatedPayload(payload));
}

MediaCaptureRecordingStarted _decodeRecordingStartedPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{'sessionHandle', 'audioIncluded'});
  return MediaCaptureRecordingStarted(
    session: MediaCaptureSession(
      _readHandle(
        payload,
        'sessionHandle',
        MediaCaptureFailureField.sessionHandle,
      ),
    ),
    audioIncluded: _readBool(
      payload,
      'audioIncluded',
      MediaCaptureFailureField.audioIncluded,
    ),
  );
}

MediaCapturePreview _decodeMediaPreviewPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{
    'mediaHandle',
    'mediaType',
    'pixelWidth',
    'pixelHeight',
    'durationMillis',
    'orientationDegrees',
    'byteLength',
  });
  return _decodePreviewFields(payload);
}

MediaCaptureRetakeReady _decodeRetakeReadyPayload(WireMap payload) {
  return MediaCaptureRetakeReady(_decodeSessionCreatedPayload(payload));
}

MediaCaptureConfirmedMedia _decodeConfirmedMediaPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{
    'mediaHandle',
    'mediaType',
    'pixelWidth',
    'pixelHeight',
    'durationMillis',
    'orientationDegrees',
    'byteLength',
    'leaseExpiresAt',
  });
  final preview = _decodePreviewFields(payload);
  return MediaCaptureConfirmedMedia(
    mediaHandle: preview.mediaHandle,
    mediaType: preview.mediaType,
    pixelWidth: preview.pixelWidth,
    pixelHeight: preview.pixelHeight,
    durationMillis: preview.durationMillis,
    orientationDegrees: preview.orientationDegrees,
    byteLength: preview.byteLength,
    leaseExpiresAtMillis: _readIntRange(
      payload,
      'leaseExpiresAt',
      MediaCaptureFailureField.leaseExpiresAt,
      min: 0,
      max: null,
    ),
  );
}

MediaCaptureSessionCancelled _decodeSessionCancelledPayload(WireMap payload) {
  return MediaCaptureSessionCancelled(_decodeSessionCreatedPayload(payload));
}

MediaCaptureMediaReleased _decodeMediaReleasedPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{'mediaHandle'});
  return MediaCaptureMediaReleased(
    MediaCaptureMediaHandle(
      _readHandle(payload, 'mediaHandle', MediaCaptureFailureField.mediaHandle),
    ),
  );
}

MediaCaptureMaterializedMedia _decodeMaterializedMediaPayload(
  WireMap payload, {
  required int nowEpochMillis,
}) {
  _requireKeys(
    payload,
    required: const <String>{
      'exportHandle',
      'fileUri',
      'mediaType',
      'contentType',
      'byteLength',
      'durationMillis',
      'expiresAt',
    },
    optional: const <String>{'integritySha256'},
  );
  final exportHandleValue = _readString(
    payload,
    'exportHandle',
    MediaCaptureFailureField.exportHandle,
  );
  late final MediaCaptureExportHandle exportHandle;
  try {
    exportHandle = MediaCaptureExportHandle(exportHandleValue);
  } on ArgumentError {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.exportHandle,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
  final fileUriValue = _readString(
    payload,
    'fileUri',
    MediaCaptureFailureField.fileUri,
  );
  final fileUri = _decodeCanonicalFileUri(fileUriValue);
  final mediaType = _readEnum(
    payload,
    'mediaType',
    MediaCaptureFailureField.mediaType,
    MediaCaptureMediaType.values,
    (value) => value.wireName,
  );
  final contentType = _readString(
    payload,
    'contentType',
    MediaCaptureFailureField.contentType,
  );
  final expectedContentType = mediaType == MediaCaptureMediaType.photo
      ? 'image/jpeg'
      : 'video/mp4';
  if (contentType != expectedContentType) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.contentType,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
  final durationMillis = _readNullableIntRange(
    payload,
    'durationMillis',
    MediaCaptureFailureField.durationMillis,
    min: mediaCaptureMinVideoDurationMillis,
    max: mediaCaptureMaxVideoDurationMillis,
  );
  _checkMediaDurationCondition(
    mediaType: mediaType,
    value: durationMillis,
    field: MediaCaptureFailureField.durationMillis,
    allowZero: false,
  );
  final expiresAtMillis = _readIntRange(
    payload,
    'expiresAt',
    MediaCaptureFailureField.expiresAt,
    min: 0,
    max: null,
  );
  if (expiresAtMillis <= nowEpochMillis ||
      expiresAtMillis - nowEpochMillis > mediaCaptureMaterializedTtlMillis) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.expiresAt,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  String? integritySha256;
  if (payload.containsKey('integritySha256')) {
    integritySha256 = _readString(
      payload,
      'integritySha256',
      MediaCaptureFailureField.integritySha256,
    );
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(integritySha256)) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.integritySha256,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
  }
  return MediaCaptureMaterializedMedia(
    exportHandle: exportHandle,
    fileUri: fileUri,
    mediaType: mediaType,
    contentType: contentType,
    byteLength: _readIntRange(
      payload,
      'byteLength',
      MediaCaptureFailureField.byteLength,
      min: 1,
      max: mediaCaptureMaxMaterializedBytes,
    ),
    durationMillis: durationMillis,
    expiresAtMillis: expiresAtMillis,
    integritySha256: integritySha256,
  );
}

MediaCaptureThumbnail _decodeThumbnailPayload(
  WireMap payload, {
  required int maxPixelEdge,
}) {
  _requireExactKeys(payload, const <String>{
    'mediaHandle',
    'thumbnailCopy',
    'thumbnailByteLength',
    'thumbnailPixelWidth',
    'thumbnailPixelHeight',
    'thumbnailContentType',
    'thumbnailOrientationDegrees',
    'mediaType',
    'posterFrameMillis',
  });
  final bytes = _readBytes(payload, 'thumbnailCopy');
  final byteLength = _readIntRange(
    payload,
    'thumbnailByteLength',
    MediaCaptureFailureField.thumbnailByteLength,
    min: 1,
    max: mediaCaptureMaxThumbnailBytes,
  );
  if (byteLength != bytes.length) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.thumbnailByteLength,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  final width = _readIntRange(
    payload,
    'thumbnailPixelWidth',
    MediaCaptureFailureField.thumbnailPixelWidth,
    min: 1,
    max: mediaCaptureMaxThumbnailEdge,
  );
  final height = _readIntRange(
    payload,
    'thumbnailPixelHeight',
    MediaCaptureFailureField.thumbnailPixelHeight,
    min: 1,
    max: mediaCaptureMaxThumbnailEdge,
  );
  if (width > maxPixelEdge || height > maxPixelEdge) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.thumbnailPixelWidth,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  final contentType = _readString(
    payload,
    'thumbnailContentType',
    MediaCaptureFailureField.thumbnailContentType,
  );
  if (contentType != 'image/jpeg') {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.thumbnailContentType,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
  _validateSanitizedJpeg(bytes, expectedWidth: width, expectedHeight: height);
  final orientation = _readAllowedInt(
    payload,
    'thumbnailOrientationDegrees',
    MediaCaptureFailureField.thumbnailOrientationDegrees,
    const <int>{0},
  );
  final mediaType = _readEnum(
    payload,
    'mediaType',
    MediaCaptureFailureField.mediaType,
    MediaCaptureMediaType.values,
    (value) => value.wireName,
  );
  final posterFrameMillis = _readNullableIntRange(
    payload,
    'posterFrameMillis',
    MediaCaptureFailureField.posterFrameMillis,
    min: 0,
    max: mediaCaptureMaxVideoDurationMillis,
  );
  _checkMediaDurationCondition(
    mediaType: mediaType,
    value: posterFrameMillis,
    field: MediaCaptureFailureField.posterFrameMillis,
    allowZero: true,
  );
  final thumbnail = MediaCaptureThumbnail(
    mediaHandle: MediaCaptureMediaHandle(
      _readHandle(payload, 'mediaHandle', MediaCaptureFailureField.mediaHandle),
    ),
    bytes: bytes,
    pixelWidth: width,
    pixelHeight: height,
    contentType: contentType,
    orientationDegrees: orientation,
    mediaType: mediaType,
    posterFrameMillis: posterFrameMillis,
  );
  bytes.fillRange(0, bytes.length, 0);
  final sourceBytes = payload['thumbnailCopy'];
  if (sourceBytes is Uint8List) {
    sourceBytes.fillRange(0, sourceBytes.length, 0);
  }
  return thumbnail;
}

MediaCaptureSessionReady _decodeSessionReadyPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{
    'sessionHandle',
    'activeCamera',
    'availableCameras',
    'switchCameraSupported',
    'supportedFlashModes',
    'focusPointSupported',
    'minZoomFactor',
    'maxZoomFactor',
  });
  final minZoomFactor = _readDoubleRange(
    payload,
    'minZoomFactor',
    MediaCaptureFailureField.minZoomFactor,
    min: 0.01,
    max: null,
  );
  final maxZoomFactor = _readDoubleRange(
    payload,
    'maxZoomFactor',
    MediaCaptureFailureField.maxZoomFactor,
    min: 0.01,
    max: null,
  );
  if (maxZoomFactor < minZoomFactor) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.maxZoomFactor,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  return MediaCaptureSessionReady(
    session: MediaCaptureSession(
      _readHandle(
        payload,
        'sessionHandle',
        MediaCaptureFailureField.sessionHandle,
      ),
    ),
    activeCamera: _readEnum(
      payload,
      'activeCamera',
      MediaCaptureFailureField.activeCamera,
      MediaCaptureCamera.values,
      (value) => value.wireName,
    ),
    availableCameras: _readEnumSet(
      payload,
      'availableCameras',
      MediaCaptureFailureField.availableCameras,
      MediaCaptureCamera.values,
      (value) => value.wireName,
      minItems: 1,
      maxItems: 2,
    ),
    switchCameraSupported: _readBool(
      payload,
      'switchCameraSupported',
      MediaCaptureFailureField.switchCameraSupported,
    ),
    supportedFlashModes: _readEnumSet(
      payload,
      'supportedFlashModes',
      MediaCaptureFailureField.supportedFlashModes,
      MediaCaptureFlashMode.values,
      (value) => value.wireName,
      minItems: 1,
      maxItems: 4,
    ),
    focusPointSupported: _readBool(
      payload,
      'focusPointSupported',
      MediaCaptureFailureField.focusPointSupported,
    ),
    minZoomFactor: minZoomFactor,
    maxZoomFactor: maxZoomFactor,
  );
}

MediaCaptureSessionFailed _decodeSessionFailedPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{
    'sessionHandle',
    'terminalFailureId',
  });
  return MediaCaptureSessionFailed(
    session: MediaCaptureSession(
      _readHandle(
        payload,
        'sessionHandle',
        MediaCaptureFailureField.sessionHandle,
      ),
    ),
    terminalFailure: _readEnum(
      payload,
      'terminalFailureId',
      MediaCaptureFailureField.terminalFailureId,
      MediaCaptureTerminalFailure.values,
      (value) => value.wireName,
    ),
  );
}

MediaCapturePreviewReady _decodePreviewReadyPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{
    'sessionHandle',
    'mediaHandle',
    'mediaType',
    'pixelWidth',
    'pixelHeight',
    'durationMillis',
    'orientationDegrees',
    'byteLength',
  });
  return MediaCapturePreviewReady(
    session: MediaCaptureSession(
      _readHandle(
        payload,
        'sessionHandle',
        MediaCaptureFailureField.sessionHandle,
      ),
    ),
    preview: _decodePreviewFields(payload),
  );
}

MediaCaptureLeaseExpired _decodeLeaseExpiredPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{'mediaHandle'});
  return MediaCaptureLeaseExpired(
    MediaCaptureMediaHandle(
      _readHandle(payload, 'mediaHandle', MediaCaptureFailureField.mediaHandle),
    ),
  );
}

MediaCaptureReadRevoked _decodeReadRevokedPayload(WireMap payload) {
  _requireExactKeys(payload, const <String>{'mediaHandle'});
  return MediaCaptureReadRevoked(
    MediaCaptureMediaHandle(
      _readHandle(payload, 'mediaHandle', MediaCaptureFailureField.mediaHandle),
    ),
  );
}

MediaCapturePreview _decodePreviewFields(WireMap payload) {
  final mediaType = _readEnum(
    payload,
    'mediaType',
    MediaCaptureFailureField.mediaType,
    MediaCaptureMediaType.values,
    (value) => value.wireName,
  );
  final durationMillis = _readNullableIntRange(
    payload,
    'durationMillis',
    MediaCaptureFailureField.durationMillis,
    min: mediaCaptureMinVideoDurationMillis,
    max: mediaCaptureMaxVideoDurationMillis,
  );
  _checkMediaDurationCondition(
    mediaType: mediaType,
    value: durationMillis,
    field: MediaCaptureFailureField.durationMillis,
    allowZero: false,
  );
  return MediaCapturePreview(
    mediaHandle: MediaCaptureMediaHandle(
      _readHandle(payload, 'mediaHandle', MediaCaptureFailureField.mediaHandle),
    ),
    mediaType: mediaType,
    pixelWidth: _readIntRange(
      payload,
      'pixelWidth',
      MediaCaptureFailureField.pixelWidth,
      min: 1,
      max: null,
    ),
    pixelHeight: _readIntRange(
      payload,
      'pixelHeight',
      MediaCaptureFailureField.pixelHeight,
      min: 1,
      max: null,
    ),
    durationMillis: durationMillis,
    orientationDegrees: _readAllowedInt(
      payload,
      'orientationDegrees',
      MediaCaptureFailureField.orientationDegrees,
      const <int>{0, 90, 180, 270},
    ),
    byteLength: _readIntRange(
      payload,
      'byteLength',
      MediaCaptureFailureField.byteLength,
      min: 1,
      max: null,
    ),
  );
}

WireMap _readMap(Object? value, MediaCaptureFailureField field) {
  if (value is! Map<Object?, Object?>) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.typeMismatch,
      );
    }
    result[key] = entry.value;
  }
  return result;
}

void _requireExactKeys(WireMap map, Set<String> expected) {
  for (final key in map.keys) {
    if (!expected.contains(key)) {
      throw MediaCaptureWireDecodeException(
        field: _fieldByWireName(key) ?? MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.unknownField,
      );
    }
  }
  for (final key in expected) {
    if (!map.containsKey(key)) {
      throw MediaCaptureWireDecodeException(
        field: _fieldByWireName(key) ?? MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.missingRequiredField,
      );
    }
  }
}

void _requireKeys(
  WireMap map, {
  required Set<String> required,
  required Set<String> optional,
}) {
  final allowed = <String>{...required, ...optional};
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw MediaCaptureWireDecodeException(
        field: _fieldByWireName(key) ?? MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.unknownField,
      );
    }
  }
  for (final key in required) {
    if (!map.containsKey(key)) {
      throw MediaCaptureWireDecodeException(
        field: _fieldByWireName(key) ?? MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.missingRequiredField,
      );
    }
  }
}

Uri _decodeCanonicalFileUri(String value) {
  if (value.length > mediaCaptureMaxFileUriLength ||
      !value.startsWith('file:///')) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.fileUri,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit <= 0x20 || codeUnit >= 0x7f) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.fileUri,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
    if (codeUnit != 0x25) continue;
    if (index + 2 >= value.length ||
        !_isUpperHex(value.codeUnitAt(index + 1)) ||
        !_isUpperHex(value.codeUnitAt(index + 2))) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.fileUri,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
    index += 2;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'file' ||
      !uri.hasAuthority ||
      uri.host.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      !uri.path.startsWith('/') ||
      uri.toString() != value) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.fileUri,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
  final rawPath = value.substring('file://'.length);
  if (rawPath.length <= 1 ||
      rawPath.endsWith('/') ||
      rawPath.substring(1).contains('//')) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.fileUri,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
  for (final rawSegment in rawPath.substring(1).split('/')) {
    late final String decoded;
    try {
      decoded = Uri.decodeComponent(rawSegment);
    } on FormatException {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.fileUri,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
    if (decoded.isEmpty ||
        decoded == '.' ||
        decoded == '..' ||
        decoded.contains('/') ||
        decoded.contains(r'\') ||
        decoded.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.fileUri,
        reason: MediaCaptureFailureReason.invalidFormat,
      );
    }
  }
  return uri;
}

bool _isUpperHex(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x46);
}

void _checkWireVersion(Object? value) {
  final wireVersion = _readIntValue(
    value,
    MediaCaptureFailureField.wireVersion,
  );
  if (wireVersion != mediaCaptureWireVersion) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.wireVersion,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
}

void _checkRequestId(Object? value, {required String expected}) {
  final requestId = _readStringValue(value, MediaCaptureFailureField.requestId);
  if (!_requestIdPattern.hasMatch(requestId) || requestId != expected) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.requestId,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
}

String _readString(WireMap map, String key, MediaCaptureFailureField field) {
  return _readStringValue(map[key], field);
}

String _readStringValue(Object? value, MediaCaptureFailureField field) {
  if (value == null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (value is! String) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  return value;
}

bool _readBool(WireMap map, String key, MediaCaptureFailureField field) {
  final value = map[key];
  if (value == null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (value is! bool) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  return value;
}

int _readIntRange(
  WireMap map,
  String key,
  MediaCaptureFailureField field, {
  required int min,
  required int? max,
}) {
  final value = _readIntValue(map[key], field);
  _checkIntRange(value, field: field, min: min, max: max);
  return value;
}

int? _readNullableIntRange(
  WireMap map,
  String key,
  MediaCaptureFailureField field, {
  required int min,
  required int max,
}) {
  if (!map.containsKey(key)) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.missingRequiredField,
    );
  }
  final value = map[key];
  if (value == null) {
    return null;
  }
  final intValue = _readIntValue(value, field);
  _checkIntRange(intValue, field: field, min: min, max: max);
  return intValue;
}

int _readAllowedInt(
  WireMap map,
  String key,
  MediaCaptureFailureField field,
  Set<int> allowed,
) {
  final value = _readIntValue(map[key], field);
  if (!allowed.contains(value)) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  return value;
}

int _readIntValue(Object? value, MediaCaptureFailureField field) {
  if (value == null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (value is! int) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  if (value < _minSigned64 || value > _maxSigned64) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.integerOverflow,
    );
  }
  return value;
}

double _readDoubleRange(
  WireMap map,
  String key,
  MediaCaptureFailureField field, {
  required double min,
  required double? max,
}) {
  final value = map[key];
  if (value == null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (value is! double) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  _checkDoubleRangeForDecode(value, field: field, min: min, max: max);
  return value;
}

void _checkDoubleRange(
  double value, {
  required MediaCaptureFailureField field,
  required double min,
  required double? max,
}) {
  if (!value.isFinite) {
    throw MediaCaptureWireEncodeException(
      field: field,
      reason: MediaCaptureFailureReason.nonFinite,
    );
  }
  if (value < min || (max != null && value > max)) {
    throw MediaCaptureWireEncodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
}

void _checkDoubleRangeForDecode(
  double value, {
  required MediaCaptureFailureField field,
  required double min,
  required double? max,
}) {
  if (!value.isFinite) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nonFinite,
    );
  }
  if (value < min || (max != null && value > max)) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
}

void _checkIntRange(
  int value, {
  required MediaCaptureFailureField field,
  required int min,
  required int? max,
}) {
  if (value < min || (max != null && value > max)) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
}

String _readHandle(WireMap map, String key, MediaCaptureFailureField field) {
  final value = _readString(map, key, field);
  if (value.isEmpty || value.length > mediaCaptureMaxHandleLength) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  return value;
}

Uint8List _readBytes(WireMap map, String key) {
  final value = map[key];
  if (value == null) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.thumbnailCopy,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (value is! Uint8List) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.thumbnailCopy,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  if (value.isEmpty || value.length > mediaCaptureMaxThumbnailBytes) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.thumbnailCopy,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  return Uint8List.fromList(value);
}

void _checkExpectedHandle({
  required String actual,
  required String expected,
  required MediaCaptureFailureField field,
}) {
  if (actual != expected) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.invalidFormat,
    );
  }
}

void _validateSanitizedJpeg(
  Uint8List bytes, {
  required int expectedWidth,
  required int expectedHeight,
}) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    _throwInvalidThumbnailBytes();
  }
  var offset = 2;
  var sawFrame = false;
  var sawScan = false;
  var sawEnd = false;
  while (offset < bytes.length) {
    if (bytes[offset] != 0xff) _throwInvalidThumbnailBytes();
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset += 1;
    }
    if (offset >= bytes.length) _throwInvalidThumbnailBytes();
    final marker = bytes[offset];
    offset += 1;
    if (marker == 0xd9) {
      if (!sawFrame || !sawScan || offset != bytes.length) {
        _throwInvalidThumbnailBytes();
      }
      sawEnd = true;
      break;
    }
    if (marker == 0x00 ||
        marker == 0xd8 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      _throwInvalidThumbnailBytes();
    }
    if (offset + 2 > bytes.length) _throwInvalidThumbnailBytes();
    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) {
      _throwInvalidThumbnailBytes();
    }
    final payloadStart = offset + 2;
    final payloadEnd = offset + segmentLength;
    if (marker == 0xe0) {
      _validateCanonicalJfifSegment(bytes, payloadStart, payloadEnd);
    } else if (marker >= 0xe1 && marker <= 0xef) {
      _throwInvalidThumbnailBytes();
    } else if (marker == 0xfe || !_allowedJpegSegmentMarkers.contains(marker)) {
      _throwInvalidThumbnailBytes();
    }
    if (_jpegStartOfFrameMarkers.contains(marker)) {
      if (sawFrame || sawScan) _throwInvalidThumbnailBytes();
      _validateStartOfFrameSegment(bytes, payloadStart, payloadEnd);
      final height = (bytes[payloadStart + 1] << 8) | bytes[payloadStart + 2];
      final width = (bytes[payloadStart + 3] << 8) | bytes[payloadStart + 4];
      if (width != expectedWidth || height != expectedHeight) {
        _throwInvalidThumbnailBytes();
      }
      sawFrame = true;
    }
    offset = payloadEnd;
    if (marker == 0xda) {
      if (!sawFrame) _throwInvalidThumbnailBytes();
      _validateStartOfScanSegment(bytes, payloadStart, payloadEnd);
      sawScan = true;
      while (offset < bytes.length) {
        if (bytes[offset] != 0xff) {
          offset += 1;
          continue;
        }
        final markerStart = offset;
        while (offset < bytes.length && bytes[offset] == 0xff) {
          offset += 1;
        }
        if (offset >= bytes.length) _throwInvalidThumbnailBytes();
        final scanMarker = bytes[offset];
        if (scanMarker == 0x00 || (scanMarker >= 0xd0 && scanMarker <= 0xd7)) {
          offset += 1;
          continue;
        }
        offset = markerStart;
        break;
      }
    }
  }
  if (!sawEnd) _throwInvalidThumbnailBytes();
}

void _validateStartOfFrameSegment(Uint8List bytes, int start, int end) {
  if (end - start < 9 || bytes[start] != 8) {
    _throwInvalidThumbnailBytes();
  }
  final componentCount = bytes[start + 5];
  if (componentCount < 1 || componentCount > 4) {
    _throwInvalidThumbnailBytes();
  }
  if (end - start != 6 + (3 * componentCount)) {
    _throwInvalidThumbnailBytes();
  }
}

void _validateStartOfScanSegment(Uint8List bytes, int start, int end) {
  if (end - start < 6) _throwInvalidThumbnailBytes();
  final componentCount = bytes[start];
  if (componentCount < 1 || componentCount > 4) {
    _throwInvalidThumbnailBytes();
  }
  if (end - start != 4 + (2 * componentCount)) {
    _throwInvalidThumbnailBytes();
  }
}

bool _startsWithAscii(Uint8List bytes, int start, int end, String expected) {
  final codeUnits = expected.codeUnits;
  if (start + codeUnits.length > end) return false;
  for (var index = 0; index < codeUnits.length; index += 1) {
    if (bytes[start + index] != codeUnits[index]) return false;
  }
  return true;
}

void _validateCanonicalJfifSegment(Uint8List bytes, int start, int end) {
  if (end - start != 14 ||
      !_startsWithAscii(bytes, start, end, 'JFIF\u0000') ||
      bytes[start + 5] != 1 ||
      bytes[start + 6] > 2 ||
      bytes[start + 7] > 2 ||
      ((bytes[start + 8] << 8) | bytes[start + 9]) == 0 ||
      ((bytes[start + 10] << 8) | bytes[start + 11]) == 0 ||
      bytes[start + 12] != 0 ||
      bytes[start + 13] != 0) {
    _throwInvalidThumbnailBytes();
  }
}

Never _throwInvalidThumbnailBytes() {
  throw const MediaCaptureWireDecodeException(
    field: MediaCaptureFailureField.thumbnailCopy,
    reason: MediaCaptureFailureReason.invalidFormat,
  );
}

const Set<int> _jpegStartOfFrameMarkers = <int>{
  0xc0,
  0xc1,
  0xc2,
  0xc3,
  0xc5,
  0xc6,
  0xc7,
  0xc9,
  0xca,
  0xcb,
  0xcd,
  0xce,
  0xcf,
};

const Set<int> _allowedJpegSegmentMarkers = <int>{
  ..._jpegStartOfFrameMarkers,
  0xc4,
  0xcc,
  0xda,
  0xdb,
  0xdc,
  0xdd,
  0xde,
  0xdf,
};

T _readEnum<T>(
  WireMap map,
  String key,
  MediaCaptureFailureField field,
  List<T> values,
  String Function(T value) wireName,
) {
  final name = _readString(map, key, field);
  for (final value in values) {
    if (wireName(value) == name) {
      return value;
    }
  }
  throw MediaCaptureWireDecodeException(
    field: field,
    reason: MediaCaptureFailureReason.invalidEnum,
  );
}

Set<T> _readEnumSet<T>(
  WireMap map,
  String key,
  MediaCaptureFailureField field,
  List<T> values,
  String Function(T value) wireName, {
  required int minItems,
  required int maxItems,
}) {
  final value = map[key];
  if (value == null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (value is! List<Object?>) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  if (value.length < minItems || value.length > maxItems) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  final result = <T>{};
  for (final item in value) {
    if (item is! String) {
      throw MediaCaptureWireDecodeException(
        field: field,
        reason: MediaCaptureFailureReason.typeMismatch,
      );
    }
    T? matched;
    for (final enumValue in values) {
      if (wireName(enumValue) == item) {
        matched = enumValue;
        break;
      }
    }
    if (matched == null) {
      throw MediaCaptureWireDecodeException(
        field: field,
        reason: MediaCaptureFailureReason.invalidEnum,
      );
    }
    result.add(matched);
  }
  if (result.length != value.length) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  return Set<T>.unmodifiable(result);
}

void _checkMediaDurationCondition({
  required MediaCaptureMediaType mediaType,
  required int? value,
  required MediaCaptureFailureField field,
  required bool allowZero,
}) {
  if (mediaType == MediaCaptureMediaType.photo && value != null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
  if (mediaType == MediaCaptureMediaType.video && value == null) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.nullNotAllowed,
    );
  }
  if (!allowZero && value == 0) {
    throw MediaCaptureWireDecodeException(
      field: field,
      reason: MediaCaptureFailureReason.outOfRange,
    );
  }
}

MediaCaptureFailureDiagnostics _decodeFailureDiagnostics(
  Object? details, {
  required MediaCaptureFailureCode code,
  required MediaCaptureOperation operation,
  required Set<String> allowedKeys,
}) {
  if (details == null) {
    return const MediaCaptureFailureDiagnostics();
  }
  final detailMap = _readMap(details, MediaCaptureFailureField.payload);
  for (final key in detailMap.keys) {
    if (!allowedKeys.contains(key)) {
      throw const MediaCaptureWireDecodeException(
        field: MediaCaptureFailureField.unknownField,
        reason: MediaCaptureFailureReason.unknownField,
      );
    }
  }
  final detailOperation = _optionalClosedValue(
    detailMap,
    'operation',
    MediaCaptureOperation.values,
    (value) => value.wireName,
  );
  if (detailOperation != null && detailOperation != operation) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.unknownField,
      reason: MediaCaptureFailureReason.invalidEnum,
    );
  }
  final capabilityFailure = _optionalClosedValue(
    detailMap,
    'capabilityFailureId',
    MediaCaptureCapabilityFailure.values,
    (value) => value.wireName,
  );
  final expectedCapabilityFailure = _capabilityFailureForCode(code);
  if (capabilityFailure != null &&
      capabilityFailure != expectedCapabilityFailure) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.unknownField,
      reason: MediaCaptureFailureReason.invalidEnum,
    );
  }
  final capacity = _optionalClosedValue(
    detailMap,
    'capacity',
    MediaCaptureCapacity.values,
    (value) => value.wireName,
  );
  final allowedCapacities = switch (code) {
    MediaCaptureFailureCode.bridgeOverloaded => const <MediaCaptureCapacity>{
      MediaCaptureCapacity.pendingRequests,
      MediaCaptureCapacity.completedRequestTombstones,
    },
    MediaCaptureFailureCode.presentationConflict =>
      const <MediaCaptureCapacity>{MediaCaptureCapacity.activePresentation},
    MediaCaptureFailureCode.transferStoreOverloaded =>
      operation == MediaCaptureOperation.releaseMaterializedMedia
          ? const <MediaCaptureCapacity>{MediaCaptureCapacity.releaseTombstones}
          : const <MediaCaptureCapacity>{
              MediaCaptureCapacity.activeExports,
              MediaCaptureCapacity.activeExportBytes,
            },
    _ => const <MediaCaptureCapacity>{},
  };
  if (capacity != null && !allowedCapacities.contains(capacity)) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.unknownField,
      reason: MediaCaptureFailureReason.invalidEnum,
    );
  }
  return MediaCaptureFailureDiagnostics(
    operation: detailOperation,
    capabilityFailure: capabilityFailure,
    actualWireVersion: _optionalInt(detailMap, 'actualWireVersion'),
    expectedWireVersion: _optionalInt(detailMap, 'expectedWireVersion'),
    field: _optionalClosedValue(
      detailMap,
      'field',
      MediaCaptureFailureField.values,
      (value) => value.wireName,
    ),
    reason: _optionalClosedValue(
      detailMap,
      'reason',
      MediaCaptureFailureReason.values,
      (value) => value.wireName,
    ),
    lifecycleReason: _optionalClosedValue(
      detailMap,
      'lifecycleReason',
      MediaCaptureLifecycleReason.values,
      (value) => value.wireName,
    ),
    capacity: capacity,
  );
}

T? _optionalClosedValue<T>(
  WireMap map,
  String key,
  List<T> values,
  String Function(T value) wireName,
) {
  if (!map.containsKey(key)) {
    return null;
  }
  final value = map[key];
  if (value is! String) {
    throw const MediaCaptureWireDecodeException(
      field: MediaCaptureFailureField.unknownField,
      reason: MediaCaptureFailureReason.typeMismatch,
    );
  }
  for (final item in values) {
    if (wireName(item) == value) {
      return item;
    }
  }
  throw const MediaCaptureWireDecodeException(
    field: MediaCaptureFailureField.unknownField,
    reason: MediaCaptureFailureReason.invalidEnum,
  );
}

int? _optionalInt(WireMap map, String key) {
  if (!map.containsKey(key)) {
    return null;
  }
  return _readIntValue(map[key], MediaCaptureFailureField.unknownField);
}

Set<String> _allowedDetailKeys(MediaCaptureFailureCode code) {
  return switch (code) {
    MediaCaptureFailureCode.incompatibleWireVersion => const <String>{
      'actualWireVersion',
      'expectedWireVersion',
    },
    MediaCaptureFailureCode.invalidWirePayload ||
    MediaCaptureFailureCode.wireEncodingFailed => const <String>{
      'operation',
      'field',
      'reason',
    },
    MediaCaptureFailureCode.duplicateRequest => const <String>{'operation'},
    MediaCaptureFailureCode.bridgeUnavailable => const <String>{
      'operation',
      'lifecycleReason',
    },
    MediaCaptureFailureCode.bridgeOverloaded ||
    MediaCaptureFailureCode.presentationConflict ||
    MediaCaptureFailureCode.transferStoreOverloaded => const <String>{
      'operation',
      'capacity',
    },
    MediaCaptureFailureCode.transferStoreUnavailable => const <String>{
      'operation',
      'lifecycleReason',
    },
    MediaCaptureFailureCode.materializedMediaInvalid => const <String>{
      'operation',
    },
    MediaCaptureFailureCode.listenerAlreadyActive => const <String>{},
    _ => const <String>{'operation', 'capabilityFailureId'},
  };
}

MediaCaptureFailureCode? _failureCodeByWireName(String wireName) {
  for (final value in MediaCaptureFailureCode.values) {
    if (value.wireName == wireName) {
      return value;
    }
  }
  return null;
}

MediaCaptureCapabilityFailure? _capabilityFailureForCode(
  MediaCaptureFailureCode code,
) {
  for (final value in MediaCaptureCapabilityFailure.values) {
    if (value.wireName == code.wireName) {
      return value;
    }
  }
  return null;
}

MediaCaptureOperation? _operationByWireName(String wireName) {
  for (final value in MediaCaptureOperation.values) {
    if (value.wireName == wireName) {
      return value;
    }
  }
  return null;
}

MediaCaptureFailureField? _fieldByWireName(String wireName) {
  for (final value in MediaCaptureFailureField.values) {
    if (value.wireName == wireName) {
      return value;
    }
  }
  return null;
}
