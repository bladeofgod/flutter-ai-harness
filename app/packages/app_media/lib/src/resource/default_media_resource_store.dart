import 'dart:async';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';

import 'media_resource_file_system.dart';
import 'media_resource_models.dart';
import 'media_resource_store.dart';
import 'media_resource_support.dart';

final class DefaultMediaResourceStore implements MediaResourceStore {
  DefaultMediaResourceStore._({
    required MediaResourceFileSystem fileSystem,
    required MediaResourceRoot root,
    required MediaImageCanonicalizer imageCanonicalizer,
    required MediaResourceRandom random,
    required MediaResourceClock clock,
  }) : _fileSystem = fileSystem,
       _root = root,
       _imageCanonicalizer = imageCanonicalizer,
       _random = random,
       _clock = clock;

  static const int maximumImageBytes = 20 * 1024 * 1024;
  static const int maximumVideoBytes = 50 * 1024 * 1024;
  static const int _maximumSourceNameLength = 255;
  static const int _maximumIdAttempts = 16;
  static const int _maximumTombstones = 256;
  static const Duration _tombstoneLifetime = Duration(minutes: 5);
  static const Set<String> _imageContentTypes = <String>{
    'image/jpeg',
    'image/png',
  };
  static const Set<String> _videoContentTypes = <String>{
    'video/mp4',
    'video/quicktime',
  };
  static const Set<String> _isoBmffBrands = <String>{
    '3gp4',
    '3gp5',
    'M4V ',
    'avc1',
    'dash',
    'iso2',
    'iso3',
    'iso4',
    'iso5',
    'iso6',
    'isom',
    'mp41',
    'mp42',
    'qt  ',
  };

  final MediaResourceFileSystem _fileSystem;
  final MediaResourceRoot _root;
  final MediaImageCanonicalizer _imageCanonicalizer;
  final MediaResourceRandom _random;
  final MediaResourceClock _clock;
  final Object _storeToken = Object();
  final Map<MediaResourceId, _ResourceRecord> _records = {};
  final Map<MediaResourceId, _Tombstone> _tombstones = {};
  final Map<MediaResourceId, Set<String>> _pendingDeletions = {};
  final Set<MediaResourceId> _issuedIds = {};

  Future<void> _tail = Future<void>.value();
  Future<void>? _disposeFuture;
  bool _closing = false;
  bool _disposed = false;

  static Future<DefaultMediaResourceStore> create({
    required MediaResourceFileSystem fileSystem,
    required MediaImageCanonicalizer imageCanonicalizer,
    required MediaResourceRandom random,
    required MediaResourceClock clock,
  }) async {
    try {
      final root = await fileSystem.initializeRoot();
      await fileSystem.cleanRoot(root);
      return DefaultMediaResourceStore._(
        fileSystem: fileSystem,
        root: root,
        imageCanonicalizer: imageCanonicalizer,
        random: random,
        clock: clock,
      );
    } on Object {
      throw StateError('Media resource store initialization failed');
    }
  }

  @override
  Future<MediaImportResult> importFile(MediaImportRequest request) {
    if (_closing) {
      return Future<MediaImportResult>.value(
        _failure(MediaResourceFailureCode.storeClosed),
      );
    }
    return _enqueue(() => _importFile(request));
  }

