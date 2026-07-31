import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../resource/media_resource_models.dart';
import '../resource/media_resource_store.dart';
import 'active_media_player_coordinator.dart';
import 'media_playback_driver.dart';
import 'media_preview_image_policy.dart';
import 'video_player_media_playback_driver.dart';

final class MediaPreviewPage extends StatefulWidget {
  const MediaPreviewPage({
    required this.resourceId,
    required this.store,
    this.onClose,
    this.routeObserver,
    this.imageInspector = const FlutterMediaPreviewImageInspector(),
    super.key,
  }) : _driverFactory = const VideoPlayerMediaPlaybackDriverFactory();

  const MediaPreviewPage._withDriverFactory({
    required this.resourceId,
    required this.store,
    required MediaPlaybackDriverFactory driverFactory,
    this.onClose,
    this.routeObserver,
    this.imageInspector = const FlutterMediaPreviewImageInspector(),
    super.key,
  }) : _driverFactory = driverFactory;

  final MediaResourceId resourceId;
  final MediaResourceStore store;
  final MediaPlaybackDriverFactory _driverFactory;
  final VoidCallback? onClose;
  final RouteObserver<ModalRoute<Object?>>? routeObserver;
  final MediaPreviewImageInspector imageInspector;

  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

MediaPreviewPage mediaPreviewPageWithDriverFactoryForTesting({
  required MediaResourceId resourceId,
  required MediaResourceStore store,
  required MediaPlaybackDriverFactory driverFactory,
  VoidCallback? onClose,
  RouteObserver<ModalRoute<Object?>>? routeObserver,
  MediaPreviewImageInspector imageInspector =
      const FlutterMediaPreviewImageInspector(),
  Key? key,
}) {
  return MediaPreviewPage._withDriverFactory(
    resourceId: resourceId,
    store: store,
    driverFactory: driverFactory,
    onClose: onClose,
    routeObserver: routeObserver,
    imageInspector: imageInspector,
    key: key,
  );
}

final class _MediaPreviewPageState extends State<MediaPreviewPage>
    with WidgetsBindingObserver, RouteAware {
  MediaResourceLease? _lease;
  MediaResourceStore? _leaseStore;
  ResolvedMediaResource? _resource;
  MediaPreviewImageDescriptor? _imageDescriptor;
  ImageProvider<Object>? _imageProvider;
  (Size, double)? _imageDecodeConfiguration;
  MediaPlaybackDriver? _driver;
  ActiveMediaPlayerLease? _playerLease;
  MediaResourceFailureCode? _failure;
  ModalRoute<Object?>? _route;
  bool? _routeWasCurrent;
  Future<void>? _routeRestore;
  int _generation = 0;
  bool _handlingPlaybackFailure = false;
  bool _decodeFailureScheduled = false;
  final Map<MediaResourceLease, Future<void>> _leaseReleases =
      HashMap<MediaResourceLease, Future<void>>.identity();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of<Object?>(context);
    if (!identical(_route, nextRoute)) {
      final oldRoute = _route;
      if (oldRoute != null) {
        widget.routeObserver?.unsubscribe(this);
      }
      _route = nextRoute;
      if (nextRoute != null) {
        widget.routeObserver?.subscribe(this, nextRoute);
      }
    }
    _refreshImageProviderForMediaQuery();
    final isCurrent = nextRoute?.isCurrent ?? true;
    final wasCurrent = _routeWasCurrent;
    _routeWasCurrent = isCurrent;
    if (!isCurrent) {
      unawaited(_pause());
    } else if (wasCurrent == false) {
      _restoreAfterRouteCover();
    }
  }

