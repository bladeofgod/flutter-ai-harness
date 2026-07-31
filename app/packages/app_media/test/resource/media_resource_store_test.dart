import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_media/app_media.dart';
import 'package:app_media/src/resource/default_media_resource_store.dart';
import 'package:app_media/src/resource/flutter_image_canonicalizer.dart';
import 'package:app_media/src/resource/local_media_resource_file_system.dart';
import 'package:app_media/src/resource/media_resource_file_system.dart';
import 'package:app_media/src/resource/media_resource_support.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Directory cacheDirectory;
  late _FakeClock clock;
  late _SequenceRandom random;
  final stores = <MediaResourceStore>[];

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('app-media-test-');
    cacheDirectory = await Directory('${sandbox.path}/cache').create();
    clock = _FakeClock(DateTime.utc(2026, 7, 30));
    random = _SequenceRandom();
  });

  tearDown(() async {
    for (final store in stores.reversed) {
      await store.dispose();
    }
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  Future<DefaultMediaResourceStore> createStore({
    SourceVerificationHook? sourceVerificationHook,
    SourceInspectionHook? sourceInspectionHook,
    MediaResourceFileSystem? fileSystem,
    MediaImageCanonicalizer imageCanonicalizer =
        const FlutterMediaImageCanonicalizer(),
  }) async {
    final store = await DefaultMediaResourceStore.create(
      fileSystem:
          fileSystem ??
          LocalMediaResourceFileSystem(
            cacheDirectoryProvider: () async => cacheDirectory,
            sourceVerificationHook: sourceVerificationHook,
            sourceInspectionHook: sourceInspectionHook,
          ),
      imageCanonicalizer: imageCanonicalizer,
      random: random,
      clock: clock,
    );
    stores.add(store);
    return store;
  }

  Future<File> sourceFile(String name, List<int> bytes) async {
    final file = File('${sandbox.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  MediaImportRequest requestFor(
    File file, {
    required MediaResourceKind kind,
    required String contentType,
    Duration? duration,
    MediaImportCancellation? cancellation,
  }) {
    return MediaImportRequest(
      sourceUri: file.uri,
      kind: kind,
      declaredContentType: contentType,
      declaredLength: file.lengthSync(),
      duration: duration,
      cancellation: cancellation,
    );
  }

  group('image import', () {
    test(
      'decodes and rewrites a JPEG as metadata-free canonical PNG',
      () async {
        final sourceBytes = _jpegWithExifSegment();
        final source = await sourceFile('customer-photo.jpg', sourceBytes);
        final store = await createStore();

        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/jpeg',
            ),
          ),
        );
        final resolved = _success(
          await store.resolve(owned.resourceId, owned.initialLease),
        );
        final canonicalBytes = await File.fromUri(
          resolved.fileUri,
        ).readAsBytes();

        expect(owned.contentType, 'image/png');
        expect(owned.length, canonicalBytes.length);
        expect(canonicalBytes.take(_pngSignature.length), _pngSignature);
        expect(canonicalBytes, isNot(containsAllInOrder('Exif'.codeUnits)));
        expect(canonicalBytes, isNot(equals(sourceBytes)));
        expect(resolved.toString(), isNot(contains(resolved.fileUri.path)));
        expect(owned.toString(), isNot(contains(owned.resourceId.value)));
      },
    );

    test(
      'rejects MIME mismatch, fake extensions, and invalid image data',
      () async {
        final store = await createStore();
        final png = await sourceFile('renamed.jpg', _onePixelPng());
        final fake = await sourceFile('looks-valid.png', _validVideo());
        final invalid = await sourceFile('truncated.png', <int>[
          ..._pngSignature,
          1,
          2,
          3,
        ]);

        expect(
          _failureCode(
            await store.importFile(
              requestFor(
                png,
                kind: MediaResourceKind.image,
                contentType: 'image/jpeg',
              ),
            ),
          ),
          MediaResourceFailureCode.unsupportedMedia,
        );
        expect(
          _failureCode(
            await store.importFile(
              requestFor(
                fake,
                kind: MediaResourceKind.image,
                contentType: 'image/png',
              ),
            ),
          ),
          MediaResourceFailureCode.unsupportedMedia,
        );
        expect(
          _failureCode(
            await store.importFile(
              requestFor(
                invalid,
                kind: MediaResourceKind.image,
                contentType: 'image/png',
              ),
            ),
          ),
          MediaResourceFailureCode.unsupportedMedia,
        );
      },
    );

    test(
      'maps an oversized canonical image without leaving a staging file',
      () async {
        final source = await sourceFile('photo.png', _onePixelPng());
        final store = await createStore(
          imageCanonicalizer: _OversizedImageCanonicalizer(),
        );

        final result = await store.importFile(
          requestFor(
            source,
            kind: MediaResourceKind.image,
            contentType: 'image/png',
          ),
        );

        expect(_failureCode(result), MediaResourceFailureCode.tooLarge);
        expect(await _storedEntries(cacheDirectory), isEmpty);
      },
    );

    test('enforces a bounded decoded RGBA memory budget', () {
      expect(
        FlutterMediaImageCanonicalizer.acceptsDimensions(4096, 4096),
        isTrue,
      );
      expect(
        FlutterMediaImageCanonicalizer.acceptsDimensions(8192, 2048),
        isTrue,
      );
      expect(
        FlutterMediaImageCanonicalizer.acceptsDimensions(4097, 4096),
        isFalse,
      );
      expect(
        FlutterMediaImageCanonicalizer.acceptsDimensions(8192, 2049),
        isFalse,
      );
    });
  });

  group('video import', () {
    test('streams an ISO BMFF source and preserves bounded metadata', () async {
      final source = await sourceFile('clip.mov', _validVideo());
      final store = await createStore();

      final owned = _success(
        await store.importFile(
          requestFor(
            source,
            kind: MediaResourceKind.video,
            contentType: 'video/quicktime',
            duration: const Duration(seconds: 8),
          ),
        ),
      );
      final resolved = _success(
        await store.resolve(owned.resourceId, owned.initialLease),
      );

      expect(owned.contentType, 'video/quicktime');
      expect(owned.duration, const Duration(seconds: 8));
      expect(await File.fromUri(resolved.fileUri).readAsBytes(), _validVideo());
      expect(resolved.fileUri.path, endsWith('.mov'));
    });

    test('rejects invalid containers and declared length drift', () async {
      final invalid = await sourceFile('invalid.mp4', List<int>.filled(32, 0));
      final valid = await sourceFile('changed.mp4', _validVideo());
      final store = await createStore();

      expect(
        _failureCode(
          await store.importFile(
            requestFor(
              invalid,
              kind: MediaResourceKind.video,
              contentType: 'video/mp4',
            ),
          ),
        ),
        MediaResourceFailureCode.unsupportedMedia,
      );
      expect(
        _failureCode(
          await store.importFile(
            MediaImportRequest(
              sourceUri: valid.uri,
              kind: MediaResourceKind.video,
              declaredContentType: 'video/mp4',
              declaredLength: valid.lengthSync() + 1,
            ),
          ),
        ),
        MediaResourceFailureCode.invalid,
      );
      expect(await _storedEntries(cacheDirectory), isEmpty);
    });

    test('rejects unknown brands and ftyp-only pseudo videos', () async {
      final unknownBrand = await sourceFile(
        'unknown.mp4',
        _videoWithBrand('zzzz'),
      );
      final fileTypeOnly = await sourceFile(
        'header-only.mp4',
        _validVideo().sublist(0, 20),
      );
      final store = await createStore();

      for (final source in <File>[unknownBrand, fileTypeOnly]) {
        expect(
          _failureCode(
            await store.importFile(
              requestFor(
                source,
                kind: MediaResourceKind.video,
                contentType: 'video/mp4',
              ),
            ),
          ),
          MediaResourceFailureCode.unsupportedMedia,
        );
      }
      expect(await _storedEntries(cacheDirectory), isEmpty);
    });

    test(
      'detects same-length source replacement and removes staging',
      () async {
        final original = _validVideo(payload: 1);
        final replacement = _validVideo(payload: 2);
        final source = await sourceFile('racing.mp4', original);
        final store = await createStore(
          sourceVerificationHook: () async {
            await source.writeAsBytes(replacement, flush: true);
          },
        );

        final result = await store.importFile(
          requestFor(
            source,
            kind: MediaResourceKind.video,
            contentType: 'video/mp4',
          ),
        );

        expect(_failureCode(result), MediaResourceFailureCode.invalid);
        expect(await _storedEntries(cacheDirectory), isEmpty);
      },
    );

    for (final mutation in <String, Future<void> Function(File)>{
      'growth': (file) async {
        await file.writeAsBytes(<int>[9], mode: FileMode.append, flush: true);
      },
      'truncation': (file) async {
        final bytes = _validVideo();
        await file.writeAsBytes(
          bytes.sublist(0, bytes.length - 1),
          flush: true,
        );
      },
    }.entries) {
      test('detects source ${mutation.key} during import', () async {
        final source = await sourceFile('mutating.mp4', _validVideo());
        final store = await createStore(
          sourceVerificationHook: () async {
            await mutation.value(source);
          },
        );

        final result = await store.importFile(
          requestFor(
            source,
            kind: MediaResourceKind.video,
            contentType: 'video/mp4',
          ),
        );

        expect(_failureCode(result), MediaResourceFailureCode.invalid);
        expect(await _storedEntries(cacheDirectory), isEmpty);
      });
    }
  });

  group('input boundary', () {
    test(
      'rejects non-file, traversal, overlong, and oversized requests',
      () async {
        final source = await sourceFile('photo.png', _onePixelPng());
        final store = await createStore();
        final requests = <MediaImportRequest>[
          MediaImportRequest(
            sourceUri: Uri.parse('content://picker/private/photo.png'),
            kind: MediaResourceKind.image,
            declaredContentType: 'image/png',
            declaredLength: source.lengthSync(),
          ),
          MediaImportRequest(
            sourceUri: Uri.parse('file:///tmp/folder/../private.png'),
            kind: MediaResourceKind.image,
            declaredContentType: 'image/png',
            declaredLength: source.lengthSync(),
          ),
          MediaImportRequest(
            sourceUri: Uri.parse('file:///tmp/${'a' * 256}.png'),
            kind: MediaResourceKind.image,
            declaredContentType: 'image/png',
            declaredLength: source.lengthSync(),
          ),
        ];

        for (final request in requests) {
          expect(
            _failureCode(await store.importFile(request)),
            MediaResourceFailureCode.invalidArgument,
          );
        }
        expect(
          _failureCode(
            await store.importFile(
              MediaImportRequest(
                sourceUri: source.uri,
                kind: MediaResourceKind.image,
                declaredContentType: 'image/png',
                declaredLength: DefaultMediaResourceStore.maximumImageBytes + 1,
              ),
            ),
          ),
          MediaResourceFailureCode.tooLarge,
        );
      },
    );

    test('rejects a symbolic-link source without leaking its target', () async {
      final source = await sourceFile('private-photo.png', _onePixelPng());
      final link = Link('${sandbox.path}/selected.png');
      await link.create(source.path);
      final store = await createStore();

      final result = await store.importFile(
        MediaImportRequest(
          sourceUri: link.uri,
          kind: MediaResourceKind.image,
          declaredContentType: 'image/png',
          declaredLength: source.lengthSync(),
        ),
      );

      final failure = _failure(result);
      expect(failure.code, MediaResourceFailureCode.invalidArgument);
      expect(failure.toString(), isNot(contains(source.path)));
      expect(failure.message, isNot(contains(source.path)));
    });

    test(
      'rejects a final source swapped to a symlink during inspection',
      () async {
        final source = await sourceFile('selected.png', _onePixelPng());
        final target = await sourceFile('private.png', _onePixelPng());
        var swapped = false;
        final store = await createStore(
          sourceInspectionHook: () async {
            if (swapped) {
              return;
            }
            swapped = true;
            await source.delete();
            await Link(source.path).create(target.path);
          },
        );

        final result = await store.importFile(
          MediaImportRequest(
            sourceUri: source.uri,
            kind: MediaResourceKind.image,
            declaredContentType: 'image/png',
            declaredLength: target.lengthSync(),
          ),
        );

        expect(_failureCode(result), MediaResourceFailureCode.invalidArgument);
        expect(result.toString(), isNot(contains(target.path)));
        expect(await _storedEntries(cacheDirectory), isEmpty);
      },
    );

    test(
      'rejects a symbolic-link store root without touching its target',
      () async {
        final outside = await Directory('${sandbox.path}/outside').create();
        final marker = File('${outside.path}/keep.txt');
        await marker.writeAsString('keep');
        await Link(
          '${cacheDirectory.path}/media_resources_v1',
        ).create(outside.path);
        final fileSystem = LocalMediaResourceFileSystem(
          cacheDirectoryProvider: () async => cacheDirectory,
        );

        await expectLater(
          DefaultMediaResourceStore.create(
            fileSystem: fileSystem,
            imageCanonicalizer: const FlutterMediaImageCanonicalizer(),
            random: random,
            clock: clock,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              isNot(contains(outside.path)),
            ),
          ),
        );
        expect(await marker.readAsString(), 'keep');
      },
    );

    test(
      'cancellation is typed and diagnostics redact source metadata',
      () async {
        final source = await sourceFile('sensitive-name.png', _onePixelPng());
        final cancellation = MediaImportCancellation()..cancel();
        final request = requestFor(
          source,
          kind: MediaResourceKind.image,
          contentType: 'image/png',
          cancellation: cancellation,
        );
        final store = await createStore();

        final result = await store.importFile(request);

        expect(_failureCode(result), MediaResourceFailureCode.cancelled);
        expect(request.toString(), isNot(contains(source.path)));
        expect(request.toString(), isNot(contains('sensitive-name')));
        expect(result.toString(), isNot(contains(source.path)));
      },
    );
  });

  group('lease lifecycle', () {
    test(
      'retains independently and deletes after the final idempotent release',
      () async {
        final source = await sourceFile('photo.png', _onePixelPng());
        final store = await createStore();
        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        );
        final retained = _success(await store.retain(owned.resourceId));

        expect(
          await store.release(owned.initialLease),
          isA<MediaResourceSuccess<void>>(),
        );
        expect(
          await store.resolve(owned.resourceId, retained),
          isA<MediaResourceSuccess<ResolvedMediaResource>>(),
        );
        expect(
          await store.release(retained),
          isA<MediaResourceSuccess<void>>(),
        );
        expect(
          await store.release(retained),
          isA<MediaResourceSuccess<void>>(),
        );
        expect(
          _failureCode(await store.retain(owned.resourceId)),
          MediaResourceFailureCode.missing,
        );
        expect(await _storedEntries(cacheDirectory), isEmpty);
      },
    );

    test(
      'retains cleanup ownership until a failed delete can be retried',
      () async {
        final source = await sourceFile('retry-delete.png', _onePixelPng());
        final delegate = LocalMediaResourceFileSystem(
          cacheDirectoryProvider: () async => cacheDirectory,
        );
        final fileSystem = _FailingDeleteFileSystem(
          delegate,
          remainingDeleteFailures: 3,
        );
        final store = await createStore(fileSystem: fileSystem);
        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        );
        final resolved = _success(
          await store.resolve(owned.resourceId, owned.initialLease),
        );

        expect(
          _failureCode(await store.release(owned.initialLease)),
          MediaResourceFailureCode.importFailed,
        );
        expect(await File.fromUri(resolved.fileUri).exists(), isTrue);
        expect(
          await store.release(owned.initialLease),
          isA<MediaResourceSuccess<void>>(),
        );
        expect(await File.fromUri(resolved.fileUri).exists(), isFalse);
        expect(fileSystem.deleteCalls, 4);
      },
    );

    test(
      'dispose converges retained cleanup after repeated delete failures',
      () async {
        final source = await sourceFile('dispose-delete.png', _onePixelPng());
        final delegate = LocalMediaResourceFileSystem(
          cacheDirectoryProvider: () async => cacheDirectory,
        );
        final fileSystem = _FailingDeleteFileSystem(
          delegate,
          remainingDeleteFailures: 7,
        );
        final store = await createStore(fileSystem: fileSystem);
        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        );

        expect(
          _failureCode(await store.release(owned.initialLease)),
          MediaResourceFailureCode.importFailed,
        );
        await store.dispose();

        expect(fileSystem.remainingDeleteFailures, 0);
        expect(await _storedEntries(cacheDirectory), isEmpty);
      },
    );

    test(
      'rejects foreign leases without decrementing valid ownership',
      () async {
        final source = await sourceFile('photo.png', _onePixelPng());
        final store = await createStore();
        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        );
        final foreign = _ForeignLease(owned.resourceId);

        expect(
          _failureCode(await store.release(foreign)),
          MediaResourceFailureCode.invalidArgument,
        );
        expect(
          _failureCode(await store.resolve(owned.resourceId, foreign)),
          MediaResourceFailureCode.invalidArgument,
        );
        expect(
          await store.resolve(owned.resourceId, owned.initialLease),
          isA<MediaResourceSuccess<ResolvedMediaResource>>(),
        );
      },
    );

    test(
      'invalidates a replaced canonical file with a stable tombstone',
      () async {
        final source = await sourceFile('photo.png', _onePixelPng());
        final store = await createStore();
        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        );
        final resolved = _success(
          await store.resolve(owned.resourceId, owned.initialLease),
        );
        await File.fromUri(
          resolved.fileUri,
        ).writeAsBytes(List<int>.filled(resolved.length, 0), flush: true);

        expect(
          _failureCode(
            await store.resolve(owned.resourceId, owned.initialLease),
          ),
          MediaResourceFailureCode.invalid,
        );
        expect(
          _failureCode(await store.retain(owned.resourceId)),
          MediaResourceFailureCode.invalid,
        );
        expect(owned.initialLease.isActive, isFalse);
      },
    );
  });

  group('store lifecycle', () {
    test('cleans previous-process files before accepting resources', () async {
      final root = await Directory(
        '${cacheDirectory.path}/media_resources_v1',
      ).create();
      final orphan = File(
        '${root.path}/mr_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png',
      );
      final staging = File(
        '${root.path}/mr_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.mp4.part',
      );
      await orphan.writeAsBytes(_onePixelPng());
      await staging.writeAsBytes(_validVideo());

      await createStore();

      expect(await root.list().toList(), isEmpty);
    });

    test(
      'dispose is exactly once, removes active files, and rejects new calls',
      () async {
        final source = await sourceFile('photo.png', _onePixelPng());
        final delegate = LocalMediaResourceFileSystem(
          cacheDirectoryProvider: () async => cacheDirectory,
        );
        final fileSystem = _CountingFileSystem(delegate);
        final store = await createStore(fileSystem: fileSystem);
        final owned = _success(
          await store.importFile(
            requestFor(
              source,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        );

        final first = store.dispose();
        final second = store.dispose();
        await Future.wait(<Future<void>>[first, second]);

        expect(first, same(second));
        expect(fileSystem.cleanCalls, 2);
        expect(owned.initialLease.isActive, isFalse);
        expect(await _storedEntries(cacheDirectory), isEmpty);
        expect(
          _failureCode(
            await store.importFile(
              requestFor(
                source,
                kind: MediaResourceKind.image,
                contentType: 'image/png',
              ),
            ),
          ),
          MediaResourceFailureCode.storeClosed,
        );
      },
    );

    test(
      'dispose cancels a late import and leaves no committed file',
      () async {
        final source = await sourceFile('late.png', _onePixelPng());
        final verificationStarted = Completer<void>();
        final allowVerification = Completer<void>();
        final store = await createStore(
          sourceVerificationHook: () async {
            verificationStarted.complete();
            await allowVerification.future;
          },
        );

        final importFuture = store.importFile(
          requestFor(
            source,
            kind: MediaResourceKind.image,
            contentType: 'image/png',
          ),
        );
        await verificationStarted.future;
        final disposeFuture = store.dispose();
        allowVerification.complete();

        expect(
          _failureCode(await importFuture),
          MediaResourceFailureCode.cancelled,
        );
        await disposeFuture;
        expect(await _storedEntries(cacheDirectory), isEmpty);
      },
    );

    test(
      'serializes concurrent imports and never reuses a collided ID',
      () async {
        random = _SequenceRandom(collisionOnSecondCall: true);
        final firstSource = await sourceFile('first.png', _onePixelPng());
        final secondSource = await sourceFile('second.png', _onePixelPng());
        final store = await createStore();

        final results = await Future.wait(<Future<MediaImportResult>>[
          store.importFile(
            requestFor(
              firstSource,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
          store.importFile(
            requestFor(
              secondSource,
              kind: MediaResourceKind.image,
              contentType: 'image/png',
            ),
          ),
        ]);
        final ids = results
            .map(_success)
            .map((resource) => resource.resourceId);

        expect(ids.toSet(), hasLength(2));
        expect(random.calls, 3);
      },
    );
  });
}

T _success<T>(MediaResourceResult<T> result) {
  return switch (result) {
    MediaResourceSuccess<T>(:final value) => value,
    MediaResourceError<T>(:final failure) => throw TestFailure(
      'Expected success, got ${failure.code.wireValue}',
    ),
  };
}

MediaResourceFailure _failure<T>(MediaResourceResult<T> result) {
  return switch (result) {
    MediaResourceSuccess<T>() => throw TestFailure('Expected failure'),
    MediaResourceError<T>(:final failure) => failure,
  };
}

MediaResourceFailureCode _failureCode<T>(MediaResourceResult<T> result) {
  return _failure(result).code;
}

Future<List<FileSystemEntity>> _storedEntries(Directory cacheDirectory) async {
  final root = Directory('${cacheDirectory.path}/media_resources_v1');
  if (!await root.exists()) {
    return const <FileSystemEntity>[];
  }
  return root.list().toList();
}

const List<int> _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

const String _onePixelJpegBase64 =
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////'
    '////////////////////////////////////////////////////////2wBDAf//'
    '////////////////////////////////////////////////////////////////////'
    '////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAA'
    'AAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBAB'
    'AAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAA'
    'AP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QA'
    'FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAA'
    'AAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAA'
    'AAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//'
    'xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==';

Uint8List _jpegWithExifSegment() {
  final jpeg = base64Decode(_onePixelJpegBase64);
  return Uint8List.fromList(<int>[
    0xff,
    0xd8,
    0xff,
    0xe1,
    0x00,
    0x08,
    0x45,
    0x78,
    0x69,
    0x66,
    0x00,
    0x00,
    ...jpeg.skip(2),
  ]);
}

Uint8List _validVideo({int payload = 1}) =>
    _videoWithBrand('isom', payload: payload);

Uint8List _videoWithBrand(String brand, {int payload = 1}) {
  assert(brand.length == 4);
  return Uint8List.fromList(<int>[
    0,
    0,
    0,
    20,
    0x66,
    0x74,
    0x79,
    0x70,
    ...brand.codeUnits,
    0,
    0,
    0,
    0,
    ...brand.codeUnits,
    0,
    0,
    0,
    12,
    0x6d,
    0x64,
    0x61,
    0x74,
    payload,
    payload,
    payload,
    payload,
  ]);
}

final class _FakeClock implements MediaResourceClock {
  _FakeClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}

final class _SequenceRandom implements MediaResourceRandom {
  _SequenceRandom({this.collisionOnSecondCall = false});

  final bool collisionOnSecondCall;
  int calls = 0;

  @override
  Uint8List nextBytes(int length) {
    calls += 1;
    final value = collisionOnSecondCall && calls == 2 ? 1 : calls;
    return Uint8List.fromList(List<int>.filled(length, value));
  }
}

final class _OversizedImageCanonicalizer implements MediaImageCanonicalizer {
  @override
  Future<CanonicalImage> canonicalize(Uint8List encodedBytes) async {
    return CanonicalImage(
      bytes: Uint8List(DefaultMediaResourceStore.maximumImageBytes + 1),
      contentType: 'image/png',
    );
  }
}

final class _ForeignLease implements MediaResourceLease {
  _ForeignLease(this.resourceId);

  @override
  final MediaResourceId resourceId;

  @override
  bool get isActive => true;

  @override
  String toString() => 'ForeignLease(<redacted>)';
}

final class _CountingFileSystem implements MediaResourceFileSystem {
  _CountingFileSystem(this.delegate);

  final MediaResourceFileSystem delegate;
  int cleanCalls = 0;

  @override
  Future<void> cleanRoot(MediaResourceRoot root) {
    cleanCalls += 1;
    return delegate.cleanRoot(root);
  }

  @override
  Future<void> commit(
    MediaResourceRoot root,
    String stagingName,
    String finalName,
  ) {
    return delegate.commit(root, stagingName, finalName);
  }

  @override
  Future<void> delete(MediaResourceRoot root, String name) {
    return delegate.delete(root, name);
  }

  @override
  Future<MediaResourceRoot> initializeRoot() => delegate.initializeRoot();

  @override
  Future<StoredMediaFile> inspectStored(
    MediaResourceRoot root,
    String finalName,
  ) {
    return delegate.inspectStored(root, finalName);
  }

  @override
  Future<StableMediaSource> readStableSource(
    Uri sourceUri, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  }) {
    return delegate.readStableSource(
      sourceUri,
      expectedLength: expectedLength,
      maximumLength: maximumLength,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<StagedMediaFile> stageStableVideo(
    MediaResourceRoot root,
    Uri sourceUri,
    String stagingName, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  }) {
    return delegate.stageStableVideo(
      root,
      sourceUri,
      stagingName,
      expectedLength: expectedLength,
      maximumLength: maximumLength,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<void> writeStaging(
    MediaResourceRoot root,
    String stagingName,
    Uint8List bytes, {
    required bool Function() isCancelled,
  }) {
    return delegate.writeStaging(
      root,
      stagingName,
      bytes,
      isCancelled: isCancelled,
    );
  }
}

final class _FailingDeleteFileSystem implements MediaResourceFileSystem {
  _FailingDeleteFileSystem(
    this.delegate, {
    required this.remainingDeleteFailures,
  });

  final MediaResourceFileSystem delegate;
  int remainingDeleteFailures;
  int deleteCalls = 0;

  @override
  Future<void> cleanRoot(MediaResourceRoot root) => delegate.cleanRoot(root);

  @override
  Future<void> commit(
    MediaResourceRoot root,
    String stagingName,
    String finalName,
  ) {
    return delegate.commit(root, stagingName, finalName);
  }

  @override
  Future<void> delete(MediaResourceRoot root, String name) async {
    deleteCalls += 1;
    if (remainingDeleteFailures > 0) {
      remainingDeleteFailures -= 1;
      throw const MediaFileSystemException(
        MediaFileSystemFailureReason.operationFailed,
      );
    }
    await delegate.delete(root, name);
  }

  @override
  Future<MediaResourceRoot> initializeRoot() => delegate.initializeRoot();

  @override
  Future<StoredMediaFile> inspectStored(
    MediaResourceRoot root,
    String finalName,
  ) {
    return delegate.inspectStored(root, finalName);
  }

  @override
  Future<StableMediaSource> readStableSource(
    Uri sourceUri, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  }) {
    return delegate.readStableSource(
      sourceUri,
      expectedLength: expectedLength,
      maximumLength: maximumLength,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<StagedMediaFile> stageStableVideo(
    MediaResourceRoot root,
    Uri sourceUri,
    String stagingName, {
    required int expectedLength,
    required int maximumLength,
    required bool Function() isCancelled,
  }) {
    return delegate.stageStableVideo(
      root,
      sourceUri,
      stagingName,
      expectedLength: expectedLength,
      maximumLength: maximumLength,
      isCancelled: isCancelled,
    );
  }

  @override
  Future<void> writeStaging(
    MediaResourceRoot root,
    String stagingName,
    Uint8List bytes, {
    required bool Function() isCancelled,
  }) {
    return delegate.writeStaging(
      root,
      stagingName,
      bytes,
      isCancelled: isCancelled,
    );
  }
}
