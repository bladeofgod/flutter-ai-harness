import 'dart:async';

import 'package:app_core/app_core.dart';

import '../resource/media_resource_models.dart';
import '../resource/media_resource_store.dart';
import 'media_playback_driver.dart';
import 'media_preview_models.dart';
import 'video_player_media_playback_driver.dart';

abstract interface class MediaPlaybackProbe {
  Future<MediaResourceResult<MediaPlaybackInfo>> probe(
    MediaResourceId resourceId, {
    MediaPreviewCancellation? cancellation,
  });
}

MediaPlaybackProbe createMediaPlaybackProbe({
  required MediaResourceStore store,
}) {
  return DefaultMediaPlaybackProbe(
    store: store,
    driverFactory: const VideoPlayerMediaPlaybackDriverFactory(),
  );
}

final class DefaultMediaPlaybackProbe implements MediaPlaybackProbe {
  const DefaultMediaPlaybackProbe({
    required MediaResourceStore store,
    required MediaPlaybackDriverFactory driverFactory,
  }) : _store = store,
       _driverFactory = driverFactory;

  final MediaResourceStore _store;
  final MediaPlaybackDriverFactory _driverFactory;

  @override
  Future<MediaResourceResult<MediaPlaybackInfo>> probe(
    MediaResourceId resourceId, {
    MediaPreviewCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return _failure(MediaResourceFailureCode.cancelled);
    }
    final cancellationSignal = Completer<void>();
    void cancel() {
      if (!cancellationSignal.isCompleted) cancellationSignal.complete();
    }

    cancellation?.addListener(cancel);
    if (cancellation?.isCancelled ?? false) cancel();
    MediaResourceLease? lease;
    MediaPlaybackDriver? driver;
    try {
      final retainFuture = _store.retain(resourceId);
      final retainedOutcome = await _raceCancellation(
        retainFuture,
        cancellationSignal.future,
      );
      if (retainedOutcome
          is _Cancelled<MediaResourceResult<MediaResourceLease>>) {
        unawaited(_releaseLateRetain(_store, retainFuture));
        return _failure(MediaResourceFailureCode.cancelled);
      }
      if (retainedOutcome
          case _Failed<MediaResourceResult<MediaResourceLease>>()) {
        return _failure(MediaResourceFailureCode.playbackFailed);
      }
      final retained =
          (retainedOutcome
                  as _Completed<MediaResourceResult<MediaResourceLease>>)
              .value;
      if (retained case MediaResourceError<MediaResourceLease>(
        :final failure,
      )) {
        return MediaResourceResult<MediaPlaybackInfo>.failure(failure);
      }
      lease = (retained as MediaResourceSuccess<MediaResourceLease>).value;
      final resolvedOutcome = await _raceCancellation(
        _store.resolve(resourceId, lease),
        cancellationSignal.future,
      );
      if (resolvedOutcome
          is _Cancelled<MediaResourceResult<ResolvedMediaResource>>) {
        return _failure(MediaResourceFailureCode.cancelled);
      }
      if (resolvedOutcome
          case _Failed<MediaResourceResult<ResolvedMediaResource>>()) {
        return _failure(MediaResourceFailureCode.playbackFailed);
      }
      final resolvedResult =
          (resolvedOutcome
                  as _Completed<MediaResourceResult<ResolvedMediaResource>>)
              .value;
      if (resolvedResult case MediaResourceError<ResolvedMediaResource>(
        :final failure,
      )) {
        return MediaResourceResult<MediaPlaybackInfo>.failure(failure);
      }
      final resolved =
          (resolvedResult as MediaResourceSuccess<ResolvedMediaResource>).value;
      if (resolved.kind != MediaResourceKind.video) {
        return _failure(MediaResourceFailureCode.invalidArgument);
      }
      driver = _driverFactory.create(resolved.fileUri);
      final initializeOutcome = await _raceCancellation(
        driver.initialize(),
        cancellationSignal.future,
      );
      if (initializeOutcome is _Cancelled<void>) {
        return _failure(MediaResourceFailureCode.cancelled);
      }
      if (initializeOutcome case _Failed<void>(:final error)) {
        if (error is UnsupportedMediaPlaybackException) {
          return _failure(MediaResourceFailureCode.unsupportedMedia);
        }
        return _failure(MediaResourceFailureCode.playbackFailed);
      }
      final snapshot = driver.snapshot;
      if (!snapshot.isInitialized || snapshot.duration <= Duration.zero) {
        return _failure(MediaResourceFailureCode.unsupportedMedia);
      }
      return MediaResourceResult<MediaPlaybackInfo>.success(
        MediaPlaybackInfo(duration: snapshot.duration),
      );
    } on UnsupportedMediaPlaybackException {
      return _failure(MediaResourceFailureCode.unsupportedMedia);
    } on Object {
      return _failure(MediaResourceFailureCode.playbackFailed);
    } finally {
      cancellation?.removeListener(cancel);
      try {
        await driver?.dispose();
      } on Object {
        // Cleanup failures do not expose platform details or skip the lease.
      } finally {
        if (lease != null) {
          try {
            await _store.release(lease);
          } on Object {
            // The typed probe result must not leak Store implementation errors.
          }
        }
      }
    }
  }
}

Future<void> _releaseLateRetain(
  MediaResourceStore store,
  Future<MediaResourceResult<MediaResourceLease>> retainFuture,
) async {
  try {
    final retained = await retainFuture;
    if (retained case MediaResourceSuccess<MediaResourceLease>(:final value)) {
      await store.release(value);
    }
  } on Object {
    // The caller has already received a typed cancellation result.
  }
}

sealed class _CancellableOutcome<T> {
  const _CancellableOutcome();
}

final class _Completed<T> extends _CancellableOutcome<T> {
  const _Completed(this.value);

  final T value;
}

final class _Failed<T> extends _CancellableOutcome<T> {
  const _Failed(this.error);

  final Object error;
}

final class _Cancelled<T> extends _CancellableOutcome<T> {
  const _Cancelled();
}

Future<_CancellableOutcome<T>> _raceCancellation<T>(
  Future<T> operation,
  Future<void> cancellation,
) {
  return Future.any(<Future<_CancellableOutcome<T>>>[
    operation.then<_CancellableOutcome<T>>(
      _Completed<T>.new,
      onError: (Object error, StackTrace _) => _Failed<T>(error),
    ),
    cancellation.then<_CancellableOutcome<T>>((_) => _Cancelled<T>()),
  ]);
}

MediaResourceError<T> _failure<T>(MediaResourceFailureCode code) {
  return MediaResourceError<T>(
    MediaResourceFailure(
      code: code,
      isRecoverable:
          code == MediaResourceFailureCode.cancelled ||
          code == MediaResourceFailureCode.playbackFailed,
    ),
  );
}
