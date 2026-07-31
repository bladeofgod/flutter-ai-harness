import 'package:app_core/app_core.dart';

enum MediaResourceKind { image, video }

enum MediaResourceFailureCode {
  invalidArgument('invalid_argument'),
  unsupportedMedia('unsupported_media'),
  tooLarge('too_large'),
  importFailed('import_failed'),
  missing('missing'),
  invalid('invalid'),
  decodeFailed('decode_failed'),
  playbackFailed('playback_failed'),
  overloaded('overloaded'),
  cancelled('cancelled'),
  storeClosed('store_closed');

  const MediaResourceFailureCode(this.wireValue);

  final String wireValue;
}

final class MediaResourceFailure {
  const MediaResourceFailure({required this.code, required this.isRecoverable});

  final MediaResourceFailureCode code;
  final bool isRecoverable;

  String get message => switch (code) {
    MediaResourceFailureCode.invalidArgument => 'The media input is invalid.',
    MediaResourceFailureCode.unsupportedMedia =>
      'The media format is unsupported.',
    MediaResourceFailureCode.tooLarge => 'The media file is too large.',
    MediaResourceFailureCode.importFailed =>
      'The media resource could not be imported.',
    MediaResourceFailureCode.missing =>
      'The media resource is no longer available.',
    MediaResourceFailureCode.invalid => 'The media resource is invalid.',
    MediaResourceFailureCode.decodeFailed =>
      'The media preview could not be decoded.',
    MediaResourceFailureCode.playbackFailed =>
      'The media resource could not be played.',
    MediaResourceFailureCode.overloaded => 'The media preview service is busy.',
    MediaResourceFailureCode.cancelled => 'The media import was cancelled.',
    MediaResourceFailureCode.storeClosed =>
      'The media resource store is closed.',
  };

  @override
  String toString() {
    return 'MediaResourceFailure(code: ${code.wireValue}, details: <redacted>)';
  }
}

sealed class MediaResourceResult<T> {
  const MediaResourceResult();

  const factory MediaResourceResult.success(T value) = MediaResourceSuccess<T>;

  const factory MediaResourceResult.failure(MediaResourceFailure failure) =
      MediaResourceError<T>;
}

final class MediaResourceSuccess<T> extends MediaResourceResult<T> {
  const MediaResourceSuccess(this.value);

  final T value;

  @override
  String toString() => 'MediaResourceSuccess<$T>(value: <redacted>)';
}

final class MediaResourceError<T> extends MediaResourceResult<T> {
  const MediaResourceError(this.failure);

  final MediaResourceFailure failure;

  @override
  String toString() => 'MediaResourceError<$T>($failure)';
}

typedef MediaImportResult = MediaResourceResult<OwnedMediaResource>;

final class MediaImportCancellation {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  @override
  String toString() => 'MediaImportCancellation(<redacted>)';
}

final class MediaImportRequest {
  const MediaImportRequest({
    required this.sourceUri,
    required this.kind,
    required this.declaredContentType,
    required this.declaredLength,
    this.duration,
    this.cancellation,
  });

  final Uri sourceUri;
  final MediaResourceKind kind;
  final String declaredContentType;
  final int declaredLength;
  final Duration? duration;
  final MediaImportCancellation? cancellation;

  @override
  String toString() {
    return 'MediaImportRequest(kind: ${kind.name}, source: <redacted>, '
        'metadata: <redacted>)';
  }
}

abstract interface class MediaResourceLease {
  MediaResourceId get resourceId;

  bool get isActive;
}

final class OwnedMediaResource {
  const OwnedMediaResource({
    required this.resourceId,
    required this.kind,
    required this.contentType,
    required this.length,
    required this.initialLease,
    this.duration,
  });

  final MediaResourceId resourceId;
  final MediaResourceKind kind;
  final String contentType;
  final int length;
  final Duration? duration;
  final MediaResourceLease initialLease;

  @override
  String toString() {
    return 'OwnedMediaResource(kind: ${kind.name}, resource: <redacted>, '
        'metadata: <redacted>)';
  }
}

final class ResolvedMediaResource {
  const ResolvedMediaResource({
    required this.resourceId,
    required this.kind,
    required this.contentType,
    required this.length,
    required this.fileUri,
    this.duration,
  });

  final MediaResourceId resourceId;
  final MediaResourceKind kind;
  final String contentType;
  final int length;
  final Duration? duration;

  /// Borrowed locator valid only while the resolving lease remains active.
  final Uri fileUri;

  @override
  String toString() {
    return 'ResolvedMediaResource(kind: ${kind.name}, resource: <redacted>, '
        'locator: <redacted>, metadata: <redacted>)';
  }
}