  @override
  void didUpdateWidget(MediaPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeObserver != widget.routeObserver) {
      oldWidget.routeObserver?.unsubscribe(this);
      final route = _route;
      if (route != null) {
        widget.routeObserver?.subscribe(this, route);
      }
    }
    if (oldWidget.resourceId != widget.resourceId ||
        !identical(oldWidget.store, widget.store) ||
        !identical(oldWidget._driverFactory, widget._driverFactory) ||
        !identical(oldWidget.imageInspector, widget.imageInspector)) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final targetStore = widget.store;
    final targetResourceId = widget.resourceId;
    final targetDriverFactory = widget._driverFactory;
    final targetImageInspector = widget.imageInspector;
    await _releaseOwnedState();
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _resource = null;
      _failure = null;
      _decodeFailureScheduled = false;
    });
    final retained = await targetStore.retain(targetResourceId);
    if (retained case MediaResourceError<MediaResourceLease>(:final failure)) {
      _publishFailure(generation, failure.code);
      return;
    }
    final lease = (retained as MediaResourceSuccess<MediaResourceLease>).value;
    if (!mounted || generation != _generation) {
      await _releaseLeaseOnce(targetStore, lease);
      return;
    }
    final resolvedResult = await targetStore.resolve(targetResourceId, lease);
    if (!mounted || generation != _generation) {
      await _releaseLeaseOnce(targetStore, lease);
      return;
    }
    if (resolvedResult case MediaResourceError<ResolvedMediaResource>(
      :final failure,
    )) {
      await _releaseLeaseOnce(targetStore, lease);
      _publishFailure(generation, failure.code);
      return;
    }
    final resolved =
        (resolvedResult as MediaResourceSuccess<ResolvedMediaResource>).value;
    if (resolved.kind == MediaResourceKind.image) {
      final descriptor = await targetImageInspector.inspect(resolved.fileUri);
      if (!mounted || generation != _generation) {
        await _releaseLeaseOnce(targetStore, lease);
        return;
      }
      if (descriptor == null ||
          !MediaPreviewImagePolicy.acceptsSource(descriptor)) {
        await _releaseLeaseOnce(targetStore, lease);
        _publishFailure(generation, MediaResourceFailureCode.decodeFailed);
        return;
      }
      _lease = lease;
      _leaseStore = targetStore;
      _resource = resolved;
      _imageDescriptor = descriptor;
      _imageProvider = _createViewerImageProvider(resolved, descriptor);
      _imageDecodeConfiguration = _currentImageDecodeConfiguration();
      setState(() {});
      return;
    }

    final driver = targetDriverFactory.create(resolved.fileUri);
    ActiveMediaPlayerLease? playerLease;
    _driver = driver;
    _lease = lease;
    _leaseStore = targetStore;
    try {
      playerLease = await ActiveMediaPlayerCoordinator.activate(
        driver,
        onRevoked: () => _handlePlayerRevoked(driver),
      );
      if (!mounted ||
          generation != _generation ||
          !identical(_driver, driver) ||
          !ActiveMediaPlayerCoordinator.isActive(playerLease)) {
        await _releaseStaleVideoLoad(
          driver: driver,
          playerLease: playerLease,
          store: targetStore,
          lease: lease,
        );
        return;
      }
      _playerLease = playerLease;
      await driver.initialize();
      await driver.pause();
      if (!mounted ||
          generation != _generation ||
          !identical(_driver, driver) ||
          !ActiveMediaPlayerCoordinator.isActive(playerLease)) {
        await _releaseStaleVideoLoad(
          driver: driver,
          playerLease: playerLease,
          store: targetStore,
          lease: lease,
        );
        return;
      }
      final snapshot = driver.snapshot;
      if (!snapshot.isInitialized || snapshot.duration <= Duration.zero) {
        throw const UnsupportedMediaPlaybackException();
      }
      _resource = resolved;
      driver.addListener(_onDriverChanged);
      setState(() {});
    } on UnsupportedMediaPlaybackException {
      await _releaseStaleVideoLoad(
        driver: driver,
        playerLease: playerLease,
        store: targetStore,
        lease: lease,
      );
      _publishFailure(generation, MediaResourceFailureCode.unsupportedMedia);
    } on Object {
      await _releaseStaleVideoLoad(
        driver: driver,
        playerLease: playerLease,
        store: targetStore,
        lease: lease,
      );
      _publishFailure(generation, MediaResourceFailureCode.playbackFailed);
    }
  }

  (Size, double) _currentImageDecodeConfiguration() {
    return (MediaQuery.sizeOf(context), MediaQuery.devicePixelRatioOf(context));
  }

  ImageProvider<Object> _createViewerImageProvider(
    ResolvedMediaResource resource,
    MediaPreviewImageDescriptor descriptor,
  ) {
    final configuration = _currentImageDecodeConfiguration();
    final decodeSize = MediaPreviewImagePolicy.viewerDecodeSize(
      source: descriptor,
      viewport: configuration.$1,
      devicePixelRatio: configuration.$2,
    );
    return ResizeImage.resizeIfNeeded(
      decodeSize.$1,
      decodeSize.$2,
      FileImage(File.fromUri(resource.fileUri)),
    );
  }

  void _refreshImageProviderForMediaQuery() {
    final resource = _resource;
    final descriptor = _imageDescriptor;
    if (resource?.kind != MediaResourceKind.image || descriptor == null) return;
    final configuration = _currentImageDecodeConfiguration();
    if (_imageDecodeConfiguration == configuration) return;
    final previous = _imageProvider;
    _imageProvider = _createViewerImageProvider(resource!, descriptor);
    _imageDecodeConfiguration = configuration;
    _decodeFailureScheduled = false;
    if (previous != null) unawaited(_evictImageProvider(previous));
  }

  Future<void> _evictImageProvider(ImageProvider<Object> provider) async {
    try {
      await provider.evict();
    } on Object {
      // A stale decode target must not block the MediaQuery update.
    }
  }

  Future<void> _handlePlayerRevoked(MediaPlaybackDriver driver) async {
    if (!identical(_driver, driver)) {
      try {
        await driver.dispose();
      } on Object {
        // The matching owner is responsible for the associated media lease.
      }
      return;
    }
    _generation += 1;
    await _releaseOwnedState();
    if (mounted) setState(() {});
  }

  Future<void> _releaseStaleVideoLoad({
    required MediaPlaybackDriver driver,
    required ActiveMediaPlayerLease? playerLease,
    required MediaResourceStore store,
    required MediaResourceLease lease,
  }) async {
    if (identical(_driver, driver)) {
      _driver = null;
      _playerLease = null;
      _lease = null;
      _leaseStore = null;
      _resource = null;
      _imageDescriptor = null;
      _imageDecodeConfiguration = null;
    }
    try {
      if (playerLease != null) {
        await ActiveMediaPlayerCoordinator.release(playerLease);
      } else {
        await driver.dispose();
      }
    } on Object {
      // The resource lease remains mandatory even if player cleanup fails.
    } finally {
      try {
        await _releaseLeaseOnce(store, lease);
      } on Object {
        // Widget cleanup cannot surface Store implementation details.
      }
    }
  }

  void _publishFailure(int generation, MediaResourceFailureCode code) {
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() => _failure = code);
  }

  void _onDriverChanged() {
    if (!mounted) {
      return;
    }
    final driver = _driver;
    if (driver?.snapshot.hasError ?? false) {
      _publishPlaybackFailure();
      return;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_pause());
    }
  }

  @override
  void didPushNext() {
    unawaited(_pause());
  }

  @override
  void didPopNext() {
    _restoreAfterRouteCover();
  }

  void _restoreAfterRouteCover() {
    if (_driver == null && _resource == null && _failure == null) {
      if (_routeRestore != null) return;
      late final Future<void> operation;
      operation = _load().whenComplete(() {
        if (identical(_routeRestore, operation)) {
          _routeRestore = null;
        }
      });
      _routeRestore = operation;
      unawaited(operation);
    }
  }

  Future<void> _pause() async {
    final driver = _driver;
    if (driver != null && driver.snapshot.isPlaying) {
      try {
        await driver.pause();
      } on Object {
        _publishPlaybackFailure();
      }
    }
  }

  Future<void> _togglePlayback() async {
    final driver = _driver;
    if (driver == null) {
      return;
    }
    try {
      final snapshot = driver.snapshot;
      if (snapshot.isCompleted ||
          (snapshot.duration > Duration.zero &&
              snapshot.position >= snapshot.duration)) {
        await driver.seekTo(Duration.zero);
        await driver.play();
      } else if (snapshot.isPlaying) {
        await driver.pause();
      } else {
        await driver.play();
      }
    } on Object {
      _publishPlaybackFailure();
    }
  }

  Future<void> _seek(double milliseconds) async {
    final driver = _driver;
    if (driver == null) {
      return;
    }
    try {
      await driver.seekTo(Duration(milliseconds: milliseconds.round()));
    } on Object {
      _publishPlaybackFailure();
    }
  }

  void _publishPlaybackFailure() {
    if (!mounted || _handlingPlaybackFailure) {
      return;
    }
    _handlingPlaybackFailure = true;
    setState(() => _failure = MediaResourceFailureCode.playbackFailed);
    unawaited(_releaseAfterPlaybackFailure());
  }

  Future<void> _releaseAfterPlaybackFailure() async {
    try {
      await _releaseOwnedState();
    } finally {
      _handlingPlaybackFailure = false;
    }
  }

  Future<void> _releaseOwnedState() async {
    final driver = _driver;
    final playerLease = _playerLease;
    final lease = _lease;
    final leaseStore = _leaseStore;
    final imageProvider = _imageProvider;
    _driver = null;
    _playerLease = null;
    _lease = null;
    _leaseStore = null;
    _resource = null;
    _imageDescriptor = null;
    _imageProvider = null;
    _imageDecodeConfiguration = null;
    try {
      if (imageProvider != null) {
        try {
          await imageProvider.evict();
        } on Object {
          // Continue with player and lease cleanup.
        }
      }
      if (driver != null) {
        driver.removeListener(_onDriverChanged);
        try {
          if (playerLease != null) {
            await ActiveMediaPlayerCoordinator.release(playerLease);
          } else {
            await driver.dispose();
          }
        } on Object {
          // Continue with the mandatory media lease release.
        }
      }
    } finally {
      if (lease != null && leaseStore != null) {
        try {
          await _releaseLeaseOnce(leaseStore, lease);
        } on Object {
          // Widget teardown must not emit an unhandled cleanup exception.
        }
      }
    }
  }

  Future<void> _releaseLeaseOnce(
    MediaResourceStore store,
    MediaResourceLease lease,
  ) {
    return _leaseReleases.putIfAbsent(lease, () async {
      await store.release(lease);
    });
  }

  void _scheduleImageDecodeFailure() {
    if (_decodeFailureScheduled) return;
    _decodeFailureScheduled = true;
    final generation = _generation;
    scheduleMicrotask(() {
      if (!mounted || generation != _generation) return;
      _generation += 1;
      final release = _releaseOwnedState();
      setState(() => _failure = MediaResourceFailureCode.decodeFailed);
      unawaited(release);
    });
  }

  @override
  void dispose() {
    _generation += 1;
    WidgetsBinding.instance.removeObserver(this);
    widget.routeObserver?.unsubscribe(this);
    unawaited(_releaseOwnedState());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    final resource = _resource;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _buildContent(resource, driver),
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                tooltip: 'Close preview',
                onPressed:
                    widget.onClose ??
                    () => unawaited(Navigator.maybePop(context)),
                color: AppColors.textOnPrimary,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          if (resource?.kind == MediaResourceKind.video && driver != null)
            _VideoControls(
              snapshot: driver.snapshot,
              onToggle: _togglePlayback,
              onSeek: _seek,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(
    ResolvedMediaResource? resource,
    MediaPlaybackDriver? driver,
  ) {
    if (_failure != null) {
      return const _PreviewStatus(
        icon: Icons.error_outline,
        label: 'Media preview unavailable',
      );
    }
    if (resource == null) {
      return const _PreviewStatus(
        icon: Icons.hourglass_empty,
        label: 'Loading media preview',
      );
    }
    if (resource.kind == MediaResourceKind.image) {
      final imageProvider = _imageProvider;
      if (imageProvider == null) {
        return const _PreviewStatus(
          icon: Icons.hourglass_empty,
          label: 'Loading image preview',
        );
      }
      return InteractiveViewer(
        minScale: 1,
        maxScale: MediaPreviewImagePolicy.maximumViewerScale,
        panEnabled: true,
        scaleEnabled: true,
        child: Center(
          child: Image(
            image: imageProvider,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) {
              _scheduleImageDecodeFailure();
              return const _PreviewStatus(
                icon: Icons.broken_image_outlined,
                label: 'Image preview unavailable',
              );
            },
          ),
        ),
      );
    }
    if (driver == null) {
      return const _PreviewStatus(
        icon: Icons.hourglass_empty,
        label: 'Loading video preview',
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: driver.snapshot.aspectRatio,
        child: driver.buildSurface(),
      ),
    );
  }
}

