import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

import 'media_capture_models.dart';
import 'media_capture_wire_codec.dart';

typedef MediaCaptureRequestIdFactory = String Function();
typedef MediaCaptureMonotonicMillis = int Function();
typedef MediaCaptureEpochMillis = int Function();

const int _maxPendingRequests = 32;
const int _maxCompletedRequestTombstones = 4096;
const int _completedRequestTombstoneMillis = 300000;
const Duration _disposeWaitTimeout = Duration(seconds: 5);
const Duration _disposeCleanupTimeout = Duration(seconds: 5);
const List<Duration> _disposeCleanupRetryDelays = <Duration>[
  Duration(milliseconds: 50),
  Duration(milliseconds: 200),
  Duration(milliseconds: 500),
];
const int _maxPlatformEnvelopeBytes =
    mediaCaptureMaxThumbnailBytes + (64 * 1024);
const MethodCodec _boundedPlatformCodec = _BoundedMethodCodec(
  _maxPlatformEnvelopeBytes,
);
final Expando<Map<String, _ActiveEventListener>> _sharedEventListeners =
    Expando<Map<String, _ActiveEventListener>>();

final class MediaCaptureClient {
  MediaCaptureClient({
    MediaCaptureRequestIdFactory? requestIdFactory,
    MediaCaptureMonotonicMillis? monotonicMillis,
    MediaCaptureEpochMillis? epochMillis,
  }) : _requestIdFactory = requestIdFactory ?? _secureRequestId,
       _monotonicMillis = monotonicMillis,
       _epochMillis = epochMillis ?? _systemEpochMillis,
       _commands = const MethodChannel(
         mediaCaptureCommandsChannel,
         _boundedPlatformCodec,
       ),
       _events = const EventChannel(
         mediaCaptureEventsChannel,
         _boundedPlatformCodec,
       ),
       _eventLifecycle = const MethodChannel(
         mediaCaptureEventsChannel,
         _boundedPlatformCodec,
       );

  final MediaCaptureRequestIdFactory _requestIdFactory;
  final MediaCaptureMonotonicMillis? _monotonicMillis;
  final MediaCaptureEpochMillis _epochMillis;
  final MethodChannel _commands;
  final EventChannel _events;
  final MethodChannel _eventLifecycle;
  final MediaCaptureWireCodec _codec = const MediaCaptureWireCodec();
  final Stopwatch _stopwatch = Stopwatch()..start();
  final Map<String, _PendingRequest> _pending = <String, _PendingRequest>{};
  final Map<String, int> _completedRequestTombstones = <String, int>{};
  final List<_DisposeCleanup> _retainedDisposeCleanups = <_DisposeCleanup>[];

