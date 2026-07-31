import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:app_core/app_core.dart';
import 'package:flutter/foundation.dart';

import '../resource/media_resource_models.dart';
import '../resource/media_resource_store.dart';
import 'media_poster_generator.dart';
import 'media_preview_models.dart';
import 'video_thumbnail_poster_generator.dart';

abstract interface class MediaPosterService {
  Future<MediaResourceResult<MediaPoster>> generate(
    MediaResourceId resourceId, {
    MediaPreviewCancellation? cancellation,
  });
}

MediaPosterService createMediaPosterService({
  required MediaResourceStore store,
}) {
  return DefaultMediaPosterService(
    store: store,
    generator: VideoThumbnailPosterGenerator(),
  );
}

final class DefaultMediaPosterService implements MediaPosterService {
  DefaultMediaPosterService({
    required MediaResourceStore store,
    required MediaPosterGenerator generator,
    Duration deadline = const Duration(seconds: 10),
  }) : _store = store,
       _generator = generator,
       _deadline = deadline;

  static const int _jpegQuality = 82;
  static const int maximumOutstandingJobs = 32;
  static final _PosterScheduler _scheduler = _PosterScheduler(
    maximumConcurrent: 2,
    maximumOutstanding: maximumOutstandingJobs,
  );

  final MediaResourceStore _store;
  final MediaPosterGenerator _generator;
  final Duration _deadline;

  @override
  Future<MediaResourceResult<MediaPoster>> generate(
    MediaResourceId resourceId, {
    MediaPreviewCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return _failure(MediaResourceFailureCode.cancelled);
    }
    final reservation = _scheduler.tryReserve();
    if (reservation == null) {
      return _failure(MediaResourceFailureCode.overloaded);
    }
    final elapsed = Stopwatch()..start();
    final interrupted = Completer<void>();
    void interrupt() {
      if (!interrupted.isCompleted) interrupted.complete();
    }

    cancellation?.addListener(interrupt);
    final timer = Timer(_deadline, interrupt);
    final retainFuture = _store.retain(resourceId);
    late final bool retainWon;
    try {
      try {
        retainWon = await Future.any<bool>(<Future<bool>>[
          retainFuture.then((_) => true),
          interrupted.future.then((_) => false),
        ]);
      } on Object {
        reservation.release();
        return _failure(MediaResourceFailureCode.decodeFailed);
      }
    } finally {
      timer.cancel();
      cancellation?.removeListener(interrupt);
    }
    if (!retainWon) {
      reservation.release();
      unawaited(_releaseLateRetain(retainFuture));
      return _failure(MediaResourceFailureCode.cancelled);
    }
    final retained = await retainFuture;
    if (retained case MediaResourceError<MediaResourceLease>(:final failure)) {
      reservation.release();
      return MediaResourceResult<MediaPoster>.failure(failure);
    }
    final lease = (retained as MediaResourceSuccess<MediaResourceLease>).value;
    final remaining = _deadline - elapsed.elapsed;
    if (remaining <= Duration.zero || (cancellation?.isCancelled ?? false)) {
      try {
        await _store.release(lease);
      } on Object {
        // The caller still receives the earlier typed cancellation result.
      } finally {
        reservation.release();
      }
      return _failure(MediaResourceFailureCode.cancelled);
    }
    final job = _PosterJob(
      store: _store,
      lease: lease,
      resourceId: resourceId,
      generator: _generator,
      deadline: remaining,
      cancellation: cancellation,
      reservation: reservation,
    );
    _scheduler.enqueue(job);
    return job.result;
  }

  Future<void> _releaseLateRetain(
    Future<MediaResourceResult<MediaResourceLease>> retainFuture,
  ) async {
    try {
      final retained = await retainFuture;
      if (retained case MediaResourceSuccess<MediaResourceLease>(
        :final value,
      )) {
        await _store.release(value);
      }
    } on Object {
      // The caller has already received a typed cancellation result.
    }
  }
}

final class _PosterScheduler {
  _PosterScheduler({
    required this.maximumConcurrent,
    required this.maximumOutstanding,
  });

  final int maximumConcurrent;
  final int maximumOutstanding;
  final List<_PosterJob> _queue = <_PosterJob>[];
  int _active = 0;
  int _outstanding = 0;

