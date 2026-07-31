import 'dart:async';

import 'package:app_data/orders.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../api/current_user_provider.dart';
import '../api/order_review_media_api.dart';
import '../api/orders_api.dart';
import 'controllers/orders_controller.dart';
import 'pages/activity_page.dart';
import 'pages/order_detail_page.dart';
import 'pages/order_review_page.dart';
import 'widgets/orders_components.dart';

const activityRoutePath = '/activity';
const activityHistoryRoutePath = '/activity?filter=history';
const ordersRoutePath = '/orders';

String orderDetailRoutePath(String orderId) =>
    '$ordersRoutePath/${Uri.encodeComponent(orderId)}';

String orderReviewRoutePath(String orderId) =>
    '${orderDetailRoutePath(orderId)}/review';

List<RouteBase> buildOrdersRoutes({
  required OrdersApi ordersApi,
  required OrderReviewMediaApi mediaApi,
  required CurrentUserProvider currentUserProvider,
}) => <RouteBase>[
  GoRoute(
    path: activityRoutePath,
    builder: (context, state) => _OrdersRoutePage(
      controller: OrdersController.activity(
        ordersApi: ordersApi,
        currentUserProvider: currentUserProvider,
        initialFilter: state.uri.queryParameters['filter'] == 'history'
            ? ActivityFilter.history
            : ActivityFilter.activity,
      ),
      mode: _OrdersRouteMode.activity,
    ),
  ),
  GoRoute(
    path: '$ordersRoutePath/:orderId',
    builder: (context, state) {
      final orderId = state.pathParameters['orderId']!;
      return _OrdersRoutePage(
        controller: OrdersController.order(
          ordersApi: ordersApi,
          currentUserProvider: currentUserProvider,
          orderId: orderId,
        ),
        mode: _OrdersRouteMode.detail,
      );
    },
    routes: <RouteBase>[
      GoRoute(
        path: 'review',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return _OrdersRoutePage(
            controller: OrdersController.review(
              ordersApi: ordersApi,
              currentUserProvider: currentUserProvider,
              mediaApi: mediaApi,
              orderId: orderId,
            ),
            mode: _OrdersRouteMode.review,
          );
        },
      ),
    ],
  ),
];

enum _OrdersRouteMode { activity, detail, review }

final class _OrdersRoutePage extends StatefulWidget {
  const _OrdersRoutePage({required this.controller, required this.mode});

  final OrdersController controller;
  final _OrdersRouteMode mode;

  @override
  State<_OrdersRoutePage> createState() => _OrdersRoutePageState();
}

final class _OrdersRoutePageState extends State<_OrdersRoutePage> {
  @override
  void initState() {
    super.initState();
    widget.controller.onInit();
  }

  @override
  void didUpdateWidget(covariant _OrdersRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) {
      return;
    }
    oldWidget.controller.onDelete();
    widget.controller.onInit();
  }

  @override
  void dispose() {
    widget.controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = widget.controller.viewState;
    return switch (state) {
      OrdersLoading() => const OrdersPageScaffold(
        title: 'My Activity',
        child: Center(
          child: CircularProgressIndicator(key: ValueKey('orders-loading')),
        ),
      ),
      OrdersError(:final failure) => _OrdersErrorPage(
        failure: failure,
        onRetry: widget.controller.retryFromUi,
      ),
      OrdersActivityData(:final filter, :final orders) => OrdersActivityPage(
        filter: filter,
        orders: orders,
        onSelectFilter: widget.controller.selectFilter,
        onOpenOrder: (orderId) => context.push(orderDetailRoutePath(orderId)),
      ),
      OrderDetailData(:final order) => switch (widget.mode) {
        _OrdersRouteMode.review => OrderReviewPage(
          order: order,
          rating: widget.controller.rating,
          isSubmitting: widget.controller.isSubmittingReview,
          validationMessage: widget.controller.reviewValidationMessage,
          mediaState: widget.controller.mediaState,
          onSelectRating: widget.controller.selectRating,
          onCommentChanged: widget.controller.updateReviewComment,
          onSubmit: widget.controller.submitReviewFromUi,
          onCaptureMedia: () {
            unawaited(widget.controller.captureMedia());
          },
          onRetakeMedia: () {
            unawaited(widget.controller.retakeMedia());
          },
          onRemoveMedia: () {
            unawaited(widget.controller.removeMedia());
          },
          onRetryMedia: () {
            unawaited(widget.controller.retryMediaOperation());
          },
          onThumbnailDecodeFailure: (attachment) {
            unawaited(
              widget.controller.reportThumbnailDecodeFailure(attachment),
            );
          },
          onDone: (order) => context.go(orderDetailRoutePath(order.id)),
        ),
        _OrdersRouteMode.detail || _OrdersRouteMode.activity => OrderDetailPage(
          order: order,
          onDismissNotification: widget.controller.dismissNotificationFromUi,
          onReview: () {
            unawaited(context.push(orderReviewRoutePath(order.id)));
          },
        ),
      },
    };
  });
}

final class _OrdersErrorPage extends StatelessWidget {
  const _OrdersErrorPage({required this.failure, required this.onRetry});

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => OrdersPageScaffold(
    title: 'My Activity',
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 52),
            const SizedBox(height: 14),
            Text('Orders are unavailable', style: ordersHeading(size: 20)),
            const SizedBox(height: 8),
            Text(
              'Retry the local Demo order history.',
              textAlign: TextAlign.center,
              style: ordersBody(),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('orders-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}