  Future<MediaImportResult> _importFile(MediaImportRequest request) async {
    if (_closing) {
      return _failure(MediaResourceFailureCode.storeClosed);
    }
    final validationFailure = _validateRequest(request);
    if (validationFailure != null) {
      return validationFailure;
    }
    if (_isImportCancelled(request)) {
      return _failure(MediaResourceFailureCode.cancelled);
    }

    final resourceId = _createResourceId();
    if (resourceId == null) {
      return _failure(MediaResourceFailureCode.importFailed);
    }
    final extension = switch (request.kind) {
      MediaResourceKind.image => 'png',
      MediaResourceKind.video =>
        request.declaredContentType == 'video/quicktime' ? 'mov' : 'mp4',
    };
    final finalName = '${resourceId.value}.$extension';
    final stagingName = '$finalName.part';
    var stagingCreated = false;
    var committed = false;

    try {
      late final int canonicalLength;
      late final String canonicalContentType;
      if (request.kind == MediaResourceKind.image) {
        final source = await _fileSystem.readStableSource(
          request.sourceUri,
          expectedLength: request.declaredLength,
          maximumLength: maximumImageBytes,
          isCancelled: () => _isImportCancelled(request),
        );
        final actualType = _imageContentType(source.bytes);
        if (actualType == null || actualType != request.declaredContentType) {
          return _failure(MediaResourceFailureCode.unsupportedMedia);
        }
        final canonical = await _imageCanonicalizer.canonicalize(source.bytes);
        if (canonical.contentType != 'image/png' &&
            canonical.contentType != 'image/jpeg') {
          return _failure(MediaResourceFailureCode.unsupportedMedia);
        }
        if (canonical.bytes.length > maximumImageBytes) {
          return _failure(MediaResourceFailureCode.tooLarge);
        }
        if (_isImportCancelled(request)) {
          return _failure(MediaResourceFailureCode.cancelled);
        }
        await _fileSystem.writeStaging(
          _root,
          stagingName,
          canonical.bytes,
          isCancelled: () => _isImportCancelled(request),
        );
        stagingCreated = true;
        canonicalLength = canonical.bytes.length;
        canonicalContentType = canonical.contentType;
      } else {
        stagingCreated = true;
        final staged = await _fileSystem.stageStableVideo(
          _root,
          request.sourceUri,
          stagingName,
          expectedLength: request.declaredLength,
          maximumLength: maximumVideoBytes,
          isCancelled: () => _isImportCancelled(request),
        );
        if (!_isIsoBmff(staged.prefix, staged.length)) {
          return _failure(MediaResourceFailureCode.unsupportedMedia);
        }
        canonicalLength = staged.length;
        canonicalContentType = request.declaredContentType;
      }

      if (_isImportCancelled(request)) {
        return _failure(MediaResourceFailureCode.cancelled);
      }
      await _fileSystem.commit(_root, stagingName, finalName);
      stagingCreated = false;
      committed = true;
      if (_isImportCancelled(request)) {
        return _failure(MediaResourceFailureCode.cancelled);
      }

      final lease = _StoreMediaResourceLease(
        storeToken: _storeToken,
        resourceId: resourceId,
      );
      final record = _ResourceRecord(
        fileName: finalName,
        kind: request.kind,
        contentType: canonicalContentType,
        length: canonicalLength,
        duration: request.duration,
      )..leases.add(lease);
      _records[resourceId] = record;
      committed = false;
      return MediaResourceResult<OwnedMediaResource>.success(
        OwnedMediaResource(
          resourceId: resourceId,
          kind: request.kind,
          contentType: canonicalContentType,
          length: canonicalLength,
          duration: request.duration,
          initialLease: lease,
        ),
      );
    } on UnsupportedMediaException {
      return _failure(MediaResourceFailureCode.unsupportedMedia);
    } on MediaFileSystemException catch (error) {
      return _failure(_mapFileSystemFailure(error.reason));
    } on Object {
      return _failure(MediaResourceFailureCode.importFailed);
    } finally {
      if (stagingCreated) {
        await _deleteOrRetain(resourceId, stagingName);
      }
      if (committed) {
        await _deleteOrRetain(resourceId, finalName);
      }
    }
  }

  @override
  Future<MediaResourceResult<MediaResourceLease>> retain(
    MediaResourceId resourceId,
  ) {
    if (_closing) {
      return Future<MediaResourceResult<MediaResourceLease>>.value(
        _failure(MediaResourceFailureCode.storeClosed),
      );
    }
    return _enqueue(() async {
      if (_closing) {
        return _failure(MediaResourceFailureCode.storeClosed);
      }
      _pruneTombstones();
      final record = _records[resourceId];
      if (record == null) {
        return _failure(_inactiveCode(resourceId));
      }
      final lease = _StoreMediaResourceLease(
        storeToken: _storeToken,
        resourceId: resourceId,
      );
      record.leases.add(lease);
      return MediaResourceResult<MediaResourceLease>.success(lease);
    });
  }

