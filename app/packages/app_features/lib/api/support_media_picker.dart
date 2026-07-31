import 'package:app_media/app_media.dart';

enum SupportMediaSource { camera, gallery }

enum SupportMediaType { image, video }

final class SupportMediaAttachment {
  SupportMediaAttachment({
    required this.resource,
    required String label,
    this.poster,
    this.duration,
  }) : label = label.trim(),
       type = switch (resource.kind) {
         MediaResourceKind.image => SupportMediaType.image,
         MediaResourceKind.video => SupportMediaType.video,
       } {
    if (this.label.isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be empty.');
    }
    if (duration != null && duration! <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive.');
    }
  }

  final OwnedMediaResource resource;
  final SupportMediaType type;
  final String label;
  final MediaPoster? poster;
  final Duration? duration;

  @override
  String toString() =>
      'SupportMediaAttachment(type: ${type.name}, '
      'resource: <redacted>, metadata: <redacted>)';
}

abstract interface class SupportMediaPicker {
  Future<SupportMediaPickResult> pick(SupportMediaSource source);

  Future<void> release(SupportMediaAttachment attachment);

  Future<void> clearDrafts();

  Future<void> dispose();
}

sealed class SupportMediaPickResult {
  const SupportMediaPickResult();
}

final class SupportMediaPickCanceled extends SupportMediaPickResult {
  const SupportMediaPickCanceled();
}

final class SupportMediaPickSuccess extends SupportMediaPickResult {
  const SupportMediaPickSuccess(this.attachment);

  final SupportMediaAttachment attachment;
}

final class SupportMediaPickFailed extends SupportMediaPickResult {
  const SupportMediaPickFailed(this.failure);

  final SupportMediaPickFailure failure;
}

final class SupportMediaPickFailure {
  const SupportMediaPickFailure(this.code);

  final SupportMediaPickFailureCode code;
}

enum SupportMediaPickFailureCode {
  permissionDenied,
  unavailable,
  readFailed,
  tooLarge,
  invalidMedia,
}

final class SupportMediaPickerDisposalException implements Exception {
  const SupportMediaPickerDisposalException();

  @override
  String toString() => 'SupportMediaPickerDisposalException()';
}
