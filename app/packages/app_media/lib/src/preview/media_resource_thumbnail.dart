import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../resource/media_resource_models.dart';
import '../resource/media_resource_store.dart';
import 'media_preview_image_policy.dart';
import 'media_preview_models.dart';

final class MediaResourceThumbnail extends StatefulWidget {
  const MediaResourceThumbnail({
    required this.resourceId,
    required this.store,
    required this.width,
    required this.height,
    this.poster,
    this.fit = BoxFit.cover,
    this.imageInspector = const FlutterMediaPreviewImageInspector(),
    super.key,
  }) : assert(width > 0),
       assert(height > 0);

  final MediaResourceId resourceId;
  final MediaResourceStore store;
  final double width;
  final double height;
  final MediaPoster? poster;
  final BoxFit fit;
  final MediaPreviewImageInspector imageInspector;

  @override
  State<MediaResourceThumbnail> createState() => _MediaResourceThumbnailState();
}

final class _MediaResourceThumbnailState extends State<MediaResourceThumbnail> {
  MediaResourceLease? _lease;
  MediaResourceStore? _leaseStore;
  ResolvedMediaResource? _resource;
  MediaPreviewImageDescriptor? _imageDescriptor;
  ImageProvider<Object>? _imageProvider;
  MediaResourceFailureCode? _failure;
  int _generation = 0;
  bool _decodeFailureScheduled = false;
  double? _devicePixelRatio;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextDevicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    if (_devicePixelRatio != null &&
        _devicePixelRatio != nextDevicePixelRatio) {
      _devicePixelRatio = nextDevicePixelRatio;
      _refreshImageProvider();
      return;
    }
    _devicePixelRatio = nextDevicePixelRatio;
  }

  @override
  void didUpdateWidget(MediaResourceThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requiresReload =
        oldWidget.resourceId != widget.resourceId ||
        !identical(oldWidget.store, widget.store) ||
        !identical(oldWidget.poster, widget.poster) ||
        !identical(oldWidget.imageInspector, widget.imageInspector);
    if (requiresReload) {
      unawaited(_load());
    } else if (oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _refreshImageProvider();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final targetStore = widget.store;
    final targetResourceId = widget.resourceId;
    final targetImageInspector = widget.imageInspector;
    final previousLease = _lease;
    final previousStore = _leaseStore;
    final previousImageProvider = _imageProvider;
    _lease = null;
    _leaseStore = null;
    _resource = null;
    _imageDescriptor = null;
    _imageProvider = null;
    _failure = null;
    _decodeFailureScheduled = false;
    if (mounted) {
      setState(() {});
    }
    await _evict(previousImageProvider);
    if (previousLease != null && previousStore != null) {
      await previousStore.release(previousLease);
    }

    final retained = await targetStore.retain(targetResourceId);
    if (retained case MediaResourceError<MediaResourceLease>(:final failure)) {
      _publishFailure(generation, failure.code);
      return;
    }
    final lease = (retained as MediaResourceSuccess<MediaResourceLease>).value;
    if (!mounted || generation != _generation) {
      await targetStore.release(lease);
      return;
    }
    final resolved = await targetStore.resolve(targetResourceId, lease);
    if (!mounted || generation != _generation) {
      await targetStore.release(lease);
      return;
    }
    if (resolved case MediaResourceError<ResolvedMediaResource>(
      :final failure,
    )) {
      await targetStore.release(lease);
      _publishFailure(generation, failure.code);
      return;
    }
    final resource =
        (resolved as MediaResourceSuccess<ResolvedMediaResource>).value;
    MediaPreviewImageDescriptor? imageDescriptor;
    if (resource.kind == MediaResourceKind.image) {
      imageDescriptor = await targetImageInspector.inspect(resource.fileUri);
      if (!mounted || generation != _generation) {
        await targetStore.release(lease);
        return;
      }
      if (imageDescriptor == null ||
          !MediaPreviewImagePolicy.acceptsSource(imageDescriptor)) {
        await targetStore.release(lease);
        _publishFailure(generation, MediaResourceFailureCode.decodeFailed);
        return;
      }
    }
    final imageProvider = _createImageProvider(resource, imageDescriptor);
    _lease = lease;
    _leaseStore = targetStore;
    _resource = resource;
    _imageDescriptor = imageDescriptor;
    _imageProvider = imageProvider;
    setState(() {});
  }

  void _refreshImageProvider() {
    final resource = _resource;
    final descriptor = _imageDescriptor;
    if (resource?.kind != MediaResourceKind.image || descriptor == null) return;
    final previous = _imageProvider;
    _imageProvider = _createImageProvider(resource!, descriptor);
    _decodeFailureScheduled = false;
    if (mounted) setState(() {});
    unawaited(_evict(previous));
  }

  ImageProvider<Object>? _createImageProvider(
    ResolvedMediaResource resource,
    MediaPreviewImageDescriptor? imageDescriptor,
  ) {
    if (resource.kind == MediaResourceKind.video) {
      final poster = widget.poster;
      return poster == null ? null : MemoryImage(poster.bytes);
    }
    final descriptor = imageDescriptor!;
    final decodeSize = MediaPreviewImagePolicy.thumbnailDecodeSize(
      source: descriptor,
      logicalSize: Size(widget.width, widget.height),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return ResizeImage.resizeIfNeeded(
      decodeSize.$1,
      decodeSize.$2,
      FileImage(File.fromUri(resource.fileUri)),
    );
  }

  void _publishFailure(int generation, MediaResourceFailureCode code) {
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() => _failure = code);
  }

  void _scheduleDecodeFailure() {
    if (_decodeFailureScheduled) return;
    _decodeFailureScheduled = true;
    final generation = _generation;
    scheduleMicrotask(() async {
      if (!mounted || generation != _generation) return;
      _generation += 1;
      final lease = _lease;
      final leaseStore = _leaseStore;
      final imageProvider = _imageProvider;
      _lease = null;
      _leaseStore = null;
      _resource = null;
      _imageDescriptor = null;
      _imageProvider = null;
      setState(() => _failure = MediaResourceFailureCode.decodeFailed);
      await _evict(imageProvider);
      if (lease != null && leaseStore != null) {
        await leaseStore.release(lease);
      }
    });
  }

  @override
  void dispose() {
    _generation += 1;
    final lease = _lease;
    final leaseStore = _leaseStore;
    final imageProvider = _imageProvider;
    _lease = null;
    _leaseStore = null;
    _imageDescriptor = null;
    _imageProvider = null;
    unawaited(_disposeOwnedState(imageProvider, leaseStore, lease));
    super.dispose();
  }

  Future<void> _disposeOwnedState(
    ImageProvider<Object>? imageProvider,
    MediaResourceStore? leaseStore,
    MediaResourceLease? lease,
  ) async {
    await _evict(imageProvider);
    if (lease != null && leaseStore != null) {
      await leaseStore.release(lease);
    }
  }

  Future<void> _evict(ImageProvider<Object>? provider) async {
    if (provider != null) {
      await provider.evict();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ColoredBox(color: AppColors.surfaceMuted, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_failure != null) {
      return const _ThumbnailStatus(
        icon: Icons.broken_image_outlined,
        semanticsLabel: 'Media preview unavailable',
      );
    }
    final resource = _resource;
    if (resource == null) {
      return const _ThumbnailStatus(
        icon: Icons.hourglass_empty,
        semanticsLabel: 'Loading media preview',
      );
    }
    if (resource.kind == MediaResourceKind.video) {
      final imageProvider = _imageProvider;
      return Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: <Widget>[
          if (imageProvider == null)
            const _ThumbnailStatus(
              icon: Icons.videocam_outlined,
              semanticsLabel: 'Video preview unavailable',
            )
          else
            Image(
              image: imageProvider,
              fit: widget.fit,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) {
                _scheduleDecodeFailure();
                return const _ThumbnailStatus(
                  icon: Icons.videocam_off_outlined,
                  semanticsLabel: 'Video preview unavailable',
                );
              },
            ),
          IgnorePointer(
            child: Center(
              child: Semantics(
                label: 'Play video',
                child: const Icon(
                  Icons.play_circle_fill,
                  color: AppColors.textOnPrimary,
                  size: 36,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final imageProvider = _imageProvider;
    if (imageProvider == null) {
      return const _ThumbnailStatus(
        icon: Icons.hourglass_empty,
        semanticsLabel: 'Loading media preview',
      );
    }
    return Image(
      image: imageProvider,
      fit: widget.fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return const _ThumbnailStatus(
          icon: Icons.hourglass_empty,
          semanticsLabel: 'Loading media preview',
        );
      },
      errorBuilder: (_, _, _) {
        _scheduleDecodeFailure();
        return const _ThumbnailStatus(
          icon: Icons.broken_image_outlined,
          semanticsLabel: 'Media preview unavailable',
        );
      },
    );
  }
}

final class _ThumbnailStatus extends StatelessWidget {
  const _ThumbnailStatus({required this.icon, required this.semanticsLabel});

  final IconData icon;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: Center(child: Icon(icon, color: AppColors.textPrimary)),
    );
  }
}
