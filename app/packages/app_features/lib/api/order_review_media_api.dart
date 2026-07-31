import 'dart:typed_data';

const int orderReviewMediaMaxThumbnailBytes = 524288;

enum OrderReviewMediaType { photo, video }

enum OrderReviewMediaFailureCode {
  permissionDenied,
  unavailable,
  interrupted,
  thumbnailUnavailable,
  releaseFailed,
}

final class OrderReviewMediaFailure {
  const OrderReviewMediaFailure({
    required this.code,
    required this.recoverable,
  });

  final OrderReviewMediaFailureCode code;
  final bool recoverable;
}

final class OrderReviewMediaAttachment {
  OrderReviewMediaAttachment({
    required this.type,
    required Uint8List thumbnailBytes,
    required this.thumbnailPixelWidth,
    required this.thumbnailPixelHeight,
    required this.duration,
  }) : _thumbnailBytes = Uint8List.fromList(thumbnailBytes) {
    if (_thumbnailBytes.isEmpty ||
        _thumbnailBytes.length > orderReviewMediaMaxThumbnailBytes) {
      throw RangeError.range(
        _thumbnailBytes.length,
        1,
        orderReviewMediaMaxThumbnailBytes,
        'thumbnailBytes.length',
      );
    }
    if (thumbnailPixelWidth <= 0 || thumbnailPixelHeight <= 0) {
      throw ArgumentError('Thumbnail dimensions must be positive.');
    }
    if (type == OrderReviewMediaType.photo && duration != null) {
      throw ArgumentError('Photo attachments cannot have a duration.');
    }
    if (type == OrderReviewMediaType.video &&
        (duration == null || duration! <= Duration.zero)) {
      throw ArgumentError('Video attachments require a positive duration.');
    }
  }

  final OrderReviewMediaType type;
  final Uint8List _thumbnailBytes;
  final int thumbnailPixelWidth;
  final int thumbnailPixelHeight;
  final Duration? duration;

  Uint8List get thumbnailBytes => Uint8List.fromList(_thumbnailBytes);
}

sealed class OrderReviewMediaCaptureOutcome {
  const OrderReviewMediaCaptureOutcome();
}

final class OrderReviewMediaConfirmed extends OrderReviewMediaCaptureOutcome {
  const OrderReviewMediaConfirmed(this.attachment);

  final OrderReviewMediaAttachment attachment;
}

final class OrderReviewMediaCancelled extends OrderReviewMediaCaptureOutcome {
  const OrderReviewMediaCancelled();
}

final class OrderReviewMediaCaptureFailure
    extends OrderReviewMediaCaptureOutcome {
  const OrderReviewMediaCaptureFailure(this.failure);

  final OrderReviewMediaFailure failure;
}

sealed class OrderReviewMediaReleaseOutcome {
  const OrderReviewMediaReleaseOutcome();
}

final class OrderReviewMediaReleased extends OrderReviewMediaReleaseOutcome {
  const OrderReviewMediaReleased();
}

final class OrderReviewMediaReleaseFailure
    extends OrderReviewMediaReleaseOutcome {
  const OrderReviewMediaReleaseFailure(this.failure);

  final OrderReviewMediaFailure failure;
}

final class OrderReviewMediaDisposalException implements Exception {
  const OrderReviewMediaDisposalException();

  @override
  String toString() => 'OrderReviewMediaDisposalException(<redacted>)';
}

abstract interface class OrderReviewMediaApi {
  Future<OrderReviewMediaCaptureOutcome> capture();

  Future<OrderReviewMediaReleaseOutcome> release(
    OrderReviewMediaAttachment attachment,
  );

  /// Drops all business attachment references immediately, then performs
  /// bounded cleanup of their native leases.
  Future<void> clearDrafts();

  Future<void> dispose();
}
