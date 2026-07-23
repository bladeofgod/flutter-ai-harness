import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../controllers/checkout_controller.dart';
import '../routes.dart';
import '../widgets/checkout_components.dart';

final class CheckoutPage extends StatelessWidget {
  const CheckoutPage({required this.controller, super.key});

  final CheckoutController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = controller.viewState;
    if (state case CheckoutReady(:final session, :final isMutating)) {
      return CheckoutPageScaffold(
        title: 'Payment',
        bottomAction: CheckoutPrimaryButton(
          key: const ValueKey('checkout-pay'),
          label: 'Pay ${session.total.format()}',
          icon: Icons.lock_outline,
          onPressed:
              isMutating ||
                  session.paymentProfile.selectedAddress == null ||
                  session.paymentProfile.selectedPaymentMethod == null
              ? null
              : () {
                  unawaited(context.push(checkoutResultRoutePath));
                  controller.payFromUi();
                },
        ),
        child: CheckoutContent(
          child: ListView(
            key: const ValueKey('checkout-scroll'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _AddressSummary(
                address: session.paymentProfile.selectedAddress,
                onTap: () => context.push(checkoutAddressRoutePath),
              ),
              const SizedBox(height: 18),
              _VoucherSummary(
                voucher: session.voucher,
                discount: session.discount,
                isMutating: isMutating,
                onEdit: () => context.push(checkoutVoucherRoutePath),
                onRemove: controller.clearVoucher,
              ),
              const SizedBox(height: 18),
              _PaymentMethodSummary(
                paymentMethod: session.paymentProfile.selectedPaymentMethod,
                onTap: () => context.push(checkoutPaymentMethodRoutePath),
              ),
              const SizedBox(height: 22),
              _AmountSummary(session: session),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  });
}

final class _AddressSummary extends StatelessWidget {
  const _AddressSummary({required this.address, required this.onTap});

  final ShippingAddress? address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CheckoutSectionCard(
    key: const ValueKey('checkout-address-summary'),
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 20,
          backgroundColor: AppColors.primarySurface,
          child: Icon(Icons.local_shipping_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shipping Address', style: checkoutHeading(size: 15)),
              const SizedBox(height: 4),
              Text(
                address?.recipientName ?? 'Add a shipping address',
                style: checkoutBody(size: 12, weight: FontWeight.w700),
              ),
              if (address != null) ...[
                const SizedBox(height: 2),
                Text(
                  address!.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: checkoutBody(
                    size: 11,
                    color: const Color(0xFF777777),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: AppColors.primary),
      ],
    ),
  );
}

final class _VoucherSummary extends StatelessWidget {
  const _VoucherSummary({
    required this.voucher,
    required this.discount,
    required this.isMutating,
    required this.onEdit,
    required this.onRemove,
  });

  final Voucher? voucher;
  final Money discount;
  final bool isMutating;
  final VoidCallback onEdit;
  final Future<bool> Function() onRemove;

  @override
  Widget build(BuildContext context) => CheckoutSectionCard(
    key: const ValueKey('checkout-voucher-summary'),
    onTap: isMutating ? null : onEdit,
    child: Row(
      children: [
        const Icon(
          Icons.confirmation_number_outlined,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                voucher == null ? 'Add voucher' : voucher!.title,
                style: checkoutHeading(size: 15),
              ),
              if (voucher != null)
                Text(
                  '${voucher!.code}  -${discount.format()}',
                  style: checkoutBody(size: 12, color: AppColors.success),
                ),
            ],
          ),
        ),
        if (voucher == null)
          const Icon(Icons.chevron_right, color: AppColors.primary)
        else
          IconButton(
            key: const ValueKey('checkout-remove-voucher'),
            tooltip: 'Remove voucher',
            onPressed: isMutating ? null : () => onRemove(),
            icon: const Icon(Icons.close, size: 18),
          ),
      ],
    ),
  );
}

final class _PaymentMethodSummary extends StatelessWidget {
  const _PaymentMethodSummary({
    required this.paymentMethod,
    required this.onTap,
  });

  final PaymentMethod? paymentMethod;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CheckoutSectionCard(
    key: const ValueKey('checkout-payment-method-summary'),
    onTap: onTap,
    child: Row(
      children: [
        const Icon(Icons.credit_card, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            paymentMethod?.maskedLabel ?? 'Choose payment method',
            style: checkoutHeading(size: 15),
          ),
        ),
        const Icon(Icons.chevron_right, color: AppColors.primary),
      ],
    ),
  );
}

final class _AmountSummary extends StatelessWidget {
  const _AmountSummary({required this.session});

  final CheckoutSession session;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Order total ${session.total.format()}',
    child: Column(
      children: [
        _AmountRow(label: 'Subtotal', amount: session.subtotal),
        if (session.discount.minorUnits > 0)
          _AmountRow(
            label: 'Voucher',
            amount: session.discount,
            prefix: '-',
            color: AppColors.success,
          ),
        const Divider(height: 28),
        _AmountRow(label: 'Total', amount: session.total, emphasized: true),
      ],
    ),
  );
}

final class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.prefix = '',
    this.color = AppColors.textPrimary,
    this.emphasized = false,
  });

  final String label;
  final Money amount;
  final String prefix;
  final Color color;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: checkoutBody(
              size: emphasized ? 17 : 14,
              weight: emphasized ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          '$prefix${amount.format()}',
          style: checkoutHeading(size: emphasized ? 20 : 15, color: color),
        ),
      ],
    ),
  );
}