  _PosterReservation? tryReserve() {
    if (_outstanding >= maximumOutstanding) return null;
    _outstanding += 1;
    return _PosterReservation(() => _outstanding -= 1);
  }

  void enqueue(_PosterJob job) {
    _queue.add(job);
    job.arm(() => _queue.remove(job));
    _drain();
  }

  void _drain() {
    while (_active < maximumConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active += 1;
      unawaited(
        job.run().whenComplete(() {
          _active -= 1;
          _drain();
        }),
      );
    }
  }
}

final class _PosterReservation {
  _PosterReservation(this._onRelease);

  final VoidCallback _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}

final class _PosterJob {
  _PosterJob({
    required this.store,
    required this.lease,
    required this.resourceId,
    required this.generator,
    required this.deadline,
    required this.cancellation,
    required this.reservation,
  });

  final MediaResourceStore store;
  final MediaResourceLease lease;
  final MediaResourceId resourceId;
  final MediaPosterGenerator generator;
  final Duration deadline;
  final MediaPreviewCancellation? cancellation;
  final _PosterReservation reservation;
  final Completer<MediaResourceResult<MediaPoster>> _caller = Completer();
  final Completer<void> _finished = Completer<void>();
  final Completer<void> _nativeSettled = Completer<void>();
  bool Function()? _removeFromQueue;
  Future<void>? _finishFuture;
  VoidCallback? _cancellationListener;
  Timer? _timer;
  bool _started = false;

  Future<MediaResourceResult<MediaPoster>> get result => _caller.future;

  void arm(bool Function() removeFromQueue) {
    _removeFromQueue = removeFromQueue;
    void cancel() {
      unawaited(_finish(_failure(MediaResourceFailureCode.cancelled)));
    }

    _cancellationListener = cancel;
    cancellation?.addListener(cancel);
    _timer = Timer(
      deadline,
      () => unawaited(_finish(_failure(MediaResourceFailureCode.cancelled))),
    );
    if (cancellation?.isCancelled ?? false) {
      cancel();
    }
  }

  Future<void> run() async {
    if (_started || _finishFuture != null) {
      await _finished.future;
      return;
    }
    _started = true;
    _removeFromQueue = null;
    if (cancellation?.isCancelled ?? false) {
      await _finish(_failure(MediaResourceFailureCode.cancelled));
      return;
    }
    final resolve = store.resolve(resourceId, lease);
    unawaited(
      resolve.then(_handleResolved, onError: (_) => _handleResolveFailure()),
    );
    await _nativeSettled.future;
  }

  Future<void> _handleResolved(
    MediaResourceResult<ResolvedMediaResource> resolvedResult,
  ) async {
    if (_finishFuture != null) {
      _settleNative();
      return;
    }
    if (resolvedResult case MediaResourceError<ResolvedMediaResource>(
      :final failure,
    )) {
      _settleNative();
      await _finish(MediaResourceResult<MediaPoster>.failure(failure));
      return;
    }
    final resolved =
        (resolvedResult as MediaResourceSuccess<ResolvedMediaResource>).value;
    if (resolved.kind != MediaResourceKind.video) {
      _settleNative();
      await _finish(_failure(MediaResourceFailureCode.invalidArgument));
      return;
    }
    final generation = Future<Uint8List?>.sync(
      () => generator.generateJpeg(
        resolved.fileUri,
        maximumDimension: MediaPoster.maximumDimension,
        quality: DefaultMediaPosterService._jpegQuality,
      ),
    );
    unawaited(
      generation.then(
        _handleGenerated,
        onError: (_) => _handleGenerationFailure(),
      ),
    );
  }