  @override
  Future<MediaResourceResult<ResolvedMediaResource>> resolve(
    MediaResourceId resourceId,
    MediaResourceLease lease,
  ) {
    if (_closing) {
      return Future<MediaResourceResult<ResolvedMediaResource>>.value(
        _failure(MediaResourceFailureCode.storeClosed),
      );
    }
    return _enqueue(() async {
      if (_closing) {
        return _failure(MediaResourceFailureCode.storeClosed);
      }
      _pruneTombstones();
      final record = _records[resourceId];
      if (record == null) {
        return _failure(_inactiveCode(resourceId));
      }
      if (lease is! _StoreMediaResourceLease ||
          lease._storeToken != _storeToken ||
          lease.resourceId != resourceId ||
          !lease.isActive ||
          !record.leases.contains(lease)) {
        return _failure(MediaResourceFailureCode.invalidArgument);
      }
      try {
        final stored = await _fileSystem.inspectStored(_root, record.fileName);
        if (_closing) {
          return _failure(MediaResourceFailureCode.storeClosed);
        }
        if (stored.length != record.length ||
            !_matchesContent(record, stored.prefix, stored.length)) {
          return await _invalidateResource(resourceId, record);
        }
        return MediaResourceResult<ResolvedMediaResource>.success(
          ResolvedMediaResource(
            resourceId: resourceId,
            kind: record.kind,
            contentType: record.contentType,
            length: record.length,
            duration: record.duration,
            fileUri: stored.fileUri,
          ),
        );
      } on Object {
        return _invalidateResource(resourceId, record);
      }
    });
  }

  @override
  Future<MediaResourceResult<void>> release(MediaResourceLease lease) {
    return _enqueue(() async {
      if (lease is! _StoreMediaResourceLease ||
          lease._storeToken != _storeToken) {
        return _failure(MediaResourceFailureCode.invalidArgument);
      }
      if (!lease._releaseOnce()) {
        return await _settlePendingDeletion(lease.resourceId)
            ? const MediaResourceResult<void>.success(null)
            : _failure(MediaResourceFailureCode.importFailed);
      }
      final record = _records[lease.resourceId];
      if (record == null) {
        return const MediaResourceResult<void>.success(null);
      }
      record.leases.remove(lease);
      if (record.leases.isNotEmpty) {
        return const MediaResourceResult<void>.success(null);
      }

      _records.remove(lease.resourceId);
      _addTombstone(lease.resourceId, MediaResourceFailureCode.missing);
      final deleted = await _deleteOrRetain(lease.resourceId, record.fileName);
      if (!deleted) {
        return _failure(MediaResourceFailureCode.importFailed);
      }
      return const MediaResourceResult<void>.success(null);
    });
  }

