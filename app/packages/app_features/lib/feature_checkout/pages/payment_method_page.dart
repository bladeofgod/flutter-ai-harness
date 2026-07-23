import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/checkout_controller.dart';
import '../widgets/checkout_components.dart';

final class CheckoutPaymentMethodPage extends StatelessWidget {
  const CheckoutPaymentMethodPage({required this.controller, super.key});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = controller.viewState;
    if (state case CheckoutReady(:final session, :final isMutating)) {
      return CheckoutPageScaffold(
        title: 'Payment Method',
        child: CheckoutContent(
          child: ListView.separated(
            key: const ValueKey('checkout-payment-methods'),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
            itemCount: session.paymentProfile.paymentMethods.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final method = session.paymentProfile.paymentMethods[index];
              final selected =
                  method.id == session.paymentProfile.selectedPaymentMethodId;
              return _PaymentMethodTile(
                method: method,
                selected: selected,
                enabled: !isMutating,
                onTap: () async {
                  final selected = await controller.selectPaymentMethod(
                    method.id,
                  );
                  if (selected && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              );
            },
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  });
}

final class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey<String>('checkout-payment-method-semantics-${method.id}'),
    selected: selected,
    button: true,
    label: method.maskedLabel,
    child: Material(
      key: ValueKey<String>('checkout-payment-method-${method.id}'),
      color: selected ? AppColors.primarySurface : AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E2E2)),
                ),
                child: Icon(
                  Icons.credit_card,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  method.maskedLabel,
                  style: checkoutHeading(size: 15),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : const Color(0xFF9A9A9A),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
