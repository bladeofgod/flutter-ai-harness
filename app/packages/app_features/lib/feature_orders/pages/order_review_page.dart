import 'dart:async';

import 'package:app_data/app_data.dart' show ProductReview;
import 'package:app_data/orders.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../api/order_review_media_api.dart';
import '../../shared/catalog/catalog_asset_image.dart';
import '../controllers/orders_controller.dart';
import '../widgets/orders_components.dart';

final class OrderReviewPage extends StatefulWidget {
  const OrderReviewPage({
    required this.order,
    required this.rating,
    required this.isSubmitting,
    required this.validationMessage,
    required this.mediaState,
    required this.onSelectRating,
    required this.onCommentChanged,
    required this.onSubmit,
    required this.onCaptureMedia,
    required this.onRetakeMedia,
    required this.onRemoveMedia,
    required this.onRetryMedia,
    required this.onThumbnailDecodeFailure,
    required this.onDone,
    super.key,
  });

  final Order order;
  final int rating;
  final bool isSubmitting;
  final String? validationMessage;
  final OrderReviewMediaDraftState mediaState;
  final ValueChanged<int> onSelectRating;
  final ValueChanged<String> onCommentChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCaptureMedia;
  final VoidCallback onRetakeMedia;
  final VoidCallback onRemoveMedia;
  final VoidCallback onRetryMedia;
  final ValueChanged<OrderReviewMediaAttachment> onThumbnailDecodeFailure;
  final ValueChanged<Order> onDone;

  @override
  State<OrderReviewPage> createState() => _OrderReviewPageState();
}

final class _OrderReviewPageState extends State<OrderReviewPage> {
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.order.review;
    if (review != null) {
      return _ReviewComplete(
        review: review,
        onDone: () {
          widget.onDone(widget.order);
        },
      );
    }
    final isMediaBusy =
        widget.mediaState is OrderReviewMediaLaunching ||
        widget.mediaState is OrderReviewMediaRemoving;
    return OrdersPageScaffold(
      title: 'Review',
      child: ListView(
        key: const ValueKey('order-review-form'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 82,
                  child: CatalogAssetImage(
                    assetKey: widget.order.lines.first.product.imageAssetKey,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.order.lines.first.product.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: ordersHeading(size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text('How was your order?', style: ordersHeading(size: 20)),
          const SizedBox(height: 8),
          Text(
            'Choose a rating for this local Demo purchase.',
            style: ordersBody(color: const Color(0xFF707070)),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: widget.rating == 0
                ? 'No rating selected'
                : '${widget.rating} of 5 stars selected',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(5, (index) {
                final value = index + 1;
                return Expanded(
                  child: IconButton(
                    key: ValueKey('order-review-rating-$value'),
                    tooltip: '$value star${value == 1 ? '' : 's'}',
                    onPressed: widget.isSubmitting || isMediaBusy
                        ? null
                        : () => widget.onSelectRating(value),
                    icon: Icon(
                      value <= widget.rating ? Icons.star : Icons.star_border,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('order-review-comment'),
            controller: _commentController,
            enabled: !widget.isSubmitting && !isMediaBusy,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: widget.onCommentChanged,
            decoration: InputDecoration(
              labelText: 'Your review',
              hintText: 'Share what you liked about this Demo order',
              alignLabelWithHint: true,
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              errorText: widget.validationMessage,
            ),
          ),
          const SizedBox(height: 18),
          _OrderReviewMediaSection(
            state: widget.mediaState,
            isEnabled: !widget.isSubmitting,
            onCapture: widget.onCaptureMedia,
            onRetake: widget.onRetakeMedia,
            onRemove: widget.onRemoveMedia,
            onRetry: widget.onRetryMedia,
            onThumbnailDecodeFailure: widget.onThumbnailDecodeFailure,
          ),
          const SizedBox(height: 18),
          OrdersPrimaryButton(
            key: const ValueKey('order-submit-review'),
            label: widget.isSubmitting ? 'Submitting...' : 'Submit review',
            icon: Icons.check,
            onPressed: widget.isSubmitting || isMediaBusy
                ? null
                : widget.onSubmit,
          ),
        ],
      ),
    );
  }
}

final class _OrderReviewMediaSection extends StatelessWidget {
  const _OrderReviewMediaSection({
    required this.state,
    required this.isEnabled,
    required this.onCapture,
    required this.onRetake,
    required this.onRemove,
    required this.onRetry,
    required this.onThumbnailDecodeFailure,
  });

  final OrderReviewMediaDraftState state;
  final bool isEnabled;
  final VoidCallback onCapture;
  final VoidCallback onRetake;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  final ValueChanged<OrderReviewMediaAttachment> onThumbnailDecodeFailure;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      OrderReviewMediaEmpty() || OrderReviewMediaDraftReleased() => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('order-review-media-add'),
          onPressed: isEnabled ? onCapture : null,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Add photo or video'),
        ),
      ),
      OrderReviewMediaLaunching() => const _MediaStatus(
        key: ValueKey('order-review-media-launching'),
        label: 'Opening camera...',
      ),
      OrderReviewMediaReady(:final attachment) => _MediaAttachment(
        key: const ValueKey('order-review-media-ready'),
        attachment: attachment,
        onRetake: isEnabled ? onRetake : null,
        onRemove: isEnabled ? onRemove : null,
        onThumbnailDecodeFailure: onThumbnailDecodeFailure,
      ),
      OrderReviewMediaRemoving() => const _MediaStatus(
        key: ValueKey('order-review-media-removing'),
        label: 'Removing attachment...',
      ),
      OrderReviewMediaDraftFailure(
        :final message,
        :final retainedAttachment,
        :final showRetainedThumbnail,
      ) =>
        _MediaFailure(
          message: message,
          retainedAttachment: retainedAttachment,
          showRetainedThumbnail: showRetainedThumbnail,
          onRetry: isEnabled ? onRetry : null,
          onRemove: retainedAttachment == null || !isEnabled ? null : onRemove,
          onThumbnailDecodeFailure: onThumbnailDecodeFailure,
        ),
    };
  }
}

final class _MediaStatus extends StatelessWidget {
  const _MediaStatus({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: ordersBody())),
        ],
      ),
    ),
  );
}