  _ActiveEventListener? _activeEventListener;
  String? _activePresentationRequestId;
  Future<void>? _disposeFuture;
  bool _presentationReserved = false;
  bool _disposeRequested = false;
  bool _disposed = false;
  int _listenerGeneration = 0;

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _disposeRequested = true;
    final completer = Completer<void>();
    _disposeFuture = completer.future;
    unawaited(_completeDispose(completer));
    return completer.future;
  }

  Future<void> _completeDispose(Completer<void> completer) async {
    try {
      await _performDispose();
      completer.complete();
    } on Object catch (error, stackTrace) {
      _disposeFuture = null;
      completer.completeError(error, stackTrace);
    }
  }

  Future<void> _performDispose() async {
    var cleanupIncomplete = false;
    final presentationRequestId = _activePresentationRequestId;
    if (presentationRequestId != null) {
      try {
        await _dismissCaptureFlowForDispose(presentationRequestId);
      } on Object {
        cleanupIncomplete = true;
      }
    }
    final listener = _activeEventListener;
    final listenerTermination = listener == null
        ? null
        : _terminateEventListener(listener, cancelNative: true);
    final pending = List<_PendingRequest>.of(_pending.values);
    if (pending.isNotEmpty) {
      try {
        await Future.wait(
          pending.map((request) => request.done),
        ).timeout(_disposeWaitTimeout);
      } on TimeoutException {
        // Late results retain their cleanup policy and are never delivered as
        // resources after disposal wins the generation.
        cleanupIncomplete = true;
      }
    }
    if (listenerTermination != null) {
      try {
        await listenerTermination.timeout(_disposeWaitTimeout);
      } on TimeoutException {
        // The local handler is already detached synchronously. Native cleanup
        // may finish later without keeping dispose pending forever.
        cleanupIncomplete = true;
      }
    }
    try {
      if (!await _retryRetainedDisposeCleanups().timeout(
        _disposeCleanupTimeout,
      )) {
        cleanupIncomplete = true;
      }
    } on TimeoutException {
      cleanupIncomplete = true;
    }
    if (cleanupIncomplete) {
      throw const MediaCaptureDisposalException();
    }
    _completedRequestTombstones.clear();
    _disposed = true;
  }

  Future<MediaCaptureCallResult<MediaCaptureSession>> startSession(
    MediaCaptureConfig config,
  ) {
    return _invoke(
      methodStartSession,
      () => _codec.startSessionPayload(config),
      (value, requestId, stackTrace) => _codec.decodeSessionCreated(
        value,
        requestId: requestId,
        operation: methodStartSession,
        stackTrace: stackTrace,
      ),
      disposeCleanup: _cancelSessionForDispose,
    );
  }

  Future<MediaCaptureCallResult<MediaCapturePreview>> takePhoto(
    MediaCaptureSession session,
  ) {
    return _invoke(
      methodTakePhoto,
      () => _codec.sessionActionPayload(session),
      (value, requestId, stackTrace) => _codec.decodeMediaPreview(
        value,
        requestId: requestId,
        operation: methodTakePhoto,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureRecordingStarted>> startRecording(
    MediaCaptureSession session,
  ) {
    return _invoke(
      methodStartRecording,
      () => _codec.sessionActionPayload(session),
      (value, requestId, stackTrace) => _codec.decodeRecordingStarted(
        value,
        requestId: requestId,
        operation: methodStartRecording,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCapturePreview>> stopRecording(
    MediaCaptureSession session,
  ) {
    return _invoke(
      methodStopRecording,
      () => _codec.sessionActionPayload(session),
      (value, requestId, stackTrace) => _codec.decodeMediaPreview(
        value,
        requestId: requestId,
        operation: methodStopRecording,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureControlApplied>> switchCamera(
    MediaCaptureSession session,
  ) {
    return _invoke(
      methodSwitchCamera,
      () => _codec.sessionActionPayload(session),
      (value, requestId, stackTrace) => _codec.decodeControlApplied(
        value,
        requestId: requestId,
        operation: methodSwitchCamera,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureControlApplied>> setFlashMode({
    required MediaCaptureSession session,
    required MediaCaptureFlashMode flashMode,
  }) {
    return _invoke(
      methodSetFlashMode,
      () => _codec.flashModePayload(session: session, flashMode: flashMode),
      (value, requestId, stackTrace) => _codec.decodeControlApplied(
        value,
        requestId: requestId,
        operation: methodSetFlashMode,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureControlApplied>> setFocusPoint({
    required MediaCaptureSession session,
    required double normalizedX,
    required double normalizedY,
  }) {
    return _invoke(
      methodSetFocusPoint,
      () => _codec.focusPointPayload(
        session: session,
        normalizedX: normalizedX,
        normalizedY: normalizedY,
      ),
      (value, requestId, stackTrace) => _codec.decodeControlApplied(
        value,
        requestId: requestId,
        operation: methodSetFocusPoint,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureControlApplied>> setZoom({
    required MediaCaptureSession session,
    required double zoomFactor,
  }) {
    return _invoke(
      methodSetZoom,
      () => _codec.zoomPayload(session: session, zoomFactor: zoomFactor),
      (value, requestId, stackTrace) => _codec.decodeControlApplied(
        value,
        requestId: requestId,
        operation: methodSetZoom,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (_) => _cancelSessionForDispose(session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureRetakeReady>> retake(
    MediaCaptureMediaHandle mediaHandle,
  ) {
    return _invoke(
      methodRetake,
      () => _codec.mediaHandlePayload(mediaHandle),
      (value, requestId, stackTrace) => _codec.decodeRetakeReady(
        value,
        requestId: requestId,
        operation: methodRetake,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (value) => _cancelSessionForDispose(value.session),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureConfirmedMedia>> confirm(
    MediaCaptureMediaHandle mediaHandle,
  ) {
    return _invoke(
      methodConfirm,
      () => _codec.mediaHandlePayload(mediaHandle),
      (value, requestId, stackTrace) => _codec.decodeConfirmedMedia(
        value,
        requestId: requestId,
        operation: methodConfirm,
        expectedMediaHandle: mediaHandle.value,
        stackTrace: stackTrace,
      ),
      disposeCleanup: _releaseMediaForDispose,
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureSessionCancelled>> cancel(
    MediaCaptureSession session,
  ) {
    return _invoke(
      methodCancel,
      () => _codec.sessionActionPayload(session),
      (value, requestId, stackTrace) => _codec.decodeSessionCancelled(
        value,
        requestId: requestId,
        operation: methodCancel,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureMediaReleased>> releaseMedia(
    MediaCaptureMediaHandle mediaHandle,
  ) {
    return _invoke(
      methodReleaseMedia,
      () => _codec.mediaHandlePayload(mediaHandle),
      (value, requestId, stackTrace) => _codec.decodeMediaReleased(
        value,
        requestId: requestId,
        operation: methodReleaseMedia,
        expectedMediaHandle: mediaHandle.value,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureMaterializedMedia>>
  materializeMedia(MediaCaptureConfirmedMedia media) {
    return _invoke(
      methodMaterializeMediaResource,
      () => _codec.materializeMediaPayload(media.mediaHandle),
      (value, requestId, stackTrace) => _codec.decodeMaterializedMedia(
        value,
        requestId: requestId,
        nowEpochMillis: _epochMillis(),
        expectedMediaType: media.mediaType,
        expectedByteLength: media.byteLength,
        expectedDurationMillis: media.durationMillis,
        stackTrace: stackTrace,
      ),
      disposeCleanup: _releaseMaterializedForDispose,
      rejectedResultCleanup: _releaseRejectedMaterializedResult,
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureMaterializedMediaReleased>>
  releaseMaterializedMedia(MediaCaptureExportHandle exportHandle) {
    return _invoke(
      methodReleaseMaterializedMedia,
      () => _codec.exportHandlePayload(exportHandle),
      (value, requestId, stackTrace) => _codec.decodeMaterializedMediaReleased(
        value,
        requestId: requestId,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<MediaCaptureCallResult<MediaCaptureThumbnail>> readMediaThumbnail(
    MediaCaptureThumbnailRequest request,
  ) {
    return _invoke(
      methodReadMediaThumbnail,
      () => _codec.thumbnailPayload(request),
      (value, requestId, stackTrace) => _codec.decodeThumbnail(
        value,
        requestId: requestId,
        operation: methodReadMediaThumbnail,
        expectedMediaHandle: request.mediaHandle.value,
        maxPixelEdge: request.maxPixelEdge,
        stackTrace: stackTrace,
      ),
      disposeCleanup: (value) async =>
          clearMediaCaptureThumbnailForDisposal(value),
    );
  }

  Future<MediaCaptureFlowOutcome> presentCaptureFlow(
    MediaCaptureConfig config,
  ) async {
    if (_disposeRequested || _disposed) {
      return MediaCaptureFlowFailure(
        _bridgeUnavailable(MediaCaptureOperation.presentCaptureFlow),
      );
    }
    if (_presentationReserved) {
      return const MediaCaptureFlowFailure(
        MediaCaptureFailure(
          code: MediaCaptureFailureCode.presentationConflict,
          diagnostics: MediaCaptureFailureDiagnostics(
            operation: MediaCaptureOperation.presentCaptureFlow,
            capacity: MediaCaptureCapacity.activePresentation,
          ),
        ),
      );
    }
    _presentationReserved = true;
    try {
      final result = await _invoke<MediaCaptureFlowOutcome>(
        methodPresentCaptureFlow,
        () => _codec.startSessionPayload(config),
        (value, requestId, stackTrace) {
          final outcome = _codec.decodeCaptureFlow(
            value,
            requestId: requestId,
            stackTrace: stackTrace,
          );
          return MediaCaptureCallResult<MediaCaptureFlowOutcome>.success(
            outcome,
          );
        },
        disposeCleanup: (outcome) async {
          if (outcome is MediaCaptureFlowConfirmed) {
            await _releaseMediaForDispose(outcome.media);
          }
        },
        onReserved: (requestId) => _activePresentationRequestId = requestId,
        onSettled: (requestId) {
          if (_activePresentationRequestId == requestId) {
            _activePresentationRequestId = null;
          }
        },
      );
      return switch (result) {
        MediaCaptureCallSuccess<MediaCaptureFlowOutcome>(:final value) => value,
        MediaCaptureCallFailure<MediaCaptureFlowOutcome>(:final failure) =>
          MediaCaptureFlowFailure(failure),
      };
    } finally {
      _presentationReserved = false;
    }
  }

  Future<bool> dismissActivePresentation() async {
    final presentationRequestId = _activePresentationRequestId;
    if (presentationRequestId == null) return true;
    final result = await _invoke<bool>(
      methodDismissCaptureFlow,
      () => _codec.presentationRequestPayload(presentationRequestId),
      (value, requestId, stackTrace) => _codec.decodeCaptureFlowDismissed(
        value,
        requestId: requestId,
        stackTrace: stackTrace,
      ),
    );
    return result is MediaCaptureCallSuccess<bool>;
  }

  Stream<MediaCaptureEvent> listenEvents() {
    late final StreamController<MediaCaptureEvent> controller;
    _ActiveEventListener? claimedListener;
    controller = StreamController<MediaCaptureEvent>();
    controller.onListen = () {
      if (_disposeRequested || _disposed) {
        controller.add(
          MediaCaptureBridgeFailureEvent(
            _bridgeUnavailable(MediaCaptureOperation.unknownOperation),
          ),
        );
        unawaited(controller.close());
        return;
      }
      if (_activeEventListener != null) {
        controller.add(
          const MediaCaptureBridgeFailureEvent(
            MediaCaptureFailure(
              code: MediaCaptureFailureCode.listenerAlreadyActive,
            ),
          ),
        );
        unawaited(controller.close());
        return;
      }
      final listener = _ActiveEventListener(
        generation: _listenerGeneration + 1,
        controller: controller,
      );
      if (!_acquireSharedEventListener(listener)) {
        controller.add(
          const MediaCaptureBridgeFailureEvent(
            MediaCaptureFailure(
              code: MediaCaptureFailureCode.listenerAlreadyActive,
            ),
          ),
        );
        unawaited(controller.close());
        return;
      }
      _listenerGeneration = listener.generation;
      _activeEventListener = listener;
      claimedListener = listener;
      listener.activation = _activateEventListener(listener);
    };
    controller.onCancel = () {
      final listener = claimedListener;
      if (listener == null) {
        return null;
      }
      if (listener.terminating) {
        return null;
      }
      return _terminateEventListener(
        listener,
        cancelNative: true,
        closeController: false,
      );
    };
    return controller.stream;
  }

  Future<void> _activateEventListener(_ActiveEventListener listener) async {
    // Awaiting the EventChannel lifecycle methods prevents an old cancel from
    // overtaking the next listener generation.
    _events.binaryMessenger.setMessageHandler(_events.name, (message) async {
      if (_disposeRequested ||
          !identical(_activeEventListener, listener) ||
          listener.terminating ||
          !_ownsSharedEventListener(listener)) {
        return null;
      }
      if (message == null) {
        _clearEventHandler(listener);
        _handleNativeEventDone(listener);
        return null;
      }
      try {
        _handleNativeEvent(listener, _events.codec.decodeEnvelope(message));
      } on PlatformException catch (error, stackTrace) {
        _handleNativeEventError(listener, error, stackTrace);
      } on Object catch (error, stackTrace) {
        _handleNativeEventError(listener, error, stackTrace);
      }
      return null;
    });
    try {
      await _eventLifecycle.invokeMethod<void>(
        'listen',
        _codec.listenEnvelope(),
      );
    } on PlatformException catch (error, stackTrace) {
      _handleEventActivationError(listener, error, stackTrace);
    } on MissingPluginException catch (_, stackTrace) {
      _handleEventActivationError(
        listener,
        _bridgeUnavailable(
          MediaCaptureOperation.unknownOperation,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      _handleEventActivationError(listener, error, stackTrace);
    }
  }

  void _clearEventHandler(_ActiveEventListener listener) {
    if (identical(_activeEventListener, listener) &&
        _ownsSharedEventListener(listener)) {
      _events.binaryMessenger.setMessageHandler(_events.name, null);
    }
  }

  void _handleNativeEvent(_ActiveEventListener listener, Object? value) {
    if (_disposeRequested ||
        !identical(_activeEventListener, listener) ||
        listener.terminating ||
        !_ownsSharedEventListener(listener)) {
      return;
    }
    listener.controller.add(_codec.decodeEvent(value));
  }

  void _handleNativeEventError(
    _ActiveEventListener listener,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!identical(_activeEventListener, listener) || listener.terminating) {
      return;
    }
    listener.controller.add(
      MediaCaptureBridgeFailureEvent(_eventFailure(error, stackTrace)),
    );
    unawaited(_terminateEventListener(listener, cancelNative: true));
  }

  void _handleEventActivationError(
    _ActiveEventListener listener,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!identical(_activeEventListener, listener) || listener.terminating) {
      return;
    }
    listener.controller.add(
      MediaCaptureBridgeFailureEvent(_eventFailure(error, stackTrace)),
    );
    unawaited(_terminateEventListener(listener, cancelNative: false));
  }

  MediaCaptureFailure _eventFailure(Object error, StackTrace stackTrace) {
    return switch (error) {
      PlatformException() => _codec.eventChannelExceptionToFailure(
        error,
        stackTrace,
      ),
      MediaCaptureFailure() => error,
      _ => _invalidWirePayload(stackTrace: stackTrace),
    };
  }

  void _handleNativeEventDone(_ActiveEventListener listener) {
    if (!identical(_activeEventListener, listener) || listener.terminating) {
      return;
    }
    unawaited(_terminateEventListener(listener, cancelNative: false));
  }

  Future<void> _terminateEventListener(
    _ActiveEventListener listener, {
    required bool cancelNative,
    bool closeController = true,
  }) {
    final existing = listener.termination;
    if (existing != null) {
      return existing;
    }
    listener.terminating = true;
    _clearEventHandler(listener);
    final future = _performEventListenerTermination(
      listener,
      cancelNative: cancelNative,
      closeController: closeController,
    );
    listener.termination = future;
    return future;
  }

  Future<void> _performEventListenerTermination(
    _ActiveEventListener listener, {
    required bool cancelNative,
    required bool closeController,
  }) async {
    try {
      if (cancelNative) {
        final activation = listener.activation;
        if (activation != null) {
          await activation;
        }
        _clearEventHandler(listener);
        await _eventLifecycle.invokeMethod<void>(
          'cancel',
          _codec.listenEnvelope(),
        );
      } else {
        _clearEventHandler(listener);
      }
    } on Object {
      // The Dart handler is already detached; the local slot must still be
      // released deterministically if the platform acknowledgement fails.
    } finally {
      if (identical(_activeEventListener, listener)) {
        _activeEventListener = null;
      }
      _releaseSharedEventListener(listener);
      if (closeController && !listener.controller.isClosed) {
        await listener.controller.close();
      }
    }
  }

  Future<MediaCaptureCallResult<T>> _invoke<T>(
    String method,
    WireMap Function() payloadFactory,
    MediaCaptureCallResult<T> Function(
      Object? value,
      String requestId,
      StackTrace? stackTrace,
    )
    decoder, {
    Future<void> Function(T value)? disposeCleanup,
    Future<void> Function(Object? value, String requestId)?
    rejectedResultCleanup,
    void Function(String requestId)? onReserved,
    void Function(String requestId)? onSettled,
  }) async {
    final operation = _operationFromMethod(method);
    if (_disposeRequested || _disposed) {
      return MediaCaptureCallResult<T>.failure(_bridgeUnavailable(operation));
    }
    late final String requestId;
    WireMap envelope;
    try {
      requestId = _requestIdFactory();
      envelope = _codec.requestEnvelope(
        requestId: requestId,
        payload: payloadFactory(),
      );
    } on MediaCaptureWireEncodeException catch (error, stackTrace) {
      return MediaCaptureCallResult<T>.failure(
        error.toFailure(operation: method, stackTrace: stackTrace),
      );
    } on Object catch (_, stackTrace) {
      return MediaCaptureCallResult<T>.failure(
        _wireEncodingFailure(operation, stackTrace),
      );
    }
    final pending = _PendingRequest();
    final reservationFailure = _reserveRequest(requestId, pending, operation);
    if (reservationFailure != null) {
      return MediaCaptureCallResult<T>.failure(reservationFailure);
    }
    onReserved?.call(requestId);
    try {
      final value = await _commands.invokeMethod<Object?>(method, envelope);
      final decoded = decoder(value, requestId, StackTrace.current);
      if (decoded is MediaCaptureCallFailure<T>) {
        final cleanup = rejectedResultCleanup;
        if (cleanup != null) {
          await cleanup(value, requestId);
        }
      }
      if (_disposeRequested) {
        if (decoded is MediaCaptureCallSuccess<T>) {
          final cleanup = disposeCleanup;
          if (cleanup != null) {
            final retained = _DisposeCleanup(() => cleanup(decoded.value));
            if (!await _attemptDisposeCleanup(retained)) {
              _retainedDisposeCleanups.add(retained);
            }
          }
        }
        return MediaCaptureCallResult<T>.failure(_bridgeUnavailable(operation));
      }
      return decoded;
    } on PlatformException catch (error, stackTrace) {
      return MediaCaptureCallResult<T>.failure(
        _codec.platformExceptionToFailure(
          error,
          stackTrace,
          operation: operation,
        ),
      );
    } on MissingPluginException catch (_, stackTrace) {
      return MediaCaptureCallResult<T>.failure(
        _bridgeUnavailable(operation, stackTrace: stackTrace),
      );
    } on Object catch (_, stackTrace) {
      return MediaCaptureCallResult<T>.failure(
        _invalidWirePayload(stackTrace: stackTrace),
      );
    } finally {
      onSettled?.call(requestId);
      _pending.remove(requestId);
      if (!_disposed) {
        _completedRequestTombstones[requestId] = _nowMillis();
      }
      pending.complete();
    }
  }

  Future<void> _dismissCaptureFlowForDispose(
    String presentationRequestId,
  ) async {
    await _invokeDisposeCleanup<bool>(
      method: methodDismissCaptureFlow,
      payload: _codec.presentationRequestPayload(presentationRequestId),
      decoder: (value, requestId, stackTrace) =>
          _codec.decodeCaptureFlowDismissed(
            value,
            requestId: requestId,
            stackTrace: stackTrace,
          ),
    );
  }

  bool _acquireSharedEventListener(_ActiveEventListener listener) {
    final messenger = _events.binaryMessenger;
    final listeners =
        _sharedEventListeners[messenger] ?? <String, _ActiveEventListener>{};
    if (listeners.containsKey(_events.name)) return false;
    listeners[_events.name] = listener;
    _sharedEventListeners[messenger] = listeners;
    return true;
  }

  bool _ownsSharedEventListener(_ActiveEventListener listener) {
    return identical(
      _sharedEventListeners[_events.binaryMessenger]?[_events.name],
      listener,
    );
  }

  void _releaseSharedEventListener(_ActiveEventListener listener) {
    final listeners = _sharedEventListeners[_events.binaryMessenger];
    if (identical(listeners?[_events.name], listener)) {
      listeners!.remove(_events.name);
    }
  }

  Future<void> _cancelSessionForDispose(MediaCaptureSession session) async {
    await _invokeDisposeCleanup<MediaCaptureSessionCancelled>(
      method: methodCancel,
      payload: _codec.sessionActionPayload(session),
      decoder: (value, requestId, stackTrace) => _codec.decodeSessionCancelled(
        value,
        requestId: requestId,
        operation: methodCancel,
        expectedSessionHandle: session.handle,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<void> _releaseMediaForDispose(MediaCaptureConfirmedMedia media) async {
    await _invokeDisposeCleanup<MediaCaptureMediaReleased>(
      method: methodReleaseMedia,
      payload: _codec.mediaHandlePayload(media.mediaHandle),
      decoder: (value, requestId, stackTrace) => _codec.decodeMediaReleased(
        value,
        requestId: requestId,
        operation: methodReleaseMedia,
        expectedMediaHandle: media.mediaHandle.value,
        stackTrace: stackTrace,
      ),
    );
  }

  Future<void> _releaseMaterializedForDispose(
    MediaCaptureMaterializedMedia media,
  ) async {
    await _releaseExportHandleForDispose(media.exportHandle);
  }

  Future<void> _releaseRejectedMaterializedResult(
    Object? value,
    String requestId,
  ) async {
    final exportHandle = _codec.materializedExportHandleForCleanup(
      value,
      requestId: requestId,
    );
    if (exportHandle == null) return;
    final retained = _DisposeCleanup(
      () => _releaseExportHandleForDispose(exportHandle),
    );
    if (!await _attemptDisposeCleanup(retained)) {
      _retainedDisposeCleanups.add(retained);
    }
  }

  Future<void> _releaseExportHandleForDispose(
    MediaCaptureExportHandle exportHandle,
  ) async {
    await _invokeDisposeCleanup<MediaCaptureMaterializedMediaReleased>(
      method: methodReleaseMaterializedMedia,
      payload: _codec.exportHandlePayload(exportHandle),
      decoder: (value, requestId, stackTrace) =>
          _codec.decodeMaterializedMediaReleased(
            value,
            requestId: requestId,
            stackTrace: stackTrace,
          ),
    );
  }

  Future<void> _invokeDisposeCleanup<T>({
    required String method,
    required WireMap payload,
    required MediaCaptureCallResult<T> Function(
      Object? value,
      String requestId,
      StackTrace stackTrace,
    )
    decoder,
  }) async {
    final requestId = _secureRequestId();
    final envelope = _codec.requestEnvelope(
      requestId: requestId,
      payload: payload,
    );
    final value = await _commands
        .invokeMethod<Object?>(method, envelope)
        .timeout(_disposeCleanupTimeout);
    final decoded = decoder(value, requestId, StackTrace.current);
    if (decoded is! MediaCaptureCallSuccess<T>) {
      throw const _DisposeCleanupFailure();
    }
  }

  Future<bool> _attemptDisposeCleanup(_DisposeCleanup cleanup) async {
    try {
      await cleanup.action().timeout(_disposeCleanupTimeout);
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> _retryRetainedDisposeCleanups() async {
    for (final cleanup in List<_DisposeCleanup>.of(_retainedDisposeCleanups)) {
      var completed = false;
      for (final delayDuration in _disposeCleanupRetryDelays) {
        await Future<void>.delayed(delayDuration);
        if (await _attemptDisposeCleanup(cleanup)) {
          completed = true;
          break;
        }
      }
      if (completed) {
        _retainedDisposeCleanups.remove(cleanup);
      }
    }
    return _retainedDisposeCleanups.isEmpty;
  }

  MediaCaptureFailure? _reserveRequest(
    String requestId,
    _PendingRequest pending,
    MediaCaptureOperation operation,
  ) {
    _pruneCompletedRequestTombstones();
    if (_pending.containsKey(requestId) ||
        _completedRequestTombstones.containsKey(requestId)) {
      return MediaCaptureFailure(
        code: MediaCaptureFailureCode.duplicateRequest,
        diagnostics: MediaCaptureFailureDiagnostics(operation: operation),
      );
    }
    if (_pending.length >= _maxPendingRequests) {
      return MediaCaptureFailure(
        code: MediaCaptureFailureCode.bridgeOverloaded,
        diagnostics: MediaCaptureFailureDiagnostics(
          operation: operation,
          capacity: MediaCaptureCapacity.pendingRequests,
        ),
      );
    }
    if (_completedRequestTombstones.length + _pending.length >=
        _maxCompletedRequestTombstones) {
      return MediaCaptureFailure(
        code: MediaCaptureFailureCode.bridgeOverloaded,
        diagnostics: MediaCaptureFailureDiagnostics(
          operation: operation,
          capacity: MediaCaptureCapacity.completedRequestTombstones,
        ),
      );
    }
    _pending[requestId] = pending;
    return null;
  }

  void _pruneCompletedRequestTombstones() {
    final now = _nowMillis();
    _completedRequestTombstones.removeWhere(
      (_, completedAt) => now - completedAt >= _completedRequestTombstoneMillis,
    );
  }

  int _nowMillis() =>
      _monotonicMillis?.call() ?? _stopwatch.elapsedMilliseconds;
}

int _systemEpochMillis() => DateTime.now().millisecondsSinceEpoch;

final class _PendingRequest {
  final Completer<void> _completer = Completer<void>();

  Future<void> get done => _completer.future;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

final class _DisposeCleanup {
  const _DisposeCleanup(this.action);

  final Future<void> Function() action;
}

final class _DisposeCleanupFailure implements Exception {
  const _DisposeCleanupFailure();
}

final class _ActiveEventListener {
  _ActiveEventListener({required this.generation, required this.controller});

  final int generation;
  final StreamController<MediaCaptureEvent> controller;
  Future<void>? activation;
  Future<void>? termination;
  bool terminating = false;
}

String _secureRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

MediaCaptureFailure _bridgeUnavailable(
  MediaCaptureOperation operation, {
  StackTrace? stackTrace,
}) {
  return MediaCaptureFailure(
    code: MediaCaptureFailureCode.bridgeUnavailable,
    diagnostics: MediaCaptureFailureDiagnostics(
      operation: operation,
      lifecycleReason: MediaCaptureLifecycleReason.adapterDisposed,
    ),
  );
}

MediaCaptureFailure _invalidWirePayload({StackTrace? stackTrace}) {
  return MediaCaptureFailure(
    code: MediaCaptureFailureCode.invalidWirePayload,
    diagnostics: const MediaCaptureFailureDiagnostics(
      field: MediaCaptureFailureField.payload,
      reason: MediaCaptureFailureReason.typeMismatch,
    ),
  );
}

MediaCaptureFailure _wireEncodingFailure(
  MediaCaptureOperation operation,
  StackTrace stackTrace,
) {
  return MediaCaptureFailure(
    code: MediaCaptureFailureCode.wireEncodingFailed,
    diagnostics: MediaCaptureFailureDiagnostics(
      operation: operation,
      field: MediaCaptureFailureField.requestId,
      reason: MediaCaptureFailureReason.invalidFormat,
    ),
  );
}

MediaCaptureOperation _operationFromMethod(String method) {
  for (final operation in MediaCaptureOperation.values) {
    if (operation.wireName == method) {
      return operation;
    }
  }
  return MediaCaptureOperation.unknownOperation;
}

final class _BoundedMethodCodec implements MethodCodec {
  const _BoundedMethodCodec(this.maxEnvelopeBytes);

  final int maxEnvelopeBytes;
  static const StandardMethodCodec _delegate = StandardMethodCodec();

  @override
  MethodCall decodeMethodCall(ByteData? methodCall) {
    _checkSize(methodCall);
    return _delegate.decodeMethodCall(methodCall);
  }

  @override
  Object? decodeEnvelope(ByteData envelope) {
    _checkSize(envelope);
    return _delegate.decodeEnvelope(envelope) as Object?;
  }

  @override
  ByteData encodeErrorEnvelope({
    required String code,
    String? message,
    Object? details,
  }) => _delegate.encodeErrorEnvelope(
    code: code,
    message: message,
    details: details,
  );

  @override
  ByteData encodeMethodCall(MethodCall methodCall) =>
      _delegate.encodeMethodCall(methodCall);

  @override
  ByteData encodeSuccessEnvelope(Object? result) =>
      _delegate.encodeSuccessEnvelope(result);

  void _checkSize(ByteData? data) {
    if (data == null || data.lengthInBytes > maxEnvelopeBytes) {
      throw const FormatException('Invalid media capture platform envelope.');
    }
  }
}
