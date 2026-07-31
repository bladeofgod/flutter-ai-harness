import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_media/app_media.dart';
import 'package:app_media/src/preview/media_poster_service.dart';
import 'package:app_media/src/preview/video_thumbnail_poster_generator.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'media_preview_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const thumbnailChannel = MethodChannel('flutter_video_thumbnail_plus');
  late Directory sandbox;
  late File source;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('poster-generator-');
    source = await File('${sandbox.path}/source.mp4').writeAsBytes(<int>[1]);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(thumbnailChannel, null);
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'default writer maps the bounded JPEG request to the thumbnail plugin',
    () async {
      MethodCall? invocation;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(thumbnailChannel, (call) async {
            invocation = call;
            final arguments = call.arguments as Map<Object?, Object?>;
            final destinationPath = arguments['path']! as String;
            await File(destinationPath).writeAsBytes(<int>[1]);
            return destinationPath;
          });
      final generator = VideoThumbnailPosterGenerator(
        temporaryRootProvider: () async => sandbox,
        tokenProvider: () => '00000000000000000000000000000000',
      );

      final result = await generator.generateJpeg(
        source.uri,
        maximumDimension: 512,
        quality: 82,
      );

      expect(result, orderedEquals(<int>[1]));
      expect(invocation?.method, 'file');
      final arguments = invocation?.arguments as Map<Object?, Object?>;
      expect(arguments['video'], source.path);
      expect(arguments['path'], endsWith('.jpg'));
      expect(arguments['format'], 0);
      expect(arguments['maxw'], 512);
      expect(arguments['maxh'], 512);
      expect(arguments['timeMs'], 0);
      expect(arguments['quality'], 82);
      expect(await _posterFiles(sandbox), isEmpty);
    },
  );

  test('default writer rejects a provider path outside its job', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(thumbnailChannel, (call) async {
          final arguments = call.arguments as Map<Object?, Object?>;
          await File(arguments['path']! as String).writeAsBytes(<int>[1]);
          return '${sandbox.path}/different.jpg';
        });
    final generator = VideoThumbnailPosterGenerator(
      temporaryRootProvider: () async => sandbox,
      tokenProvider: () => '11111111111111111111111111111111',
    );

    final result = await generator.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );

    expect(result, isNull);
    expect(await _posterFiles(sandbox), isEmpty);
  });

  test('concurrent generators never sweep another live output', () async {
    final parentAlias = Link('${sandbox.path}/parent-alias');
    await parentAlias.create(sandbox.parent.path);
    final aliasedSandbox = Directory(
      path.join(parentAlias.path, path.basename(sandbox.path)),
    );
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var sawFirstDuringSecondWrite = false;
    String? firstOutputPath;
    final writer = _FakePosterWriter((request) async {
      expect(request.sourcePath, source.path);
      expect(request.width, 512);
      expect(request.height, 512);
      expect(request.quality, 82);
      final destination = File(request.destinationPath);
      await destination.writeAsBytes(<int>[1]);
      if (firstOutputPath == null) {
        firstOutputPath = destination.path;
        firstStarted.complete();
        await releaseFirst.future;
      } else {
        sawFirstDuringSecondWrite = await File(firstOutputPath!).exists();
      }
      return true;
    });
    final first = _generator(sandbox, writer: writer, token: 'first');
    final second = _generator(aliasedSandbox, writer: writer, token: 'second');

    final firstResult = first.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );
    await firstStarted.future;
    final secondResult = await second.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );
    releaseFirst.complete();

    expect(await firstResult, orderedEquals(<int>[1]));
    expect(secondResult, orderedEquals(<int>[1]));
    expect(sawFirstDuringSecondWrite, isTrue);
    expect(await _posterFiles(sandbox), isEmpty);
  });

  test('preparation lock protects a job before live registration', () async {
    final firstJobCreated = Completer<Directory>();
    final releaseFirstPreparation = Completer<void>();
    var secondWriterStarted = false;
    final first = _generator(
      sandbox,
      token: 'preparing-first',
      createJobRoot: (root) async {
        final jobRoot = await root.createTemp('job-');
        firstJobCreated.complete(jobRoot);
        await releaseFirstPreparation.future;
        return jobRoot;
      },
      writer: _FakePosterWriter((request) async {
        await File(request.destinationPath).writeAsBytes(<int>[1]);
        return true;
      }),
    );
    final second = _generator(
      sandbox,
      token: 'preparing-second',
      writer: _FakePosterWriter((request) async {
        secondWriterStarted = true;
        await File(request.destinationPath).writeAsBytes(<int>[1]);
        return true;
      }),
    );

    final firstResult = first.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );
    final firstJobRoot = await firstJobCreated.future;
    final secondResult = second.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await firstJobRoot.exists(), isTrue);
    expect(secondWriterStarted, isFalse);

    releaseFirstPreparation.complete();
    expect(await firstResult, orderedEquals(<int>[1]));
    expect(await secondResult, orderedEquals(<int>[1]));
    expect(secondWriterStarted, isTrue);
    expect(await _posterFiles(sandbox), isEmpty);
  });

  test('false throw empty and oversized outputs are always deleted', () async {
    final cases = <String, Future<bool> Function(File)>{
      'false': (file) async {
        await file.writeAsBytes(<int>[1]);
        return false;
      },
      'throw': (file) async {
        await file.writeAsBytes(<int>[1]);
        throw StateError('provider failed');
      },
      'empty': (file) async {
        await file.writeAsBytes(<int>[]);
        return true;
      },
      'oversized': (file) async {
        await file.writeAsBytes(
          Uint8List(MediaPoster.maximumBytes + 1),
          flush: true,
        );
        return true;
      },
    };

    for (final entry in cases.entries) {
      final generator = _generator(
        sandbox,
        token: entry.key,
        writer: _FakePosterWriter(
          (request) => entry.value(File(request.destinationPath)),
        ),
      );
      final future = generator.generateJpeg(
        source.uri,
        maximumDimension: 512,
        quality: 82,
      );
      if (entry.key == 'throw') {
        await expectLater(future, throwsStateError);
      } else {
        expect(await future, isNull);
      }
      expect(await _posterFiles(sandbox), isEmpty, reason: entry.key);
    }
  });

  test('bounded read rejects growth after the file stat', () async {
    final generator = _generator(
      sandbox,
      token: 'growing',
      writer: _FakePosterWriter((request) async {
        await File(request.destinationPath).writeAsBytes(<int>[1]);
        return true;
      }),
      readFile: (_, maximumBytes) async* {
        yield Uint8List(maximumBytes + 1);
      },
    );

    final result = await generator.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );

    expect(result, isNull);
    expect(await _posterFiles(sandbox), isEmpty);
  });

  test(
    'a later job sweeps an output left after three delete failures',
    () async {
      var firstDeleteAttempts = 0;
      String? firstOutputPath;
      Future<void> deleteFile(File file) async {
        firstOutputPath ??= file.path;
        if (file.path == firstOutputPath && firstDeleteAttempts++ < 4) {
          throw const FileSystemException('delete failed');
        }
        await file.delete();
      }

      final writer = _FakePosterWriter((request) async {
        await File(request.destinationPath).writeAsBytes(<int>[1]);
        return true;
      });
      final first = _generator(
        sandbox,
        writer: writer,
        token: 'first-failure',
        deleteFile: deleteFile,
      );
      await expectLater(
        first.generateJpeg(source.uri, maximumDimension: 512, quality: 82),
        throwsA(isA<FileSystemException>()),
      );
      final orphan = File(firstOutputPath!);
      expect(await orphan.exists(), isTrue);

      final second = _generator(
        sandbox,
        writer: writer,
        token: 'second-success',
        deleteFile: deleteFile,
      );
      expect(
        await second.generateJpeg(
          source.uri,
          maximumDimension: 512,
          quality: 82,
        ),
        orderedEquals(<int>[1]),
      );

      expect(firstDeleteAttempts, 5);
      expect(await orphan.exists(), isFalse);
      expect(await _posterFiles(sandbox), isEmpty);
    },
  );

  test('orphan sweep deletes a symlink without following it', () async {
    final posterRoot = Directory('${sandbox.path}/app-media-posters');
    await posterRoot.create();
    final orphanRoot = Directory('${posterRoot.path}/job-orphan');
    await orphanRoot.create();
    final sentinel = await File(
      '${sandbox.path}/outside.jpg',
    ).writeAsBytes(<int>[9]);
    final orphanLink = Link('${orphanRoot.path}/orphan.jpg');
    await orphanLink.create(sentinel.path);
    final generator = _generator(
      sandbox,
      token: 'safe',
      writer: _FakePosterWriter((request) async {
        await File(request.destinationPath).writeAsBytes(<int>[1]);
        return true;
      }),
    );

    await generator.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );

    expect(await orphanLink.exists(), isFalse);
    expect(await sentinel.readAsBytes(), <int>[9]);
  });

  test('rejects a symlink poster root without touching its target', () async {
    final outside = Directory('${sandbox.path}/outside')..createSync();
    final sentinel = await File(
      '${outside.path}/sentinel.jpg',
    ).writeAsBytes(<int>[9]);
    await Link('${sandbox.path}/app-media-posters').create(outside.path);
    final generator = _generator(
      sandbox,
      token: 'root-link',
      writer: _FakePosterWriter((_) async => true),
    );

    await expectLater(
      generator.generateJpeg(source.uri, maximumDimension: 512, quality: 82),
      throwsA(isA<FileSystemException>()),
    );

    expect(await sentinel.readAsBytes(), <int>[9]);
  });

  test('rejects and removes a provider-created output symlink', () async {
    final sentinel = await File(
      '${sandbox.path}/outside-output.jpg',
    ).writeAsBytes(<int>[9]);
    final generator = _generator(
      sandbox,
      token: 'output-link',
      writer: _FakePosterWriter((request) async {
        await Link(request.destinationPath).create(sentinel.path);
        return true;
      }),
    );

    final result = await generator.generateJpeg(
      source.uri,
      maximumDimension: 512,
      quality: 82,
    );

    expect(result, isNull);
    expect(await sentinel.readAsBytes(), <int>[9]);
    expect(await _posterFiles(sandbox), isEmpty);
  });

  test('cleanup failure becomes a typed result without path details', () async {
    final id = testResourceId('51');
    final store = FakeMediaResourceStore(
      <MediaResourceId, ResolvedMediaResource>{
        id: testResource(
          id: id,
          kind: MediaResourceKind.video,
          fileUri: source.uri,
        ),
      },
    );
    final generator = _generator(
      sandbox,
      token: 'redacted',
      writer: _FakePosterWriter((request) async {
        await File(request.destinationPath).writeAsBytes(_onePixelJpeg());
        return true;
      }),
      deleteFile: (_) async {
        throw const FileSystemException('delete failed');
      },
    );
    final service = DefaultMediaPosterService(
      store: store,
      generator: generator,
    );

    final result = await service.generate(id);

    expect(
      (result as MediaResourceError<MediaPoster>).failure.code,
      MediaResourceFailureCode.decodeFailed,
    );
    expect(result.toString(), isNot(contains(sandbox.path)));
    expect(result.toString(), isNot(contains(source.path)));
    expect(store.releaseCalls, 1);
  });
}

