import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import 'media_resource_file_system.dart';

typedef CacheDirectoryProvider = Future<Directory> Function();
typedef SourceVerificationHook = Future<void> Function();
typedef SourceInspectionHook = Future<void> Function();

final class LocalMediaResourceFileSystem implements MediaResourceFileSystem {
  LocalMediaResourceFileSystem({
    required CacheDirectoryProvider cacheDirectoryProvider,
    SourceVerificationHook? sourceVerificationHook,
    SourceInspectionHook? sourceInspectionHook,
  }) : _cacheDirectoryProvider = cacheDirectoryProvider,
       _sourceVerificationHook = sourceVerificationHook,
       _sourceInspectionHook = sourceInspectionHook;

  static const String _directoryName = 'media_resources_v1';
  static const int _copyChunkSize = 64 * 1024;
  static const int _containerProbeSize = 64 * 1024;
  static final RegExp _storedNamePattern = RegExp(
    r'^mr_[0-9a-f]{32}\.(png|mp4|mov)(\.part)?$',
  );

  final CacheDirectoryProvider _cacheDirectoryProvider;
  final SourceVerificationHook? _sourceVerificationHook;
  final SourceInspectionHook? _sourceInspectionHook;

  @override
  Future<MediaResourceRoot> initializeRoot() async {
    try {
      final cacheDirectory = await _cacheDirectoryProvider();
      final cacheType = await FileSystemEntity.type(
        cacheDirectory.path,
        followLinks: false,
      );
      if (cacheType != FileSystemEntityType.directory) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.operationFailed,
        );
      }
      final canonicalCache = await cacheDirectory.resolveSymbolicLinks();
      final rootPath = path.join(canonicalCache, _directoryName);
      final existingType = await FileSystemEntity.type(
        rootPath,
        followLinks: false,
      );
      if (existingType == FileSystemEntityType.link ||
          (existingType != FileSystemEntityType.notFound &&
              existingType != FileSystemEntityType.directory)) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.operationFailed,
        );
      }
      final rootDirectory = await Directory(rootPath).create();
      final canonicalRoot = await rootDirectory.resolveSymbolicLinks();
      if (!_isWithin(canonicalCache, canonicalRoot)) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.operationFailed,
        );
      }
      return MediaResourceRoot(canonicalRoot);
    } on MediaFileSystemException {
      rethrow;
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  @override
  Future<void> cleanRoot(MediaResourceRoot root) async {
    try {
      await for (final entity in Directory(
        root.path,
      ).list(followLinks: false)) {
        final directParent = path.equals(path.dirname(entity.path), root.path);
        if (!directParent) {
          throw const MediaFileSystemException(
            MediaFileSystemFailureReason.operationFailed,
          );
        }
        await entity.delete(recursive: true);
      }
    } on MediaFileSystemException {
      rethrow;
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  @override
  Future<StableMediaSource> readStableSource(
    Uri sourceUri, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  }) async {
    final before = await _inspectSource(
      sourceUri,
      expectedLength: expectedLength,
      maximumLength: maximumLength,
    );
    final bytes = BytesBuilder(copy: false);
    final digestOutput = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    try {
      await for (final chunk in File(before.canonicalPath).openRead()) {
        _throwIfCancelled(isCancelled);
        bytes.add(chunk);
        digestInput.add(chunk);
        if (bytes.length > maximumLength || bytes.length > expectedLength) {
          throw const MediaFileSystemException(
            MediaFileSystemFailureReason.sourceChanged,
          );
        }
      }
      digestInput.close();
      _throwIfCancelled(isCancelled);
      if (bytes.length != expectedLength) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.sourceChanged,
        );
      }
      await _sourceVerificationHook?.call();
      await _verifySourceUnchanged(
        sourceUri,
        before,
        digestOutput.value,
        maximumLength,
      );
      return StableMediaSource(bytes: bytes.takeBytes());
    } on MediaFileSystemException {
      rethrow;
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  @override
  Future<StagedMediaFile> stageStableVideo(
    MediaResourceRoot root,
    Uri sourceUri,
    String stagingName, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  }) async {
    _validateStoredName(stagingName, staging: true);
    final before = await _inspectSource(
      sourceUri,
      expectedLength: expectedLength,
      maximumLength: maximumLength,
    );
    final stagingPath = _controlledPath(root, stagingName);
    await _requireAbsent(stagingPath);
    RandomAccessFile? source;
    RandomAccessFile? destination;
    final digestOutput = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    final prefix = BytesBuilder(copy: false);
    var written = 0;
    try {
      source = await File(before.canonicalPath).open(mode: FileMode.read);
      destination = await File(stagingPath).open(mode: FileMode.writeOnly);
      while (true) {
        _throwIfCancelled(isCancelled);
        final chunk = await source.read(_copyChunkSize);
        if (chunk.isEmpty) {
          break;
        }
        written += chunk.length;
        if (written > maximumLength || written > expectedLength) {
          throw const MediaFileSystemException(
            MediaFileSystemFailureReason.sourceChanged,
          );
        }
        if (prefix.length < _containerProbeSize) {
          final remaining = _containerProbeSize - prefix.length;
          prefix.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
        }
        digestInput.add(chunk);
        await destination.writeFrom(chunk);
      }
      digestInput.close();
      if (written != expectedLength) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.sourceChanged,
        );
      }
      await destination.flush();
      await destination.close();
      destination = null;
      await source.close();
      source = null;
      _throwIfCancelled(isCancelled);
      await _sourceVerificationHook?.call();
      await _verifySourceUnchanged(
        sourceUri,
        before,
        digestOutput.value,
        maximumLength,
      );
      return StagedMediaFile(length: written, prefix: prefix.takeBytes());
    } on MediaFileSystemException {
      await _deletePath(stagingPath);
      rethrow;
    } on Object {
      await _deletePath(stagingPath);
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    } finally {
      await destination?.close();
      await source?.close();
    }
  }

  @override
  Future<void> writeStaging(
    MediaResourceRoot root,
    String stagingName,
    Uint8List bytes, {
    required bool Function() isCancelled,
  }) async {
    _validateStoredName(stagingName, staging: true);
    final stagingPath = _controlledPath(root, stagingName);
    await _requireAbsent(stagingPath);
    RandomAccessFile? destination;
    try {
      _throwIfCancelled(isCancelled);
      destination = await File(stagingPath).open(mode: FileMode.writeOnly);
      await destination.writeFrom(bytes);
      _throwIfCancelled(isCancelled);
      await destination.flush();
      await destination.close();
      destination = null;
    } on MediaFileSystemException {
      await _deletePath(stagingPath);
      rethrow;
    } on Object {
      await _deletePath(stagingPath);
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    } finally {
      await destination?.close();
    }
  }

  @override
  Future<void> commit(
    MediaResourceRoot root,
    String stagingName,
    String finalName,
  ) async {
    _validateStoredName(stagingName, staging: true);
    _validateStoredName(finalName, staging: false);
    final stagingPath = _controlledPath(root, stagingName);
    final finalPath = _controlledPath(root, finalName);
    try {
      await _requireAbsent(finalPath);
      final stagingType = await FileSystemEntity.type(
        stagingPath,
        followLinks: false,
      );
      if (stagingType != FileSystemEntityType.file) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.operationFailed,
        );
      }
      await File(stagingPath).rename(finalPath);
    } on MediaFileSystemException {
      rethrow;
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  @override
  Future<StoredMediaFile> inspectStored(
    MediaResourceRoot root,
    String finalName,
  ) async {
    _validateStoredName(finalName, staging: false);
    final storedPath = _controlledPath(root, finalName);
    try {
      final type = await FileSystemEntity.type(storedPath, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.invalidStoredFile,
        );
      }
      final canonical = await File(storedPath).resolveSymbolicLinks();
      if (!_isWithin(root.path, canonical)) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.invalidStoredFile,
        );
      }
      final stat = await File(canonical).stat();
      final prefixBuilder = BytesBuilder(copy: false);
      await for (final chunk in File(
        canonical,
      ).openRead(0, _containerProbeSize)) {
        prefixBuilder.add(chunk);
      }
      return StoredMediaFile(
        fileUri: Uri.file(canonical),
        length: stat.size,
        prefix: prefixBuilder.takeBytes(),
      );
    } on MediaFileSystemException {
      rethrow;
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.invalidStoredFile,
      );
    }
  }

  @override
  Future<void> delete(MediaResourceRoot root, String name) async {
    _validateStoredName(name, staging: name.endsWith('.part'));
    await _deletePath(_controlledPath(root, name));
  }

  Future<_SourceSnapshot> _inspectSource(
    Uri sourceUri, {
    required int expectedLength,
    required int maximumLength,
  }) async {
    try {
      final sourcePath = path.normalize(path.absolute(sourceUri.toFilePath()));
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.invalidSource,
        );
      }
      await _sourceInspectionHook?.call();
      final canonicalParent = await Directory(
        path.dirname(sourcePath),
      ).resolveSymbolicLinks();
      final canonicalPath = path.join(
        canonicalParent,
        path.basename(sourcePath),
      );
      final originalType = await FileSystemEntity.type(
        sourcePath,
        followLinks: false,
      );
      final canonicalType = await FileSystemEntity.type(
        canonicalPath,
        followLinks: false,
      );
      if (originalType != FileSystemEntityType.file ||
          canonicalType != FileSystemEntityType.file) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.invalidSource,
        );
      }
      final resolvedOriginal = await File(sourcePath).resolveSymbolicLinks();
      final resolvedCanonical = await File(
        canonicalPath,
      ).resolveSymbolicLinks();
      if (!path.equals(resolvedOriginal, canonicalPath) ||
          !path.equals(resolvedCanonical, canonicalPath)) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.invalidSource,
        );
      }
      final stat = await File(canonicalPath).stat();
      if (stat.type != FileSystemEntityType.file) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.invalidSource,
        );
      }
      if (stat.size > maximumLength) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.tooLarge,
        );
      }
      if (stat.size != expectedLength) {
        throw const MediaFileSystemException(
          MediaFileSystemFailureReason.sourceChanged,
        );
      }
      return _SourceSnapshot(
        canonicalPath: canonicalPath,
        canonicalParent: canonicalParent,
        size: stat.size,
        modifiedMicros: stat.modified.microsecondsSinceEpoch,
      );
    } on MediaFileSystemException {
      rethrow;
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.invalidSource,
      );
    }
  }

  Future<void> _verifySourceUnchanged(
    Uri sourceUri,
    _SourceSnapshot before,
    Digest expectedDigest,
    int maximumLength,
  ) async {
    final after = await _inspectSource(
      sourceUri,
      expectedLength: before.size,
      maximumLength: maximumLength,
    );
    if (after.canonicalPath != before.canonicalPath ||
        after.canonicalParent != before.canonicalParent ||
        after.modifiedMicros != before.modifiedMicros) {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.sourceChanged,
      );
    }
    final currentDigest = await sha256
        .bind(File(after.canonicalPath).openRead())
        .first;
    if (currentDigest != expectedDigest) {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.sourceChanged,
      );
    }
  }

  String _controlledPath(MediaResourceRoot root, String name) {
    final candidate = path.join(root.path, name);
    if (!_isWithin(root.path, candidate) || path.basename(candidate) != name) {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
    return candidate;
  }

  void _validateStoredName(String name, {required bool staging}) {
    if (!_storedNamePattern.hasMatch(name) ||
        staging != name.endsWith('.part')) {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  Future<void> _requireAbsent(String targetPath) async {
    if (await FileSystemEntity.type(targetPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  Future<void> _deletePath(String targetPath) async {
    try {
      final type = await FileSystemEntity.type(targetPath, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        if (type == FileSystemEntityType.directory) {
          await Directory(targetPath).delete(recursive: true);
        } else {
          await File(targetPath).delete();
        }
      }
    } on Object {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
  }

  bool _isWithin(String root, String candidate) {
    return path.equals(root, candidate) || path.isWithin(root, candidate);
  }

  void _throwIfCancelled(bool Function() isCancelled) {
    if (isCancelled()) {
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.cancelled,
      );
    }
  }
}

final class _SourceSnapshot {
  const _SourceSnapshot({
    required this.canonicalPath,
    required this.canonicalParent,
    required this.size,
    required this.modifiedMicros,
  });

  final String canonicalPath;
  final String canonicalParent;
  final int size;
  final int modifiedMicros;
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final value = _value;
    if (value == null) {
      throw StateError('Digest is not complete');
    }
    return value;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}
