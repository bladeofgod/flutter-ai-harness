import 'dart:typed_data';

abstract interface class MediaResourceFileSystem {
  Future<MediaResourceRoot> initializeRoot();

  Future<void> cleanRoot(MediaResourceRoot root);

  Future<StableMediaSource> readStableSource(
    Uri sourceUri, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  });

  Future<StagedMediaFile> stageStableVideo(
    MediaResourceRoot root,
    Uri sourceUri,
    String stagingName, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  });

  Future<void> writeStaging(
    MediaResourceRoot root,
    String stagingName,
    Uint8List bytes, {
    required bool Function() isCancelled,
  });

  Future<void> commit(
    MediaResourceRoot root,
    String stagingName,
    String finalName,
  );

  Future<StoredMediaFile> inspectStored(
    MediaResourceRoot root,
    String finalName,
  );

  Future<void> delete(MediaResourceRoot root, String name);
}

final class MediaResourceRoot {
  const MediaResourceRoot(this.path);

  final String path;

  @override
  String toString() => 'MediaResourceRoot(<redacted>)';
}

final class StableMediaSource {
  const StableMediaSource({required this.bytes});

  final Uint8List bytes;

  @override
  String toString() => 'StableMediaSource(bytes: <redacted>)';
}

final class StagedMediaFile {
  const StagedMediaFile({required this.length, required this.prefix});

  final int length;
  final Uint8List prefix;

  @override
  String toString() => 'StagedMediaFile(metadata: <redacted>)';
}

final class StoredMediaFile {
  const StoredMediaFile({
    required this.fileUri,
    required this.length,
    required this.prefix,
  });

  final Uri fileUri;
  final int length;
  final Uint8List prefix;

  @override
  String toString() => 'StoredMediaFile(locator: <redacted>)';
}

enum MediaFileSystemFailureReason {
  invalidSource,
  tooLarge,
  sourceChanged,
  cancelled,
  invalidStoredFile,
  operationFailed,
}

final class MediaFileSystemException implements Exception {
  const MediaFileSystemException(this.reason);

  final MediaFileSystemFailureReason reason;

  @override
  String toString() {
    return 'MediaFileSystemException(reason: ${reason.name}, '
        'details: <redacted>)';
  }
}
