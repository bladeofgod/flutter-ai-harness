import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart'
    as video_thumbnail;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'media_poster_generator.dart';
import 'media_preview_models.dart';

abstract interface class VideoThumbnailPosterWriter {
  Future<bool> write({
    required String sourcePath,
    required String destinationPath,
    required int width,
    required int height,
    required int quality,
  });
}

typedef MediaPosterTemporaryRootProvider = Future<Directory> Function();
typedef MediaPosterJobRootCreate = Future<Directory> Function(Directory root);
typedef MediaPosterTokenProvider = String Function();
typedef MediaPosterFileDelete = Future<void> Function(File file);
typedef MediaPosterFileRead =
    Stream<List<int>> Function(File file, int maximumBytes);

final class VideoThumbnailPosterGenerator implements MediaPosterGenerator {
  VideoThumbnailPosterGenerator({
    VideoThumbnailPosterWriter? writer,
    MediaPosterTemporaryRootProvider? temporaryRootProvider,
    MediaPosterJobRootCreate? createJobRoot,
    MediaPosterTokenProvider? tokenProvider,
    MediaPosterFileDelete? deleteFile,
    MediaPosterFileRead? readFile,
  }) : _writer = writer ?? const _FlutterVideoThumbnailPlusPosterWriter(),
       _temporaryRootProvider = temporaryRootProvider ?? _defaultTemporaryRoot,
       _createJobRoot = createJobRoot ?? _defaultCreateJobRoot,
       _tokenProvider = tokenProvider ?? _randomToken,
       _deleteFile = deleteFile ?? _defaultDelete,
       _readFile = readFile ?? _defaultRead;

  static final Random _random = Random.secure();
  static final Set<String> _liveJobRoots = <String>{};
  static final Map<String, _AsyncLock> _rootPreparationLocks =
      <String, _AsyncLock>{};
  static final RegExp _legacyPosterName = RegExp(r'^[0-9a-f]{32}\.jpg$');

  final VideoThumbnailPosterWriter _writer;
  final MediaPosterTemporaryRootProvider _temporaryRootProvider;
  final MediaPosterJobRootCreate _createJobRoot;
  final MediaPosterTokenProvider _tokenProvider;
  final MediaPosterFileDelete _deleteFile;
  final MediaPosterFileRead _readFile;