VideoThumbnailPosterGenerator _generator(
  Directory root, {
  required VideoThumbnailPosterWriter writer,
  required String token,
  MediaPosterJobRootCreate? createJobRoot,
  MediaPosterFileDelete? deleteFile,
  MediaPosterFileRead? readFile,
}) {
  return VideoThumbnailPosterGenerator(
    writer: writer,
    temporaryRootProvider: () async => root,
    createJobRoot: createJobRoot,
    tokenProvider: () =>
        sha256.convert(utf8.encode(token)).toString().substring(0, 32),
    deleteFile: deleteFile,
    readFile: readFile,
  );
}

Future<List<FileSystemEntity>> _posterFiles(Directory root) async {
  final posterRoot = Directory('${root.path}/app-media-posters');
  if (!await posterRoot.exists()) return <FileSystemEntity>[];
  return posterRoot.list(followLinks: false).toList();
}

typedef _PosterWrite = Future<bool> Function(_PosterWriteRequest request);

final class _FakePosterWriter implements VideoThumbnailPosterWriter {
  const _FakePosterWriter(this.callback);

  final _PosterWrite callback;

  @override
  Future<bool> write({
    required String sourcePath,
    required String destinationPath,
    required int width,
    required int height,
    required int quality,
  }) {
    return callback(
      _PosterWriteRequest(
        sourcePath: sourcePath,
        destinationPath: destinationPath,
        width: width,
        height: height,
        quality: quality,
      ),
    );
  }
}

final class _PosterWriteRequest {
  const _PosterWriteRequest({
    required this.sourcePath,
    required this.destinationPath,
    required this.width,
    required this.height,
    required this.quality,
  });

  final String sourcePath;
  final String destinationPath;
  final int width;
  final int height;
  final int quality;
}

Uint8List _onePixelJpeg() => base64Decode(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////'
  '////////////////////////////////////////////////////////2wBDAf//'
  '////////////////////////////////////////////////////////////////////'
  '////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA'
  'AAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBAB'
  'AAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAA'
  'AP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QA'
  'FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAA'
  'AAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAA'
  'AAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//'
  'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==',
);