final class _MediaAttachment extends StatelessWidget {
  const _MediaAttachment({
    required this.attachment,
    required this.onRetake,
    required this.onRemove,
    required this.onThumbnailDecodeFailure,
    super.key,
  });

  final OrderReviewMediaAttachment attachment;
  final VoidCallback? onRetake;
  final VoidCallback? onRemove;
  final ValueChanged<OrderReviewMediaAttachment> onThumbnailDecodeFailure;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 112),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        _MediaThumbnail(
          attachment: attachment,
          onDecodeFailure: onThumbnailDecodeFailure,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attachment.type == OrderReviewMediaType.photo
                    ? 'Photo attached'
                    : 'Video attached',
                style: ordersHeading(size: 16),
              ),
              if (attachment.duration case final duration?) ...[
                const SizedBox(height: 4),
                Text(_formatDuration(duration), style: ordersBody()),
              ],
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              key: const ValueKey('order-review-media-retake'),
              label: 'Retake',
              button: true,
              onTap: onRetake,
              excludeSemantics: true,
              child: IconButton(
                tooltip: 'Retake',
                onPressed: onRetake,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Semantics(
              key: const ValueKey('order-review-media-remove'),
              label: 'Remove attachment',
              button: true,
              onTap: onRemove,
              excludeSemantics: true,
              child: IconButton(
                tooltip: 'Remove attachment',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

final class _MediaThumbnail extends StatefulWidget {
  const _MediaThumbnail({
    required this.attachment,
    required this.onDecodeFailure,
  });

  final OrderReviewMediaAttachment attachment;
  final ValueChanged<OrderReviewMediaAttachment> onDecodeFailure;

  @override
  State<_MediaThumbnail> createState() => _MediaThumbnailState();
}

final class _MediaThumbnailState extends State<_MediaThumbnail> {
  late MemoryImage _imageProvider;
  bool _reportedFailure = false;

  @override
  void initState() {
    super.initState();
    _imageProvider = MemoryImage(widget.attachment.thumbnailBytes);
  }

  @override
  void didUpdateWidget(covariant _MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.attachment, widget.attachment)) {
      _evict(_imageProvider);
      _imageProvider = MemoryImage(widget.attachment.thumbnailBytes);
      _reportedFailure = false;
    }
  }

  @override
  void dispose() {
    _evict(_imageProvider);
    super.dispose();
  }

  void _evict(MemoryImage provider) {
    unawaited(
      provider.obtainKey(const ImageConfiguration()).then((key) {
        PaintingBinding.instance.imageCache.evict(key, includeLive: true);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: 96,
      child: Image(
        image: _imageProvider,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        semanticLabel: widget.attachment.type == OrderReviewMediaType.photo
            ? 'Captured photo thumbnail'
            : 'Captured video thumbnail',
        errorBuilder: (context, error, stackTrace) {
          if (!_reportedFailure) {
            _reportedFailure = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                widget.onDecodeFailure(widget.attachment);
              }
            });
          }
          return const ColoredBox(
            color: AppColors.primarySurface,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.primary,
              ),
            ),
          );
        },
      ),
    ),
  );
}

final class _MediaFailure extends StatelessWidget {
  const _MediaFailure({
    required this.message,
    required this.retainedAttachment,
    required this.showRetainedThumbnail,
    required this.onRetry,
    required this.onRemove,
    required this.onThumbnailDecodeFailure,
  });

  final String message;
  final OrderReviewMediaAttachment? retainedAttachment;
  final bool showRetainedThumbnail;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final ValueChanged<OrderReviewMediaAttachment> onThumbnailDecodeFailure;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('order-review-media-failure'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (retainedAttachment case final attachment?
              when showRetainedThumbnail) ...[
            Row(
              children: [
                _MediaThumbnail(
                  attachment: attachment,
                  onDecodeFailure: onThumbnailDecodeFailure,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(message, style: ordersBody())),
              ],
            ),
          ] else
            Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(message, style: ordersBody())),
              ],
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('order-review-media-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              if (onRemove case final remove?)
                IconButton(
                  key: const ValueKey('order-review-media-remove'),
                  tooltip: 'Remove attachment',
                  onPressed: remove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

final class _ReviewComplete extends StatelessWidget {
  const _ReviewComplete({required this.review, required this.onDone});

  final ProductReview review;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => OrdersPageScaffold(
    title: 'Review',
    showBack: false,
    child: Center(
      key: const ValueKey('order-review-complete'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primarySurface,
              child: Icon(Icons.check, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Thank you for your review',
              textAlign: TextAlign.center,
              style: ordersHeading(),
            ),
            const SizedBox(height: 10),
            Text(
              'Your ${review.rating}-star review was saved in this Demo session.',
              textAlign: TextAlign.center,
              style: ordersBody(height: 1.5, color: const Color(0xFF707070)),
            ),
            const SizedBox(height: 28),
            OrdersPrimaryButton(
              key: const ValueKey('order-review-done'),
              label: 'Done',
              icon: Icons.arrow_back,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    ),
  );
}
