import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_media/app_media.dart';
import 'package:app_media/src/preview/media_playback_driver.dart';
import 'package:app_media/src/preview/media_playback_probe.dart';
import 'package:app_media/src/preview/media_poster_generator.dart';
import 'package:app_media/src/preview/media_poster_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'media_preview_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('media-preview-service-');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('MediaPlaybackProbe', () {
    test(
      'initializes a real-driver boundary and releases exactly once',
      () async {
        final id = testResourceId('1');
        final file = await File(
          '${sandbox.path}/clip.mp4',
        ).writeAsBytes(<int>[1]);
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        );
        final driver = FakeMediaPlaybackDriver();
        final probe = DefaultMediaPlaybackProbe(
          store: store,
          driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
        );

        final result = await probe.probe(id);

        expect(result, isA<MediaResourceSuccess<MediaPlaybackInfo>>());
        expect(
          (result as MediaResourceSuccess<MediaPlaybackInfo>).value.duration,
          const Duration(minutes: 2),
        );
        expect(driver.initializeCalls, 1);
        expect(driver.disposeCalls, 1);
        expect(store.retainCalls, 1);
        expect(store.releaseCalls, 1);
      },
    );

    test(
      'maps unsupported initialization without leaking driver details',
      () async {
        final id = testResourceId('2');
        final file = await File(
          '${sandbox.path}/unsupported.mov',
        ).writeAsBytes(<int>[1]);
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        );
        final probe = DefaultMediaPlaybackProbe(
          store: store,
          driverFactory: FakeMediaPlaybackDriverFactory(
            () => FakeMediaPlaybackDriver(
              initializeError: const UnsupportedMediaPlaybackException(),
            ),
          ),
        );

        final result = await probe.probe(id);

        expect(
          (result as MediaResourceError<MediaPlaybackInfo>).failure.code,
          MediaResourceFailureCode.unsupportedMedia,
        );
        expect(store.releaseCalls, 1);
        expect(result.toString(), isNot(contains(file.path)));
      },
    );

    test('dispose failure still releases the probe lease', () async {
      final id = testResourceId('42');
      final file = await File(
        '${sandbox.path}/dispose-error.mp4',
      ).writeAsBytes(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final driver = FakeMediaPlaybackDriver(
        disposeError: const FormatException(),
      );
      final probe = DefaultMediaPlaybackProbe(
        store: store,
        driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
      );

      final result = await probe.probe(id);

      expect(result, isA<MediaResourceSuccess<MediaPlaybackInfo>>());
      expect(driver.disposeCalls, 1);
      expect(store.releaseCalls, 1);
      expect(store.releaseAttempts, 1);
    });

    test(
      'cancellation completes without waiting for late initialization',
      () async {
        final id = testResourceId('3');
        final file = await File(
          '${sandbox.path}/late.mp4',
        ).writeAsBytes(<int>[1]);
        final gate = Completer<void>();
        final cancellation = MediaPreviewCancellation();
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        );
        final driver = FakeMediaPlaybackDriver(initializeGate: gate);
        final probe = DefaultMediaPlaybackProbe(
          store: store,
          driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
        );

        final future = probe.probe(id, cancellation: cancellation);
        await _waitFor(() => driver.initializeCalls == 1);
        cancellation.cancel();
        final result = await future;

        expect(
          (result as MediaResourceError<MediaPlaybackInfo>).failure.code,
          MediaResourceFailureCode.cancelled,
        );
        expect(driver.disposeCalls, 1);
        expect(store.releaseCalls, 1);
        gate.complete();
        await Future<void>.delayed(Duration.zero);
        expect(driver.disposeCalls, 1);
        expect(store.releaseCalls, 1);
      },
    );

    test(
      'cancellation covers a pending retain and releases its late lease',
      () async {
        final id = testResourceId('41');
        final file = await File(
          '${sandbox.path}/probe-late-retain.mp4',
        ).writeAsBytes(<int>[1]);
        final retainGate = Completer<void>();
        final cancellation = MediaPreviewCancellation();
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        )..retainGate = retainGate;
        final factory = FakeMediaPlaybackDriverFactory(
          FakeMediaPlaybackDriver.new,
        );
        final probe = DefaultMediaPlaybackProbe(
          store: store,
          driverFactory: factory,
        );

        final future = probe.probe(id, cancellation: cancellation);
        await _waitFor(() => store.retainCalls == 1);
        cancellation.cancel();
        final result = await future;

        expect(
          (result as MediaResourceError<MediaPlaybackInfo>).failure.code,
          MediaResourceFailureCode.cancelled,
        );
        expect(factory.drivers, isEmpty);
        expect(store.releaseCalls, 0);
        retainGate.complete();
        await _waitFor(() => store.releaseCalls == 1);
        expect(store.releaseAttempts, 1);
      },
    );
  });

  group('MediaPosterService', () {
    test(
      'bounded poster model rejects oversized or metadata-bearing input',
      () {
        expect(
          () => MediaPoster.png(
            bytes: Uint8List(MediaPoster.maximumBytes + 1),
            width: 1,
            height: 1,
          ),
          throwsArgumentError,
        );
        expect(
          () => MediaPoster.png(
            bytes: _metadataBearingPng(),
            width: 1,
            height: 1,
          ),
          throwsArgumentError,
        );
        final corruptCrc = _metadataFreePng()..last ^= 1;
        final unknownCriticalChunk = _pngWithChunk('ABCD', const <int>[]);
        final trailingData = Uint8List.fromList(<int>[
          ..._metadataFreePng(),
          1,
        ]);
        for (final invalid in <Uint8List>[
          corruptCrc,
          unknownCriticalChunk,
          trailingData,
        ]) {
          expect(
            () => MediaPoster.png(bytes: invalid, width: 1, height: 1),
            throwsArgumentError,
          );
        }
      },
    );

    test('bounds global native work to two jobs', () async {
      final generator = _ControlledPosterGenerator(_metadataFreeJpeg());
      final stores = <FakeMediaResourceStore>[];
      final futures = <Future<MediaResourceResult<MediaPoster>>>[];
      for (var index = 1; index <= 3; index += 1) {
        final id = testResourceId('$index');
        final file = await File(
          '${sandbox.path}/$index.mp4',
        ).writeAsBytes(<int>[1]);
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        );
        stores.add(store);
        futures.add(
          DefaultMediaPosterService(
            store: store,
            generator: generator,
          ).generate(id),
        );
      }

      await _waitFor(() => generator.calls == 2);
      expect(generator.maximumActive, 2);
      generator.completeNext();
      await _waitFor(() => generator.calls == 3);
      generator.completeAll();
      final results = await Future.wait(futures);

      expect(results, everyElement(isA<MediaResourceSuccess<MediaPoster>>()));
      expect(generator.maximumActive, 2);
      expect(stores.map((store) => store.releaseCalls), everyElement(1));
    });

    test('timeout keeps the lease until the late provider settles', () async {
      final id = testResourceId('4');
      final file = await File(
        '${sandbox.path}/timeout.mp4',
      ).writeAsBytes(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final generator = _ControlledPosterGenerator(_metadataFreeJpeg());
      final service = DefaultMediaPosterService(
        store: store,
        generator: generator,
        deadline: const Duration(milliseconds: 20),
      );

      final result = await service.generate(id);

      expect(
        (result as MediaResourceError<MediaPoster>).failure.code,
        MediaResourceFailureCode.cancelled,
      );
      expect(store.releaseCalls, 0);
      generator.completeAll();
      await _waitFor(() => store.releaseCalls == 1);
      expect(store.releaseCalls, 1);
      expect(store.releaseAttempts, 1);
    });

    test(
      'deadline covers a pending retain and releases its late lease',
      () async {
        final id = testResourceId('40');
        final file = await File(
          '${sandbox.path}/late-retain.mp4',
        ).writeAsBytes(<int>[1]);
        final retainGate = Completer<void>();
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        )..retainGate = retainGate;
        final service = DefaultMediaPosterService(
          store: store,
          generator: _ImmediatePosterGenerator(_metadataFreeJpeg()),
          deadline: const Duration(milliseconds: 20),
        );

        final result = await service.generate(id);

        expect(
          (result as MediaResourceError<MediaPoster>).failure.code,
          MediaResourceFailureCode.cancelled,
        );
        expect(store.releaseCalls, 0);
        retainGate.complete();
        await _waitFor(() => store.releaseCalls == 1);
        expect(store.releaseAttempts, 1);
      },
    );

    test(
      'queued jobs keep their own deadline behind two hung providers',
      () async {
        final generator = _ControlledPosterGenerator(_metadataFreeJpeg());
        final stores = <FakeMediaResourceStore>[];
        final futures = <Future<MediaResourceResult<MediaPoster>>>[];
        for (var index = 20; index <= 22; index += 1) {
          final id = testResourceId('$index');
          final file = await File(
            '${sandbox.path}/queued-$index.mp4',
          ).writeAsBytes(<int>[1]);
          final store = FakeMediaResourceStore(
            <MediaResourceId, ResolvedMediaResource>{
              id: testResource(
                id: id,
                kind: MediaResourceKind.video,
                fileUri: file.uri,
              ),
            },
          );
          stores.add(store);
          futures.add(
            DefaultMediaPosterService(
              store: store,
              generator: generator,
              deadline: const Duration(milliseconds: 20),
            ).generate(id),
          );
        }

        final results = await Future.wait(futures);

        expect(
          results.map(
            (result) =>
                (result as MediaResourceError<MediaPoster>).failure.code,
          ),
          everyElement(MediaResourceFailureCode.cancelled),
        );
        expect(generator.calls, 2);
        expect(generator.maximumActive, 2);
        expect(
          stores.map((store) => store.releaseCalls),
          orderedEquals(<int>[0, 0, 1]),
        );
        generator.completeAll();
        await _waitFor(() => stores.every((store) => store.releaseCalls == 1));
      },
    );

    test(
      'queued cancellation avoids provider invocation and releases lease',
      () async {
        final generator = _ControlledPosterGenerator(_metadataFreeJpeg());
        final blockerFutures = <Future<MediaResourceResult<MediaPoster>>>[];
        for (var index = 5; index <= 6; index += 1) {
          final id = testResourceId('$index');
          final file = await File(
            '${sandbox.path}/$index.mp4',
          ).writeAsBytes(<int>[1]);
          final store = FakeMediaResourceStore(
            <MediaResourceId, ResolvedMediaResource>{
              id: testResource(
                id: id,
                kind: MediaResourceKind.video,
                fileUri: file.uri,
              ),
            },
          );
          blockerFutures.add(
            DefaultMediaPosterService(
              store: store,
              generator: generator,
            ).generate(id),
          );
        }
        await _waitFor(() => generator.calls == 2);
        final queuedId = testResourceId('7');
        final queuedFile = await File(
          '${sandbox.path}/7.mp4',
        ).writeAsBytes(<int>[1]);
        final queuedStore =
            FakeMediaResourceStore(<MediaResourceId, ResolvedMediaResource>{
              queuedId: testResource(
                id: queuedId,
                kind: MediaResourceKind.video,
                fileUri: queuedFile.uri,
              ),
            });
        final cancellation = MediaPreviewCancellation();
        final queued = DefaultMediaPosterService(
          store: queuedStore,
          generator: generator,
        ).generate(queuedId, cancellation: cancellation);

        await _waitFor(() => queuedStore.retainCalls == 1);
        cancellation.cancel();
        final result = await queued;

        expect(
          (result as MediaResourceError<MediaPoster>).failure.code,
          MediaResourceFailureCode.cancelled,
        );
        expect(generator.calls, 2);
        expect(queuedStore.releaseCalls, 1);
        generator.completeAll();
        await Future.wait(blockerFutures);
      },
    );

    test('bounds outstanding jobs before retaining more resources', () async {
      final id = testResourceId('50');
      final file = await File(
        '${sandbox.path}/bounded-queue.mp4',
      ).writeAsBytes(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final generator = _ControlledPosterGenerator(_metadataFreeJpeg());
      final service = DefaultMediaPosterService(
        store: store,
        generator: generator,
      );
      final cancellations = List<MediaPreviewCancellation>.generate(
        DefaultMediaPosterService.maximumOutstandingJobs,
        (_) => MediaPreviewCancellation(),
      );
      final futures = <Future<MediaResourceResult<MediaPoster>>>[
        for (final cancellation in cancellations)
          service.generate(id, cancellation: cancellation),
      ];
      await _waitFor(() => generator.calls == 2);

      final overflow = await service.generate(id);

      expect(
        (overflow as MediaResourceError<MediaPoster>).failure.code,
        MediaResourceFailureCode.overloaded,
      );
      expect(
        store.retainCalls,
        DefaultMediaPosterService.maximumOutstandingJobs,
      );

      cancellations[2].cancel();
      await futures[2];
      await _waitFor(() => store.releaseCalls == 1);
      final replacementCancellation = MediaPreviewCancellation();
      final replacement = service.generate(
        id,
        cancellation: replacementCancellation,
      );
      await _waitFor(
        () =>
            store.retainCalls ==
            DefaultMediaPosterService.maximumOutstandingJobs + 1,
      );

      for (final cancellation in cancellations) {
        cancellation.cancel();
      }
      replacementCancellation.cancel();
      generator.completeAll();
      await Future.wait(<Future<MediaResourceResult<MediaPoster>>>[
        ...futures,
        replacement,
      ]);
      await _waitFor(
        () =>
            store.releaseCalls ==
            DefaultMediaPosterService.maximumOutstandingJobs + 1,
      );
      expect(generator.calls, 2);
    });

    test(
      'synchronous provider failures do not consume scheduler slots',
      () async {
        final stores = <FakeMediaResourceStore>[];
        final futures = <Future<MediaResourceResult<MediaPoster>>>[];
        for (var index = 30; index <= 32; index += 1) {
          final id = testResourceId('$index');
          final file = await File(
            '${sandbox.path}/sync-failure-$index.mp4',
          ).writeAsBytes(<int>[1]);
          final store = FakeMediaResourceStore(
            <MediaResourceId, ResolvedMediaResource>{
              id: testResource(
                id: id,
                kind: MediaResourceKind.video,
                fileUri: file.uri,
              ),
            },
          );
          stores.add(store);
          futures.add(
            DefaultMediaPosterService(
              store: store,
              generator: index < 32
                  ? const _SynchronousThrowPosterGenerator()
                  : _ImmediatePosterGenerator(_metadataFreeJpeg()),
            ).generate(id),
          );
        }

        final results = await Future.wait(futures);

        expect(
          results
              .take(2)
              .map(
                (result) =>
                    (result as MediaResourceError<MediaPoster>).failure.code,
              ),
          everyElement(MediaResourceFailureCode.decodeFailed),
        );
        expect(results.last, isA<MediaResourceSuccess<MediaPoster>>());
        expect(stores.map((store) => store.releaseCalls), everyElement(1));
      },
    );

    test('rejects undecodable provider output and clears its bytes', () async {
      final id = testResourceId('8');
      final file = await File(
        '${sandbox.path}/unsafe.mp4',
      ).writeAsBytes(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final unsafe = Uint8List.fromList(<int>[
        0xff,
        0xd8,
        0xff,
        0xe1,
        0x00,
        0x04,
        1,
        2,
        0xff,
        0xd9,
      ]);
      final service = DefaultMediaPosterService(
        store: store,
        generator: _ImmediatePosterGenerator(unsafe),
      );

      final result = await service.generate(id);

      expect(
        (result as MediaResourceError<MediaPoster>).failure.code,
        MediaResourceFailureCode.decodeFailed,
      );
      expect(unsafe, everyElement(0));
      expect(store.releaseCalls, 1);
    });

    test(
      're-encodes provider bytes and drops trailing sensitive data',
      () async {
        final id = testResourceId('9');
        final file = await File(
          '${sandbox.path}/trailing.mp4',
        ).writeAsBytes(<int>[1]);
        final store = FakeMediaResourceStore(
          <MediaResourceId, ResolvedMediaResource>{
            id: testResource(
              id: id,
              kind: MediaResourceKind.video,
              fileUri: file.uri,
            ),
          },
        );
        final providerBytes = Uint8List.fromList(<int>[
          ..._metadataFreeJpeg(),
          ...utf8.encode('/private/user-sensitive-name.jpg'),
        ]);
        final service = DefaultMediaPosterService(
          store: store,
          generator: _ImmediatePosterGenerator(providerBytes),
        );

        final result = await service.generate(id);

        final poster = (result as MediaResourceSuccess<MediaPoster>).value;
        expect(poster.contentType, 'image/png');
        expect(
          utf8.decode(poster.bytes, allowMalformed: true),
          isNot(contains('/private/')),
        );
        expect(providerBytes, everyElement(0));
        expect(store.releaseCalls, 1);
      },
    );
  });
}

