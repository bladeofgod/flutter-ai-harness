import 'package:app_data/app_data.dart' show ProductReview;
import 'package:app_data/orders.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../../shared/catalog/catalog_asset_image.dart';
import '../widgets/orders_components.dart';

final class OrderReviewPage extends StatefulWidget {
  const OrderReviewPage({
    required this.order,
    required this.rating,
    required this.isSubmitting,
    required this.validationMessage,
    required this.onSelectRating,
    required this.onCommentChanged,
    required this.onSubmit,
    required this.onDone,
    super.key,
  });

  final Order order;
  final int rating;
  final bool isSubmitting;
  final String? validationMessage;
  final ValueChanged<int> onSelectRating;
  final ValueChanged<String> onCommentChanged;
  final VoidCallback onSubmit;
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
                    onPressed: widget.isSubmitting
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
            enabled: !widget.isSubmitting,
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
          OrdersPrimaryButton(
            key: const ValueKey('order-submit-review'),
            label: widget.isSubmitting ? 'Submitting...' : 'Submit review',
            icon: Icons.check,
            onPressed: widget.isSubmitting ? null : widget.onSubmit,
          ),
        ],
      ),
    );
  }
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