  @override
  Future<Uint8List?> generateJpeg(
    Uri fileUri, {
    required int maximumDimension,
    required int quality,
  }) async {
    final temporaryRoot = await _temporaryRootProvider();
    final preparedRoot = await _preparePosterRoot(temporaryRoot);
    final posterRoot = preparedRoot.$1;
    final posterRootCanonical = preparedRoot.$2;
    final preparedJob = await _prepareJobRoot(posterRoot, posterRootCanonical);
    final jobRoot = preparedJob.$1;
    final jobRootCanonical = preparedJob.$2;
    final token = _tokenProvider();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      try {
        await _deleteTree(jobRoot);
      } finally {
        _liveJobRoots.remove(jobRootCanonical);
      }
      throw const FileSystemException('Invalid generated poster token');
    }
    final output = File(path.join(jobRoot.path, '$token.jpg'));
    try {
      final generated = await _writer.write(
        sourcePath: fileUri.toFilePath(),
        destinationPath: output.path,
        width: maximumDimension,
        height: maximumDimension,
        quality: quality,
      );
      if (!generated || !await _isSafeOutput(output, jobRootCanonical)) {
        return null;
      }
      final stat = await output.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          stat.size > MediaPoster.maximumBytes) {
        return null;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in _readFile(output, MediaPoster.maximumBytes)) {
        builder.add(chunk);
        if (builder.length > MediaPoster.maximumBytes) return null;
      }
      final bytes = builder.takeBytes();
      if (!await _isSafeOutput(output, jobRootCanonical)) {
        bytes.fillRange(0, bytes.length, 0);
        return null;
      }
      final finalStat = await output.stat();
      if (finalStat.type != FileSystemEntityType.file ||
          finalStat.size != stat.size ||
          finalStat.modified != stat.modified) {
        bytes.fillRange(0, bytes.length, 0);
        return null;
      }
      return bytes.isEmpty ? null : bytes;
    } finally {
      try {
        await _deleteGeneratedPoster(output);
      } finally {
        try {
          await _deleteTree(jobRoot);
        } finally {
          _liveJobRoots.remove(jobRootCanonical);
        }
      }
    }
  }

  Future<(Directory, String)> _preparePosterRoot(
    Directory temporaryRoot,
  ) async {
    if (await FileSystemEntity.type(temporaryRoot.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Invalid temporary poster root');
    }
    final temporaryCanonical = await temporaryRoot.resolveSymbolicLinks();
    final posterRoot = Directory(
      path.join(temporaryRoot.path, 'app-media-posters'),
    );
    final initialType = await FileSystemEntity.type(
      posterRoot.path,
      followLinks: false,
    );
    if (initialType == FileSystemEntityType.notFound) {
      await posterRoot.create();
    } else if (initialType != FileSystemEntityType.directory) {
      throw const FileSystemException('Invalid generated poster root');
    }
    final canonical = await _validatedDirectoryWithin(
      posterRoot,
      temporaryCanonical,
    );
    return (posterRoot, canonical);
  }

  Future<(Directory, String)> _prepareJobRoot(
    Directory posterRoot,
    String posterRootCanonical,
  ) {
    return _withRootPreparationLock(posterRootCanonical, () async {
      await _sweepOrphanedPosters(posterRoot, posterRootCanonical);
      if (await posterRoot.resolveSymbolicLinks() != posterRootCanonical) {
        throw const FileSystemException('Generated poster root changed');
      }
      final jobRoot = await _createJobRoot(posterRoot);
      try {
        final canonical = await _validatedDirectoryWithin(
          jobRoot,
          posterRootCanonical,
        );
        _liveJobRoots.add(canonical);
        return (jobRoot, canonical);
      } on Object {
        await _deleteTree(jobRoot);
        rethrow;
      }
    });
  }

  Future<T> _withRootPreparationLock<T>(
    String canonicalRoot,
    Future<T> Function() action,
  ) {
    final lock = _rootPreparationLocks.putIfAbsent(
      canonicalRoot,
      _AsyncLock.new,
    );
    return lock.run(action).whenComplete(() {
      if (lock.isIdle &&
          identical(_rootPreparationLocks[canonicalRoot], lock)) {
        _rootPreparationLocks.remove(canonicalRoot);
      }
    });
  }

  Future<String> _validatedDirectoryWithin(
    Directory directory,
    String canonicalParent,
  ) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Invalid generated poster directory');
    }
    final canonical = await directory.resolveSymbolicLinks();
    if (!path.isWithin(canonicalParent, canonical)) {
      throw const FileSystemException('Invalid generated poster directory');
    }
    return canonical;
  }

  Future<bool> _isSafeOutput(File output, String canonicalJobRoot) async {
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return false;
    }
    try {
      final canonical = await output.resolveSymbolicLinks();
      return path.isWithin(canonicalJobRoot, canonical) &&
          path.basename(canonical) == path.basename(output.path);
    } on Object {
      return false;
    }
  }

  static Future<Directory> _defaultTemporaryRoot() => getTemporaryDirectory();

  static Future<Directory> _defaultCreateJobRoot(Directory root) {
    return root.createTemp('job-');
  }

  static Future<void> _defaultDelete(File output) => output.delete();

  static Stream<List<int>> _defaultRead(File output, int maximumBytes) {
    return output.openRead(0, maximumBytes + 1);
  }

  static String _randomToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _deleteGeneratedPoster(File output) async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        final type = await FileSystemEntity.type(
          output.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) return;
        if (type == FileSystemEntityType.link) {
          await Link(output.path).delete();
        } else if (type == FileSystemEntityType.directory) {
          await _deleteTree(Directory(output.path));
        } else {
          await _deleteFile(output);
        }
        return;
      } on Object {
        // The bounded retries keep temporary poster cleanup locally owned.
      }
    }
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const FileSystemException('Unable to delete generated poster');
    }
  }

  Future<void> _sweepOrphanedPosters(
    Directory root,
    String expectedCanonical,
  ) async {
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != expectedCanonical) {
      throw const FileSystemException('Generated poster root changed');
    }
    await for (final entity in root.list(followLinks: false)) {
      final name = path.basename(entity.path);
      final isOwnedJob = entity is Directory && name.startsWith('job-');
      if (isOwnedJob) {
        try {
          final canonical = await entity.resolveSymbolicLinks();
          if (path.isWithin(expectedCanonical, canonical) &&
              _liveJobRoots.contains(canonical)) {
            continue;
          }
        } on Object {
          // Invalid owned entries are handled by the no-follow cleanup below.
        }
      }
      final isLegacyPoster =
          (entity is File || entity is Link) &&
          _legacyPosterName.hasMatch(name);
      if (!isOwnedJob && !isLegacyPoster) continue;
      try {
        await _deleteTree(entity);
      } on Object {
        // A later job retries cleanup without touching unrelated entries.
      }
    }
  }

  Future<void> _deleteTree(FileSystemEntity entity) async {
    final type = await FileSystemEntity.type(entity.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.link) {
      await Link(entity.path).delete();
      return;
    }
    if (type == FileSystemEntityType.file) {
      await _deleteFile(File(entity.path));
      return;
    }
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('Invalid generated poster entry');
    }
    final directory = Directory(entity.path);
    await for (final child in directory.list(followLinks: false)) {
      await _deleteTree(child);
    }
    await directory.delete();
  }
}

final class _AsyncLock {
  Future<void> _tail = Future<void>.value();
  int _users = 0;

  bool get isIdle => _users == 0;

  Future<T> run<T>(Future<T> Function() action) {
    _users += 1;
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        _users -= 1;
        release.complete();
      }
    }();
  }
}

final class _FlutterVideoThumbnailPlusPosterWriter
    implements VideoThumbnailPosterWriter {
  const _FlutterVideoThumbnailPlusPosterWriter();

  @override
  Future<bool> write({
    required String sourcePath,
    required String destinationPath,
    required int width,
    required int height,
    required int quality,
  }) async {
    final generatedPath =
        await video_thumbnail.FlutterVideoThumbnailPlus.thumbnailFile(
          video: sourcePath,
          thumbnailPath: destinationPath,
          imageFormat: video_thumbnail.ImageFormat.jpeg,
          maxWidth: width,
          maxHeight: height,
          quality: quality,
        );
    return generatedPath != null && path.equals(generatedPath, destinationPath);
  }
}