  Future<void> _handleGenerated(Uint8List? bytes) async {
    if (_finishFuture != null) {
      _clear(bytes);
      _settleNative();
      return;
    }
    try {
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > MediaPoster.maximumBytes) {
        _clear(bytes);
        _settleNative();
        await _finishDecodeFailure();
        return;
      }
      final sanitized = await _sanitizePoster(bytes);
      if (_finishFuture != null) {
        _clear(sanitized?.$1);
        return;
      }
      if (sanitized == null) {
        _settleNative();
        await _finishDecodeFailure();
        return;
      }
      late final MediaPoster poster;
      try {
        poster = MediaPoster.png(
          bytes: sanitized.$1,
          width: sanitized.$2,
          height: sanitized.$3,
        );
      } finally {
        _clear(sanitized.$1);
      }
      _settleNative();
      await _finish(MediaResourceResult<MediaPoster>.success(poster));
    } on Object {
      _settleNative();
      await _finishDecodeFailure();
    } finally {
      _settleNative();
    }
  }

  Future<void> _handleResolveFailure() async {
    _settleNative();
    await _finishDecodeFailure();
  }

  Future<void> _handleGenerationFailure() async {
    _settleNative();
    await _finishDecodeFailure();
  }

  void _settleNative() {
    if (!_nativeSettled.isCompleted) _nativeSettled.complete();
  }

  Future<void> _finishDecodeFailure() {
    return _finish(_failure(MediaResourceFailureCode.decodeFailed));
  }

  Future<void> _finish(MediaResourceResult<MediaPoster> result) {
    final active = _finishFuture;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performFinish(result);
    _finishFuture = operation;
    return operation;
  }

  Future<void> _performFinish(MediaResourceResult<MediaPoster> result) async {
    _removeFromQueue?.call();
    _removeFromQueue = null;
    _timer?.cancel();
    final listener = _cancellationListener;
    if (listener != null) {
      cancellation?.removeListener(listener);
      _cancellationListener = null;
    }
    if (!_caller.isCompleted) _caller.complete(result);
    if (_started) {
      await _nativeSettled.future;
    } else {
      _settleNative();
    }
    try {
      await store.release(lease);
    } on Object {
      // Cleanup failures cannot escape an already completed caller result.
    } finally {
      reservation.release();
      if (!_finished.isCompleted) _finished.complete();
    }
  }
}

Future<(Uint8List, int, int)?> _sanitizePoster(Uint8List providerBytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  Uint8List? sanitizedBytes;
  var transferred = false;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(providerBytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width > MediaPoster.maximumDimension ||
        descriptor.height > MediaPoster.maximumDimension) {
      return null;
    }
    codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > MediaPoster.maximumBytes) {
      return null;
    }
    final encodedBytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    try {
      sanitizedBytes = _stripPngAncillaryChunks(encodedBytes);
    } finally {
      _clear(encodedBytes);
    }
    if (sanitizedBytes == null) return null;
    transferred = true;
    return (sanitizedBytes, descriptor.width, descriptor.height);
  } on Object {
    return null;
  } finally {
    if (!transferred) _clear(sanitizedBytes);
    _clear(providerBytes);
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Uint8List? _stripPngAncillaryChunks(Uint8List encoded) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (encoded.length < signature.length) return null;
  for (var index = 0; index < signature.length; index += 1) {
    if (encoded[index] != signature[index]) return null;
  }
  final output = BytesBuilder(copy: false)..add(signature);
  var offset = signature.length;
  var sawEnd = false;
  while (offset + 12 <= encoded.length) {
    final length =
        encoded[offset] << 24 |
        encoded[offset + 1] << 16 |
        encoded[offset + 2] << 8 |
        encoded[offset + 3];
    final chunkEnd = offset + 12 + length;
    if (chunkEnd > encoded.length) return null;
    final typeOffset = offset + 4;
    final isCritical = encoded[typeOffset] & 0x20 == 0;
    if (isCritical) output.add(encoded.sublist(offset, chunkEnd));
    final isEnd =
        encoded[typeOffset] == 73 &&
        encoded[typeOffset + 1] == 69 &&
        encoded[typeOffset + 2] == 78 &&
        encoded[typeOffset + 3] == 68;
    offset = chunkEnd;
    if (isEnd) {
      sawEnd = true;
      break;
    }
  }
  if (!sawEnd || offset != encoded.length) return null;
  return output.takeBytes();
}

void _clear(Uint8List? bytes) {
  bytes?.fillRange(0, bytes.length, 0);
}

MediaResourceError<T> _failure<T>(MediaResourceFailureCode code) {
  return MediaResourceError<T>(
    MediaResourceFailure(
      code: code,
      isRecoverable:
          code == MediaResourceFailureCode.cancelled ||
          code == MediaResourceFailureCode.overloaded ||
          code == MediaResourceFailureCode.decodeFailed,
    ),
  );
}
