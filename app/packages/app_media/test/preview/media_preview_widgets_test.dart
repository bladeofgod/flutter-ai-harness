import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:app_media/app_media.dart';
import 'package:app_media/src/preview/active_media_player_coordinator.dart';
import 'package:app_media/src/preview/media_playback_driver.dart';
import 'package:app_media/src/preview/media_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'media_preview_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUp(() async {
    imageCache.clear();
    imageCache.clearLiveImages();
    sandbox = await Directory.systemTemp.createTemp('media-preview-widget-');
  });

  tearDown(() async {
    await ActiveMediaPlayerCoordinator.resetForTesting();
    imageCache.clear();
    imageCache.clearLiveImages();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('MediaResourceThumbnail', () {
    testWidgets('shows canonical image with stable dimensions and lease', (
      tester,
    ) async {
      final id = testResourceId('1');
      final file = File('${sandbox.path}/photo.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 96,
            height: 72,
            imageInspector: FakeMediaPreviewImageInspector(),
          ),
        ),
      );
      await _pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);

      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.getSize(find.byType(MediaResourceThumbnail)),
        const Size(96, 72),
      );
      expect(store.retainCalls, 1);
      expect(store.releaseCalls, 0);
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final cacheKey = await provider.obtainKey(const ImageConfiguration());

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      expect(store.releaseCalls, 1);
      final cacheStatus = imageCache.statusForKey(cacheKey);
      expect(cacheStatus.pending, isFalse);
      expect(cacheStatus.keepAlive, isFalse);
      expect(cacheStatus.live, isFalse);
    });

    testWidgets('uses bounded poster for video without creating a player', (
      tester,
    ) async {
      final id = testResourceId('2');
      final file = File('${sandbox.path}/clip.mp4')..writeAsBytesSync(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final poster = MediaPoster.png(
        bytes: _onePixelPng(),
        width: 1,
        height: 1,
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 120,
            height: 80,
            poster: poster,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
      expect(find.bySemanticsLabel('Play video'), findsOneWidget);
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final cacheKey = await provider.obtainKey(const ImageConfiguration());
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      final cacheStatus = imageCache.statusForKey(cacheKey);
      expect(cacheStatus.pending, isFalse);
      expect(cacheStatus.keepAlive, isFalse);
      expect(cacheStatus.live, isFalse);
    });

    testWidgets('late resolve after unmount only releases the retained lease', (
      tester,
    ) async {
      final id = testResourceId('3');
      final file = File('${sandbox.path}/late.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );
      final gate = Completer<void>();
      store.resolveGate = gate;

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
          ),
        ),
      );
      await _pumpUntil(tester, () => store.resolveCalls == 1);
      await tester.pumpWidget(_app(const SizedBox()));
      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(store.releaseCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing media has an explicit accessible error', (
      tester,
    ) async {
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{},
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: testResourceId('4'),
            store: store,
            width: 80,
            height: 80,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('rejects oversized decoded dimensions before image decode', (
      tester,
    ) async {
      final id = testResourceId('17');
      final file = File('${sandbox.path}/oversized-thumbnail.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );
      final inspector = FakeMediaPreviewImageInspector(
        descriptor: const MediaPreviewImageDescriptor(
          width: 8192,
          height: 8192,
        ),
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
            imageInspector: inspector,
          ),
        ),
      );
      await _pumpUntil(tester, () => store.releaseCalls == 1);
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
      expect(store.releaseAttempts, 1);
    });

    testWidgets('updates bounded decode target for size and DPR changes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = testResourceId('20');
      final file = File('${sandbox.path}/responsive-thumbnail.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );
      final inspector = FakeMediaPreviewImageInspector(
        descriptor: const MediaPreviewImageDescriptor(
          width: 2000,
          height: 1000,
        ),
      );

      Widget thumbnail(double width, double height) {
        return _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: width,
            height: height,
            imageInspector: inspector,
          ),
        );
      }

      await tester.pumpWidget(thumbnail(50, 50));
      await _pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(_resizeImage(tester).width, 100);
      expect(_resizeImage(tester).height, 50);

      await tester.pumpWidget(thumbnail(200, 50));
      await tester.pump();
      expect(_resizeImage(tester).width, 200);
      expect(_resizeImage(tester).height, 100);

      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(_resizeImage(tester).width, 400);
      expect(_resizeImage(tester).height, 200);
      expect(store.retainCalls, 1);
      expect(store.releaseCalls, 0);
    });

    testWidgets('late image inspection after unmount only releases its lease', (
      tester,
    ) async {
      final id = testResourceId('18');
      final file = File('${sandbox.path}/late-inspection.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );
      final gate = Completer<void>();
      final inspector = FakeMediaPreviewImageInspector(gate: gate);

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
            imageInspector: inspector,
          ),
        ),
      );
      await _pumpUntil(tester, () => inspector.inspectCalls == 1);
      await tester.pumpWidget(_app(const SizedBox()));
      gate.complete();
      await _pumpUntil(tester, () => store.releaseCalls == 1);

      expect(store.releaseAttempts, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('image decode failure releases the retained resource', (
      tester,
    ) async {
      final id = testResourceId('f');
      final file = File('${sandbox.path}/missing-thumbnail.png');
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
            imageInspector: FakeMediaPreviewImageInspector(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await _pumpUntil(tester, () => store.releaseCalls == 1);
      await tester.pump();

      expect(store.releaseCalls, 1);
      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('poster decode failure releases the retained resource', (
      tester,
    ) async {
      final id = testResourceId('10');
      final file = File('${sandbox.path}/invalid-poster.mp4')
        ..writeAsBytesSync(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final poster = MediaPoster.png(
        bytes: _undecodablePng(),
        width: 1,
        height: 1,
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
            poster: poster,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await _pumpUntil(tester, () => store.releaseCalls == 1);
      await tester.pump();

      expect(store.releaseCalls, 1);
      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('a replacement poster recovers the same video resource', (
      tester,
    ) async {
      final id = testResourceId('14');
      final file = File('${sandbox.path}/replacement-poster.mp4')
        ..writeAsBytesSync(<int>[1]);
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.video,
            fileUri: file.uri,
          ),
        },
      );
      final invalidPoster = MediaPoster.png(
        bytes: _undecodablePng(),
        width: 1,
        height: 1,
      );

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
            poster: invalidPoster,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await _pumpUntil(tester, () => store.releaseCalls == 1);

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: id,
            store: store,
            width: 80,
            height: 80,
            poster: MediaPoster.png(bytes: _onePixelPng(), width: 1, height: 1),
          ),
        ),
      );
      await _pumpUntil(tester, () => store.retainCalls == 2);
      await _pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);

      expect(find.byType(Image), findsOneWidget);
      expect(find.bySemanticsLabel('Media preview unavailable'), findsNothing);
    });

    testWidgets('store replacement releases each lease through its owner', (
      tester,
    ) async {
      final firstId = testResourceId('b');
      final secondId = testResourceId('c');
      final firstFile = File('${sandbox.path}/first.png')
        ..writeAsBytesSync(_onePixelPng());
      final secondFile = File('${sandbox.path}/second.png')
        ..writeAsBytesSync(_onePixelPng());
      final firstStore =
          FakeMediaResourceStore(<MediaResourceId, ResolvedMediaResource>{
            firstId: testResource(
              id: firstId,
              kind: MediaResourceKind.image,
              fileUri: firstFile.uri,
            ),
          });
      final secondStore =
          FakeMediaResourceStore(<MediaResourceId, ResolvedMediaResource>{
            secondId: testResource(
              id: secondId,
              kind: MediaResourceKind.image,
              fileUri: secondFile.uri,
            ),
          });

      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: firstId,
            store: firstStore,
            width: 80,
            height: 80,
            imageInspector: FakeMediaPreviewImageInspector(),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            firstStore.retainCalls == 1 &&
            find.byType(Image).evaluate().isNotEmpty,
      );
      await tester.pumpWidget(
        _app(
          MediaResourceThumbnail(
            resourceId: secondId,
            store: secondStore,
            width: 80,
            height: 80,
            imageInspector: FakeMediaPreviewImageInspector(),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            firstStore.releaseCalls == 1 &&
            secondStore.retainCalls == 1 &&
            find.byType(Image).evaluate().isNotEmpty,
      );

      expect(firstStore.releaseCalls, 1);
      expect(secondStore.retainCalls, 1);
      await tester.pumpWidget(_app(const SizedBox()));
      await _pumpUntil(tester, () => secondStore.releaseCalls == 1);
      expect(secondStore.releaseCalls, 1);
    });
  });

  group('MediaPreviewPage image', () {
    testWidgets('real inspector reads canonical dimensions without decoding', (
      tester,
    ) async {
      final file = File('${sandbox.path}/inspected.png')
        ..writeAsBytesSync(_onePixelPng());

      final descriptor = await tester.runAsync(
        () => const FlutterMediaPreviewImageInspector().inspect(file.uri),
      );

      expect(descriptor?.width, 1);
      expect(descriptor?.height, 1);
    });

    testWidgets('uses InteractiveViewer with bounded zoom and releases once', (
      tester,
    ) async {
      final id = testResourceId('5');
      final file = File('${sandbox.path}/viewer.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          MediaPreviewPage(
            resourceId: id,
            store: store,
            imageInspector: FakeMediaPreviewImageInspector(),
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(InteractiveViewer).evaluate().isNotEmpty,
      );

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 1);
      expect(viewer.maxScale, 4);
      expect(viewer.panEnabled, isTrue);
      expect(find.byTooltip('Close preview'), findsOneWidget);
      final provider = tester.widget<Image>(find.byType(Image)).image;
      final cacheKey = await provider.obtainKey(const ImageConfiguration());

      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
      expect(store.releaseCalls, 1);
      final cacheStatus = imageCache.statusForKey(cacheKey);
      expect(cacheStatus.pending, isFalse);
      expect(cacheStatus.keepAlive, isFalse);
      expect(cacheStatus.live, isFalse);
    });

    testWidgets('updates viewer decode target after rotation and DPR changes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = testResourceId('21');
      final file = File('${sandbox.path}/responsive-viewer.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          MediaPreviewPage(
            resourceId: id,
            store: store,
            imageInspector: FakeMediaPreviewImageInspector(
              descriptor: const MediaPreviewImageDescriptor(
                width: 4000,
                height: 2000,
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(_resizeImage(tester).width, 1600);
      expect(_resizeImage(tester).height, 800);

      tester.view.physicalSize = const Size(800, 400);
      await tester.pump();
      expect(_resizeImage(tester).width, 3200);
      expect(_resizeImage(tester).height, 1600);

      tester.view.physicalSize = const Size(1600, 800);
      tester.view.devicePixelRatio = 2;
      await tester.pump();
      expect(_resizeImage(tester).width, 4000);
      expect(_resizeImage(tester).height, 2000);
      expect(store.retainCalls, 1);
      expect(store.releaseCalls, 0);
    });

    testWidgets('decode failure unloads the image lease', (tester) async {
      final id = testResourceId('11');
      final file = File('${sandbox.path}/missing-viewer.png');
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          MediaPreviewPage(
            resourceId: id,
            store: store,
            imageInspector: FakeMediaPreviewImageInspector(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await _pumpUntil(tester, () => store.releaseCalls == 1);
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(store.releaseCalls, 1);
      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('viewer rejects oversized source dimensions before decode', (
      tester,
    ) async {
      final id = testResourceId('19');
      final file = File('${sandbox.path}/oversized-viewer.png')
        ..writeAsBytesSync(_onePixelPng());
      final store = FakeMediaResourceStore(
        <MediaResourceId, ResolvedMediaResource>{
          id: testResource(
            id: id,
            kind: MediaResourceKind.image,
            fileUri: file.uri,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          MediaPreviewPage(
            resourceId: id,
            store: store,
            imageInspector: FakeMediaPreviewImageInspector(
              descriptor: const MediaPreviewImageDescriptor(
                width: 8192,
                height: 8192,
              ),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => store.releaseCalls == 1);
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
      expect(store.releaseAttempts, 1);
    });
  });

  group('MediaPreviewPage video', () {
    testWidgets('starts paused and supports play pause seek and replay', (
      tester,
    ) async {
      final fixture = _videoFixture(sandbox, '6');
      final driver = FakeMediaPlaybackDriver();
      final factory = FakeMediaPlaybackDriverFactory(() => driver);

      await tester.pumpWidget(
        _app(
          mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: fixture.id,
            store: fixture.store,
            driverFactory: factory,
          ),
        ),
      );
      await _pumpUntil(tester, () => driver.initializeCalls == 1);
      await tester.pump();

      expect(find.byKey(const Key('fake-video-surface')), findsOneWidget);
      expect(driver.pauseCalls, 1);
      expect(driver.playCalls, 0);
      await tester.tap(find.byTooltip('Play video').first);
      await tester.pump();
      expect(driver.playCalls, 1);
      await tester.tap(find.byTooltip('Pause video').first);
      await tester.pump();
      expect(driver.pauseCalls, 2);

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged?.call(30000);
      await tester.pump();
      expect(driver.seekCalls, 1);

      driver.snapshot = const MediaPlaybackSnapshot(
        isInitialized: true,
        isPlaying: false,
        isCompleted: true,
        position: Duration(minutes: 2),
        duration: Duration(minutes: 2),
        aspectRatio: 16 / 9,
        hasError: false,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Replay video').first);
      await tester.pump();
      expect(driver.seekCalls, 2);
      expect(driver.playCalls, 2);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
    });

    testWidgets('pauses on lifecycle loss and does not auto resume', (
      tester,
    ) async {
      final fixture = _videoFixture(sandbox, '7');
      final driver = FakeMediaPlaybackDriver();

      await tester.pumpWidget(
        _app(
          mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: fixture.id,
            store: fixture.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
          ),
        ),
      );
      await _pumpUntil(tester, () => driver.initializeCalls == 1);
      await tester.pump();
      await tester.tap(find.byTooltip('Play video').first);
      await tester.pump();
      final pausesBeforeBackground = driver.pauseCalls;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(driver.pauseCalls, pausesBeforeBackground + 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(driver.playCalls, 1);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
    });

    testWidgets('pauses when another route covers the default viewer', (
      tester,
    ) async {
      final fixture = _videoFixture(sandbox, 'd');
      final driver = FakeMediaPlaybackDriver();
      await tester.pumpWidget(
        MaterialApp(
          home: mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: fixture.id,
            store: fixture.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
          ),
        ),
      );
      await _pumpUntil(tester, () => driver.initializeCalls == 1);
      await tester.pump();
      await tester.tap(find.byTooltip('Play video').first);
      await tester.pump();
      final pausesBeforeCover = driver.pauseCalls;

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(builder: (_) => const SizedBox()),
        ),
      );
      await tester.pump();

      expect(driver.pauseCalls, pausesBeforeCover + 1);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
    });

    testWidgets('runtime playback failure unloads player and lease', (
      tester,
    ) async {
      final fixture = _videoFixture(sandbox, 'e');
      final driver = FakeMediaPlaybackDriver(
        disposeError: const FormatException(),
      );
      await tester.pumpWidget(
        _app(
          mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: fixture.id,
            store: fixture.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
          ),
        ),
      );
      await _pumpUntil(tester, () => driver.initializeCalls == 1);
      await tester.pump();

      driver.snapshot = const MediaPlaybackSnapshot(
        isInitialized: true,
        isPlaying: false,
        isCompleted: false,
        position: Duration.zero,
        duration: Duration(minutes: 2),
        aspectRatio: 16 / 9,
        hasError: true,
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.bySemanticsLabel('Media preview unavailable'),
        findsOneWidget,
      );
      expect(driver.disposeCalls, 1);
      expect(fixture.store.releaseCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'late initialization after dispose cleans driver and lease once',
      (tester) async {
        final fixture = _videoFixture(sandbox, '8');
        final gate = Completer<void>();
        final driver = FakeMediaPlaybackDriver(
          initializeGate: gate,
          disposeError: const FormatException(),
        );

        await tester.pumpWidget(
          _app(
            mediaPreviewPageWithDriverFactoryForTesting(
              resourceId: fixture.id,
              store: fixture.store,
              driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
            ),
          ),
        );
        await _pumpUntil(tester, () => driver.initializeCalls == 1);
        await tester.pumpWidget(_app(const SizedBox()));
        gate.complete();
        await tester.pump();
        await tester.pump();

        expect(driver.disposeCalls, 1);
        expect(fixture.store.releaseCalls, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('new viewer waits for previous player disposal', (
      tester,
    ) async {
      final first = _videoFixture(sandbox, '15');
      final second = _videoFixture(sandbox, '16');
      final disposeGate = Completer<void>();
      final firstDriver = FakeMediaPlaybackDriver(disposeGate: disposeGate);
      final secondDriver = FakeMediaPlaybackDriver();
      await tester.pumpWidget(
        MaterialApp(
          home: mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: first.id,
            store: first.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => firstDriver),
          ),
        ),
      );
      await _pumpUntil(tester, () => firstDriver.initializeCalls == 1);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => mediaPreviewPageWithDriverFactoryForTesting(
              resourceId: second.id,
              store: second.store,
              driverFactory: FakeMediaPlaybackDriverFactory(() => secondDriver),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => firstDriver.disposeCalls == 1);

      expect(secondDriver.initializeCalls, 0);
      expect(first.store.releaseCalls, 0);

      disposeGate.complete();
      await _pumpUntil(tester, () => secondDriver.initializeCalls == 1);
      expect(first.store.releaseCalls, 1);
      expect(secondDriver.disposeCalls, 0);
    });

    testWidgets('a new viewer disposes the previous global player', (
      tester,
    ) async {
      final first = _videoFixture(sandbox, '9');
      final second = _videoFixture(sandbox, 'a');
      final firstDriver = FakeMediaPlaybackDriver();
      final secondDriver = FakeMediaPlaybackDriver();

      await tester.pumpWidget(
        _app(
          mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: first.id,
            store: first.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => firstDriver),
          ),
        ),
      );
      await _pumpUntil(tester, () => firstDriver.initializeCalls == 1);
      await tester.pumpWidget(
        _app(
          mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: second.id,
            store: second.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => secondDriver),
          ),
        ),
      );
      await _pumpUntil(tester, () => secondDriver.initializeCalls == 1);

      expect(firstDriver.disposeCalls, 1);
      expect(secondDriver.disposeCalls, 0);
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();
    });

    testWidgets('stacked viewer revokes a late initializing previous owner', (
      tester,
    ) async {
      final first = _videoFixture(sandbox, '12');
      final second = _videoFixture(sandbox, '13');
      final firstGate = Completer<void>();
      final firstDriver = FakeMediaPlaybackDriver(initializeGate: firstGate);
      final secondDriver = FakeMediaPlaybackDriver();
      await tester.pumpWidget(
        MaterialApp(
          home: mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: first.id,
            store: first.store,
            driverFactory: FakeMediaPlaybackDriverFactory(() => firstDriver),
          ),
        ),
      );
      await _pumpUntil(tester, () => firstDriver.initializeCalls == 1);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => mediaPreviewPageWithDriverFactoryForTesting(
              resourceId: second.id,
              store: second.store,
              driverFactory: FakeMediaPlaybackDriverFactory(() => secondDriver),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => secondDriver.initializeCalls == 1);
      firstGate.complete();
      await tester.pump();
      await tester.pump();

      expect(firstDriver.disposeCalls, 1);
      expect(first.store.releaseCalls, 1);
      expect(first.store.releaseAttempts, 1);
      expect(secondDriver.disposeCalls, 0);
      expect(find.byKey(const Key('fake-video-surface')), findsOneWidget);
    });

    testWidgets('restores the previous viewer after a stacked viewer pops', (
      tester,
    ) async {
      final first = _videoFixture(sandbox, '14');
      final second = _videoFixture(sandbox, '15');
      final firstDriver = FakeMediaPlaybackDriver();
      final restoredDriver = FakeMediaPlaybackDriver();
      final secondDriver = FakeMediaPlaybackDriver();
      var firstCreation = 0;
      final firstFactory = FakeMediaPlaybackDriverFactory(
        () => firstCreation++ == 0 ? firstDriver : restoredDriver,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: mediaPreviewPageWithDriverFactoryForTesting(
            resourceId: first.id,
            store: first.store,
            driverFactory: firstFactory,
          ),
        ),
      );
      await _pumpUntil(tester, () => firstDriver.initializeCalls == 1);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => mediaPreviewPageWithDriverFactoryForTesting(
              resourceId: second.id,
              store: second.store,
              driverFactory: FakeMediaPlaybackDriverFactory(() => secondDriver),
            ),
          ),
        ),
      );
      await _pumpUntil(tester, () => secondDriver.initializeCalls == 1);
      expect(firstDriver.disposeCalls, 1);
      expect(first.store.releaseCalls, 1);

      navigator.pop();
      await _pumpUntil(tester, () => restoredDriver.initializeCalls == 1);
      await tester.pumpAndSettle();

      expect(firstFactory.drivers, <FakeMediaPlaybackDriver>[
        firstDriver,
        restoredDriver,
      ]);
      expect(secondDriver.disposeCalls, 1);
      expect(second.store.releaseCalls, 1);
      expect(first.store.retainCalls, 2);
      expect(first.store.releaseCalls, 1);
      expect(find.byKey(const Key('fake-video-surface')), findsOneWidget);
    });

    testWidgets('fits compact portrait landscape safe areas and large text', (
      tester,
    ) async {
      final sizes = <Size>[
        const Size(320, 568),
        const Size(375, 812),
        const Size(812, 375),
      ];
      for (var index = 0; index < sizes.length; index += 1) {
        tester.view.physicalSize = sizes[index];
        tester.view.devicePixelRatio = 1;
        final fixture = _videoFixture(sandbox, '${index + 11}');
        final driver = FakeMediaPlaybackDriver();
        await tester.pumpWidget(
          _app(
            mediaPreviewPageWithDriverFactoryForTesting(
              resourceId: fixture.id,
              store: fixture.store,
              driverFactory: FakeMediaPlaybackDriverFactory(() => driver),
            ),
            textScale: 1.3,
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 20),
          ),
        );
        await _pumpUntil(tester, () => driver.initializeCalls == 1);
        driver.snapshot = const MediaPlaybackSnapshot(
          isInitialized: true,
          isPlaying: false,
          isCompleted: false,
          position: Duration(hours: 12, minutes: 34, seconds: 56),
          duration: Duration(hours: 23, minutes: 59, seconds: 59),
          aspectRatio: 16 / 9,
          hasError: false,
        );
        await tester.pump();

        expect(find.text('12:34:56'), findsOneWidget);
        expect(find.text('23:59:59'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout must fit ${sizes[index]} at 1.3x text',
        );
        await tester.pumpWidget(_app(const SizedBox()));
        await tester.pump();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}

Widget _app(
  Widget child, {
  double textScale = 1,
  EdgeInsets padding = EdgeInsets.zero,
}) {
  return MaterialApp(
    builder: (context, appChild) {
      return MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale), padding: padding),
        child: appChild ?? const SizedBox(),
      );
    },
    home: Center(child: child),
  );
}

({MediaResourceId id, FakeMediaResourceStore store}) _videoFixture(
  Directory sandbox,
  String suffix,
) {
  final id = testResourceId(suffix);
  final file = File('${sandbox.path}/$suffix.mp4')..writeAsBytesSync(<int>[1]);
  return (
    id: id,
    store: FakeMediaResourceStore(<MediaResourceId, ResolvedMediaResource>{
      id: testResource(
        id: id,
        kind: MediaResourceKind.video,
        fileUri: file.uri,
      ),
    }),
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 2));
  }
  fail('Timed out waiting for widget state');
}

ResizeImage _resizeImage(WidgetTester tester) {
  return tester.widget<Image>(find.byType(Image)).image as ResizeImage;
}

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);

Uint8List _undecodablePng() {
  final bytes = _onePixelPng();
  final view = ByteData.sublistView(bytes);
  bytes[25] = 7;
  view.setUint32(29, _crc32(bytes.sublist(12, 29)));
  return bytes;
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