  @override
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }
    _closing = true;
    final future = _enqueue(() async {
      if (_disposed) {
        return;
      }
      _disposed = true;
      final records = Map<MediaResourceId, _ResourceRecord>.from(_records);
      _records.clear();
      for (final entry in records.entries) {
        for (final lease in entry.value.leases) {
          lease._invalidate();
        }
        _addTombstone(entry.key, MediaResourceFailureCode.storeClosed);
        await _deleteOrRetain(entry.key, entry.value.fileName);
      }
      for (final resourceId in _pendingDeletions.keys.toList()) {
        await _settlePendingDeletion(resourceId);
      }
      try {
        await _fileSystem.cleanRoot(_root);
        _pendingDeletions.clear();
      } on Object {
        // Startup cleanup retries any residue without exposing filesystem data.
      }
    });
    _disposeFuture = future;
    return future;
  }

  MediaResourceError<T> _failure<T>(MediaResourceFailureCode code) {
    return MediaResourceError<T>(
      MediaResourceFailure(
        code: code,
        isRecoverable:
            code == MediaResourceFailureCode.importFailed ||
            code == MediaResourceFailureCode.cancelled,
      ),
    );
  }

  MediaResourceError<OwnedMediaResource>? _validateRequest(
    MediaImportRequest request,
  ) {
    final uri = request.sourceUri;
    if (uri.scheme != 'file' ||
        uri.host.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith('/') ||
        uri.pathSegments.any((segment) => segment == '.' || segment == '..') ||
        uri.pathSegments.isEmpty ||
        uri.pathSegments.last.length > _maximumSourceNameLength ||
        request.declaredLength <= 0 ||
        (request.duration != null && request.duration!.isNegative) ||
        (request.kind == MediaResourceKind.image && request.duration != null)) {
      return _failure(MediaResourceFailureCode.invalidArgument);
    }
    final maximum = request.kind == MediaResourceKind.image
        ? maximumImageBytes
        : maximumVideoBytes;
    if (request.declaredLength > maximum) {
      return _failure(MediaResourceFailureCode.tooLarge);
    }
    final allowedTypes = request.kind == MediaResourceKind.image
        ? _imageContentTypes
        : _videoContentTypes;
    if (!allowedTypes.contains(request.declaredContentType)) {
      return _failure(MediaResourceFailureCode.unsupportedMedia);
    }
    return null;
  }

  MediaResourceId? _createResourceId() {
    for (var attempt = 0; attempt < _maximumIdAttempts; attempt += 1) {
      final bytes = _random.nextBytes(16);
      if (bytes.length != 16) {
        return null;
      }
      final value = StringBuffer('mr_');
      for (final byte in bytes) {
        value.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      final id = MediaResourceId(value.toString());
      if (_issuedIds.add(id)) {
        return id;
      }
    }
    return null;
  }

  bool _isImportCancelled(MediaImportRequest request) {
    return _closing || (request.cancellation?.isCancelled ?? false);
  }

  String? _imageContentType(Uint8List bytes) {
    if (_isPng(bytes)) {
      return 'image/png';
    }
    if (_isJpeg(bytes)) {
      return 'image/jpeg';
    }
    return null;
  }

  bool _matchesContent(_ResourceRecord record, Uint8List prefix, int length) {
    return switch (record.contentType) {
      'image/png' => _isPng(prefix),
      'image/jpeg' => _isJpegHeader(prefix),
      'video/mp4' || 'video/quicktime' => _isIsoBmff(prefix, length),
      _ => false,
    };
  }

  bool _isPng(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    return _startsWith(bytes, signature);
  }

  bool _isJpeg(Uint8List bytes) {
    return _isJpegHeader(bytes) &&
        bytes[bytes.length - 2] == 0xff &&
        bytes[bytes.length - 1] == 0xd9;
  }

  bool _isJpegHeader(Uint8List bytes) {
    return bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8;
  }

  bool _isIsoBmff(Uint8List bytes, int totalLength) {
    if (bytes.length < 16 || totalLength < 24) {
      return false;
    }
    final fileTypeLength = _readUint32(bytes, 0);
    if (fileTypeLength < 16 ||
        fileTypeLength > totalLength ||
        fileTypeLength > bytes.length ||
        _boxType(bytes, 4) != 'ftyp') {
      return false;
    }
    final brands = <String>{_boxType(bytes, 8)};
    for (var offset = 16; offset + 4 <= fileTypeLength; offset += 4) {
      brands.add(_boxType(bytes, offset));
    }
    if (!brands.any(_isoBmffBrands.contains)) {
      return false;
    }

    var offset = fileTypeLength;
    while (offset + 8 <= bytes.length && offset + 8 <= totalLength) {
      var headerLength = 8;
      var boxLength = _readUint32(bytes, offset);
      final type = _boxType(bytes, offset + 4);
      if (boxLength == 1) {
        if (offset + 16 > bytes.length) {
          return false;
        }
        headerLength = 16;
        boxLength = _readUint64(bytes, offset + 8);
      } else if (boxLength == 0) {
        boxLength = totalLength - offset;
      }
      if (boxLength < headerLength || offset + boxLength > totalLength) {
        return false;
      }
      if (type == 'moov' || type == 'mdat') {
        return true;
      }
      if (offset + boxLength > bytes.length) {
        return false;
      }
      offset += boxLength;
    }
    return false;
  }

  int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  int _readUint64(Uint8List bytes, int offset) {
    return (_readUint32(bytes, offset) << 32) | _readUint32(bytes, offset + 4);
  }

  String _boxType(Uint8List bytes, int offset) {
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }

  bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) {
      return false;
    }
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) {
        return false;
      }
    }
    return true;
  }

  MediaResourceFailureCode _mapFileSystemFailure(
    MediaFileSystemFailureReason reason,
  ) {
    return switch (reason) {
      MediaFileSystemFailureReason.invalidSource =>
        MediaResourceFailureCode.invalidArgument,
      MediaFileSystemFailureReason.tooLarge =>
        MediaResourceFailureCode.tooLarge,
      MediaFileSystemFailureReason.sourceChanged =>
        MediaResourceFailureCode.invalid,
      MediaFileSystemFailureReason.cancelled =>
        MediaResourceFailureCode.cancelled,
      MediaFileSystemFailureReason.invalidStoredFile =>
        MediaResourceFailureCode.invalid,
      MediaFileSystemFailureReason.operationFailed =>
        MediaResourceFailureCode.importFailed,
    };
  }

  Future<MediaResourceError<ResolvedMediaResource>> _invalidateResource(
    MediaResourceId resourceId,
    _ResourceRecord record,
  ) async {
    if (_records[resourceId] == record) {
      _records.remove(resourceId);
      for (final lease in record.leases) {
        lease._invalidate();
      }
      _addTombstone(resourceId, MediaResourceFailureCode.invalid);
      await _deleteOrRetain(resourceId, record.fileName);
    }
    return _failure(MediaResourceFailureCode.invalid);
  }

  MediaResourceFailureCode _inactiveCode(MediaResourceId resourceId) {
    return _tombstones[resourceId]?.failureCode ??
        MediaResourceFailureCode.missing;
  }

  void _addTombstone(
    MediaResourceId resourceId,
    MediaResourceFailureCode failureCode,
  ) {
    _tombstones[resourceId] = _Tombstone(
      createdAt: _clock.now(),
      failureCode: failureCode,
    );
    _pruneTombstones();
  }

  void _pruneTombstones() {
    final cutoff = _clock.now().subtract(_tombstoneLifetime);
    _tombstones.removeWhere((_, tombstone) {
      return tombstone.createdAt.isBefore(cutoff);
    });
    while (_tombstones.length > _maximumTombstones) {
      _tombstones.remove(_tombstones.keys.first);
    }
  }

  Future<bool> _deleteWithRetry(String fileName) async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        await _fileSystem.delete(_root, fileName);
        return true;
      } on Object {
        // The entry is already inactive; retries only converge physical cleanup.
      }
    }
    return false;
  }

  Future<bool> _deleteOrRetain(
    MediaResourceId resourceId,
    String fileName,
  ) async {
    final deleted = await _deleteWithRetry(fileName);
    if (!deleted) {
      _pendingDeletions.putIfAbsent(resourceId, () => <String>{}).add(fileName);
      return false;
    }
    final names = _pendingDeletions[resourceId];
    names?.remove(fileName);
    if (names?.isEmpty ?? false) {
      _pendingDeletions.remove(resourceId);
    }
    return true;
  }

  Future<bool> _settlePendingDeletion(MediaResourceId resourceId) async {
    final names = _pendingDeletions[resourceId];
    if (names == null) {
      return true;
    }
    var settled = true;
    for (final fileName in names.toList()) {
      if (!await _deleteOrRetain(resourceId, fileName)) {
        settled = false;
      }
    }
    return settled;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        for (final resourceId in _pendingDeletions.keys.toList()) {
          await _settlePendingDeletion(resourceId);
        }
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _StoreMediaResourceLease implements MediaResourceLease {
  _StoreMediaResourceLease({
    required Object storeToken,
    required this.resourceId,
  }) : _storeToken = storeToken;

  final Object _storeToken;

  @override
  final MediaResourceId resourceId;

  bool _active = true;

  @override
  bool get isActive => _active;

  bool _releaseOnce() {
    if (!_active) {
      return false;
    }
    _active = false;
    return true;
  }

  void _invalidate() {
    _active = false;
  }

  @override
  String toString() => 'MediaResourceLease(<redacted>)';
}

final class _ResourceRecord {
  _ResourceRecord({
    required this.fileName,
    required this.kind,
    required this.contentType,
    required this.length,
    required this.duration,
  });

  final String fileName;
  final MediaResourceKind kind;
  final String contentType;
  final int length;
  final Duration? duration;
  final Set<_StoreMediaResourceLease> leases = {};
}

final class _Tombstone {
  const _Tombstone({required this.createdAt, required this.failureCode});

  final DateTime createdAt;
  final MediaResourceFailureCode failureCode;
}