final class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.snapshot,
    required this.onToggle,
    required this.onSeek,
  });

  final MediaPlaybackSnapshot snapshot;
  final Future<void> Function() onToggle;
  final Future<void> Function(double) onSeek;

  @override
  Widget build(BuildContext context) {
    final durationMs = snapshot.duration.inMilliseconds;
    final positionMs = snapshot.position.inMilliseconds.clamp(0, durationMs);
    final replay =
        snapshot.isCompleted || (durationMs > 0 && positionMs >= durationMs);
    final compact = MediaQuery.sizeOf(context).width < 420;
    final playButton = IconButton(
      tooltip: snapshot.isPlaying
          ? 'Pause video'
          : replay
          ? 'Replay video'
          : 'Play video',
      onPressed: onToggle,
      color: AppColors.textOnPrimary,
      icon: Icon(
        replay
            ? Icons.replay
            : snapshot.isPlaying
            ? Icons.pause
            : Icons.play_arrow,
      ),
    );
    final slider = Slider(
      value: positionMs.toDouble(),
      max: durationMs <= 0 ? 1 : durationMs.toDouble(),
      onChanged: onSeek,
    );
    final currentLabel = Text(
      _formatDuration(snapshot.position),
      style: const TextStyle(color: AppColors.textOnPrimary),
    );
    final totalLabel = Text(
      _formatDuration(snapshot.duration),
      style: const TextStyle(color: AppColors.textOnPrimary),
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: IconButton.filledTonal(
            tooltip: replay
                ? 'Replay video'
                : snapshot.isPlaying
                ? 'Pause video'
                : 'Play video',
            onPressed: onToggle,
            color: AppColors.textOnPrimary,
            iconSize: 44,
            icon: Icon(
              replay
                  ? Icons.replay
                  : snapshot.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: compact ? 88 : 64,
              child: ColoredBox(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: compact
                      ? Column(
                          children: <Widget>[
                            SizedBox(
                              height: 48,
                              child: Row(
                                children: <Widget>[
                                  playButton,
                                  Expanded(child: slider),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: currentLabel,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: totalLabel,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: <Widget>[
                            playButton,
                            currentLabel,
                            Expanded(child: slider),
                            totalLabel,
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Center(
        child: Icon(icon, color: AppColors.textOnPrimary, size: 40),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = totalSeconds.remainder(3600) ~/ 60;
  final seconds = totalSeconds.remainder(60);
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