final class _ControlledPosterGenerator implements MediaPosterGenerator {
  _ControlledPosterGenerator(this.bytes);

  final Uint8List bytes;
  final List<Completer<Uint8List?>> _pending = <Completer<Uint8List?>>[];
  int calls = 0;
  int active = 0;
  int maximumActive = 0;

  @override
  Future<Uint8List?> generateJpeg(
    Uri fileUri, {
    required int maximumDimension,
    required int quality,
  }) async {
    calls += 1;
    active += 1;
    maximumActive = active > maximumActive ? active : maximumActive;
    final completer = Completer<Uint8List?>();
    _pending.add(completer);
    try {
      final result = await completer.future;
      return result == null ? null : Uint8List.fromList(result);
    } finally {
      active -= 1;
    }
  }

  void completeNext() {
    final next = _pending.firstWhere((item) => !item.isCompleted);
    next.complete(bytes);
  }

  void completeAll() {
    for (final pending in _pending) {
      if (!pending.isCompleted) {
        pending.complete(bytes);
      }
    }
  }
}

final class _ImmediatePosterGenerator implements MediaPosterGenerator {
  const _ImmediatePosterGenerator(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List?> generateJpeg(
    Uri fileUri, {
    required int maximumDimension,
    required int quality,
  }) async => bytes;
}

final class _SynchronousThrowPosterGenerator implements MediaPosterGenerator {
  const _SynchronousThrowPosterGenerator();

  @override
  Future<Uint8List?> generateJpeg(
    Uri fileUri, {
    required int maximumDimension,
    required int quality,
  }) {
    throw const FormatException();
  }
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Timed out waiting for test condition');
}

Uint8List _metadataFreeJpeg() => base64Decode(_onePixelJpegBase64);

Uint8List _metadataFreePng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

Uint8List _metadataBearingPng() {
  return _pngWithChunk('tEXt', utf8.encode('sensitive=path'));
}

Uint8List _pngWithChunk(String type, List<int> data) {
  final png = _metadataFreePng();
  final endOffset = png.length - 12;
  return Uint8List.fromList(<int>[
    ...png.sublist(0, endOffset),
    ..._pngChunk(type, data),
    ...png.sublist(endOffset),
  ]);
}

Uint8List _pngChunk(String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final result = Uint8List(12 + data.length);
  final view = ByteData.sublistView(result);
  view.setUint32(0, data.length);
  result.setRange(4, 8, typeBytes);
  result.setRange(8, 8 + data.length, data);
  view.setUint32(8 + data.length, _crc32(<int>[...typeBytes, ...data]));
  return result;
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

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
