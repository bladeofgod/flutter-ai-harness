import 'package:app_data/app_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../api/cart_api.dart';
import '../api/checkout_api.dart';
import 'controllers/checkout_controller.dart';
import 'pages/checkout_page.dart';
import 'pages/payment_method_page.dart';
import 'pages/payment_result_page.dart';
import 'pages/shipping_address_page.dart';
import 'pages/voucher_page.dart';
import 'widgets/checkout_components.dart';

const checkoutRoutePath = '/checkout';
const checkoutVoucherRoutePath = '/checkout/voucher';
const checkoutAddressRoutePath = '/checkout/address';
const checkoutPaymentMethodRoutePath = '/checkout/payment-method';
const checkoutResultRoutePath = '/checkout/result';

String checkoutLocationWithVoucher(String voucherId) => Uri(
  path: checkoutRoutePath,
  queryParameters: <String, String>{'voucherId': voucherId},
).toString();

typedef CheckoutNavigationCallback = void Function(BuildContext context);
typedef CheckoutCompletedNavigation =
    void Function(BuildContext context, CheckoutReceipt receipt);
typedef CheckoutReceiptSettlement =
    Future<void> Function(CheckoutReceipt receipt, Cart cart);

List<RouteBase> buildCheckoutRoutes({
  required CartApi cartApi,
  required CheckoutApi checkoutApi,
  required CheckoutNavigationCallback onEmptyCart,
  required CheckoutNavigationCallback onCompleted,
  CheckoutCompletedNavigation? onCompletedWithReceipt,
  CheckoutReceiptSettlement? onReceiptReady,
}) {
  final coordinator = _CheckoutScopeCoordinator(
    cartApi: cartApi,
    checkoutApi: checkoutApi,
    onReceiptReady: onReceiptReady,
  );
  return <RouteBase>[
    GoRoute(
      path: checkoutRoutePath,
      builder: (context, state) => _CheckoutRoutePage(
        coordinator: coordinator,
        onEmptyCart: onEmptyCart,
        requestedVoucherId: state.uri.queryParameters['voucherId'],
        contentBuilder: (controller) => CheckoutPage(controller: controller),
      ),
      routes: <RouteBase>[
        _childRoute(
          path: 'voucher',
          coordinator: coordinator,
          onEmptyCart: onEmptyCart,
          contentBuilder: (controller) =>
              CheckoutVoucherPage(controller: controller),
        ),
        _childRoute(
          path: 'address',
          coordinator: coordinator,
          onEmptyCart: onEmptyCart,
          contentBuilder: (controller) =>
              CheckoutShippingAddressPage(controller: controller),
        ),
        _childRoute(
          path: 'payment-method',
          coordinator: coordinator,
          onEmptyCart: onEmptyCart,
          contentBuilder: (controller) =>
              CheckoutPaymentMethodPage(controller: controller),
        ),
        _childRoute(
          path: 'result',
          coordinator: coordinator,
          onEmptyCart: onEmptyCart,
          contentBuilder: (controller) => CheckoutPaymentResultPage(
            controller: controller,
            onCompleted: onCompleted,
            onCompletedWithReceipt: onCompletedWithReceipt,
          ),
        ),
      ],
    ),
  ];
}

GoRoute _childRoute({
  required String path,
  required _CheckoutScopeCoordinator coordinator,
  required CheckoutNavigationCallback onEmptyCart,
  required _CheckoutContentBuilder contentBuilder,
}) => GoRoute(
  path: path,
  builder: (context, state) => _CheckoutRoutePage(
    coordinator: coordinator,
    onEmptyCart: onEmptyCart,
    contentBuilder: contentBuilder,
  ),
);

typedef _CheckoutContentBuilder =
    Widget Function(CheckoutController controller);

final class _CheckoutScopeCoordinator {
  _CheckoutScopeCoordinator({
    required this.cartApi,
    required this.checkoutApi,
    this.onReceiptReady,
  });

  final CartApi cartApi;
  final CheckoutApi checkoutApi;
  final CheckoutReceiptSettlement? onReceiptReady;
  CheckoutController? _controller;
  int _leases = 0;
  bool _emptyRedirectScheduled = false;

  CheckoutController acquire() {
    final controller =
        _controller ??
        CheckoutController(
          cartApi: cartApi,
          checkoutApi: checkoutApi,
          onReceiptReady: onReceiptReady,
        );
    if (_controller == null) {
      _controller = controller;
      _emptyRedirectScheduled = false;
      controller.onInit();
    }
    _leases += 1;
    return controller;
  }

  void release(CheckoutController controller) {
    assert(identical(controller, _controller));
    _leases -= 1;
    assert(_leases >= 0);
    if (_leases == 0) {
      controller.onDelete();
      _controller = null;
    }
  }

  void scheduleEmptyRedirect(
    BuildContext context,
    CheckoutNavigationCallback onEmptyCart,
  ) {
    if (_emptyRedirectScheduled) {
      return;
    }
    _emptyRedirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        onEmptyCart(context);
      }
    });
  }
}

final class _CheckoutRoutePage extends StatefulWidget {
  const _CheckoutRoutePage({
    required this.coordinator,
    required this.onEmptyCart,
    required this.contentBuilder,
    this.requestedVoucherId,
  });

  final _CheckoutScopeCoordinator coordinator;
  final CheckoutNavigationCallback onEmptyCart;
  final _CheckoutContentBuilder contentBuilder;
  final String? requestedVoucherId;

  @override
  State<_CheckoutRoutePage> createState() => _CheckoutRoutePageState();
}

final class _CheckoutRoutePageState extends State<_CheckoutRoutePage> {
  late final CheckoutController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.coordinator.acquire();
    final requestedVoucherId = widget.requestedVoucherId;
    if (requestedVoucherId != null) {
      _controller.requestVoucherById(requestedVoucherId);
    }
  }

  @override
  void dispose() {
    widget.coordinator.release(_controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = _controller.viewState;
    return switch (state) {
      CheckoutLoading() => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: ValueKey('checkout-loading')),
        ),
      ),
      CheckoutEmptyCart() => _emptyCartRedirect(context),
      CheckoutError(:final failure) => _CheckoutLoadError(
        failure: failure,
        canLeave: !_controller.hasPendingSettlement,
        onRetry: _controller.retryFromUi,
      ),
      CheckoutReady() => widget.contentBuilder(_controller),
    };
  });

  Widget _emptyCartRedirect(BuildContext context) {
    widget.coordinator.scheduleEmptyRedirect(context, widget.onEmptyCart);
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          key: ValueKey('checkout-empty-cart-redirect'),
        ),
      ),
    );
  }
}

final class _CheckoutLoadError extends StatelessWidget {
  const _CheckoutLoadError({
    required this.failure,
    required this.canLeave,
    required this.onRetry,
  });

  final Object failure;
  final bool canLeave;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: canLeave,
    child: CheckoutPageScaffold(
      title: 'Payment',
      showBack: canLeave,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52),
              const SizedBox(height: 16),
              Text('Checkout is unavailable', style: checkoutHeading(size: 20)),
              const SizedBox(height: 8),
              Text(
                'Your cart has not changed. Retry the local Demo checkout.',
                textAlign: TextAlign.center,
                style: checkoutBody(),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('checkout-retry-load'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
