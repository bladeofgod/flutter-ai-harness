import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/checkout_controller.dart';
import '../routes.dart';
import '../widgets/checkout_components.dart';

final class CheckoutPaymentResultPage extends StatelessWidget {
  const CheckoutPaymentResultPage({
    required this.controller,
    required this.onCompleted,
    this.onCompletedWithReceipt,
    super.key,
  });

  final CheckoutController controller;
  final CheckoutNavigationCallback onCompleted;
  final CheckoutCompletedNavigation? onCompletedWithReceipt;

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = controller.viewState;
    if (state case CheckoutReady(:final session)) {
      return switch (session.paymentState) {
        PaymentState.inProgress => const _PaymentProgress(),
        PaymentState.failed => _PaymentFailure(controller: controller),
        PaymentState.succeeded => _PaymentSuccess(
          session: session,
          onContinue: () {
            final receipt = session.receipt;
            if (receipt != null && onCompletedWithReceipt != null) {
              onCompletedWithReceipt!(context, receipt);
            } else {
              onCompleted(context);
            }
          },
        ),
        PaymentState.ready => _PaymentReady(controller: controller),
      };
    }
    return const SizedBox.shrink();
  });
}

final class _PaymentProgress extends StatelessWidget {
  const _PaymentProgress();

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: false,
    child: CheckoutPageScaffold(
      title: 'Payment',
      showBack: false,
      child: Center(
        key: const ValueKey('checkout-payment-progress'),
        child: Semantics(
          key: const ValueKey('checkout-payment-progress-semantics'),
          liveRegion: true,
          label: 'Demo payment in progress',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              const SizedBox(height: 24),
              Text('Payment in progress', style: checkoutHeading(size: 22)),
              const SizedBox(height: 8),
              Text(
                'Completing a local Demo payment...',
                textAlign: TextAlign.center,
                style: checkoutBody(color: const Color(0xFF777777)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _PaymentFailure extends StatelessWidget {
  const _PaymentFailure({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) => CheckoutPageScaffold(
    title: 'Payment',
    bottomAction: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckoutPrimaryButton(
          key: const ValueKey('checkout-payment-retry'),
          label: 'Try again',
          onPressed: controller.payFromUi,
        ),
        TextButton.icon(
          key: const ValueKey('checkout-change-payment-method'),
          onPressed: () => context.push(checkoutPaymentMethodRoutePath),
          icon: const Icon(Icons.credit_card),
          label: const Text('Choose another payment method'),
        ),
      ],
    ),
    child: _ResultBody(
      key: const ValueKey('checkout-payment-failed'),
      icon: Icons.close,
      iconColor: const Color(0xFFFF6B73),
      backgroundColor: const Color(0xFFFFE8EA),
      title: "Couldn't proceed payment",
      description:
          'No external transaction was created. Your cart is unchanged, '
          'so you can choose another Demo card and retry.',
    ),
  );
}

final class _PaymentSuccess extends StatelessWidget {
  const _PaymentSuccess({required this.session, required this.onContinue});

  final CheckoutSession session;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => CheckoutPageScaffold(
    title: 'Payment',
    showBack: false,
    bottomAction: CheckoutPrimaryButton(
      key: const ValueKey('checkout-payment-continue'),
      label: 'Continue shopping',
      onPressed: onContinue,
    ),
    child: _ResultBody(
      key: const ValueKey('checkout-payment-succeeded'),
      icon: Icons.check,
      iconColor: AppColors.success,
      backgroundColor: const Color(0xFFE9FBEA),
      title: 'Demo payment completed',
      description:
          'No real card was charged. This receipt only records the local '
          'Demo checkout for ${session.total.format()}.',
      receiptId: session.receipt?.id,
    ),
  );
}

final class _PaymentReady extends StatelessWidget {
  const _PaymentReady({required this.controller});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) => CheckoutPageScaffold(
    title: 'Payment',
    bottomAction: CheckoutPrimaryButton(
      key: const ValueKey('checkout-result-pay'),
      label: 'Start Demo payment',
      onPressed: controller.payFromUi,
    ),
    child: const _ResultBody(
      key: ValueKey('checkout-payment-ready'),
      icon: Icons.lock_outline,
      iconColor: AppColors.primary,
      backgroundColor: AppColors.primarySurface,
      title: 'Ready for Demo payment',
      description: 'Review your local checkout and continue when ready.',
    ),
  );
}

final class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.description,
    this.receiptId,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String description;
  final String? receiptId;

  @override
  Widget build(BuildContext context) => CheckoutContent(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 58, 24, 30),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: iconColor),
            ),
            const SizedBox(height: 28),
            Text(title, textAlign: TextAlign.center, style: checkoutHeading()),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: checkoutBody(
                size: 14,
                color: const Color(0xFF666666),
                height: 1.5,
              ),
            ),
            if (receiptId != null) ...[
              const SizedBox(height: 20),
              Text(
                'Receipt ${receiptId!}',
                style: checkoutBody(size: 12, weight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
