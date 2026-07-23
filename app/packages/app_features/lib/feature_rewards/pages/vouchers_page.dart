import 'package:app_data/rewards.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/rewards_controller.dart';
import '../widgets/rewards_components.dart';

final class VouchersPage extends StatelessWidget {
  const VouchersPage({
    required this.controller,
    required this.onUseVoucher,
    super.key,
  });

  final RewardsController controller;
  final ValueChanged<String> onUseVoucher;

  @override
  Widget build(BuildContext context) => GetBuilder<RewardsController>(
    init: controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (managedController) => Obx(() {
      final state = managedController.viewState;
      return switch (state) {
        RewardsLoading() => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(key: ValueKey('vouchers-loading')),
          ),
        ),
        RewardsError() => RewardsLoadError(
          onRetry: managedController.retryFromUi,
        ),
        RewardsEmpty() => const _EmptyVouchers(),
        RewardsData(:final snapshot) => _VoucherList(
          vouchers: snapshot.vouchers,
          selectedVoucherId: managedController.selectedVoucherId,
          onSelect: managedController.selectVoucher,
          onUseVoucher: onUseVoucher,
        ),
      };
    }),
  );
}

final class _EmptyVouchers extends StatelessWidget {
  const _EmptyVouchers();

  @override
  Widget build(BuildContext context) => RewardsPageScaffold(
    title: 'My Vouchers',
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_number_outlined, size: 52),
            const SizedBox(height: 12),
            Text('No vouchers yet', style: rewardsHeading(size: 20)),
            const SizedBox(height: 6),
            Text(
              'Your Demo rewards will appear here.',
              textAlign: TextAlign.center,
              style: rewardsBody(color: const Color(0xFF697386)),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _VoucherList extends StatelessWidget {
  const _VoucherList({
    required this.vouchers,
    required this.selectedVoucherId,
    required this.onSelect,
    required this.onUseVoucher,
  });

  final List<VoucherEntitlement> vouchers;
  final String? selectedVoucherId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onUseVoucher;

  @override
  Widget build(BuildContext context) => RewardsPageScaffold(
    title: 'My Vouchers',
    child: ListView.separated(
      key: const ValueKey('vouchers-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: vouchers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entitlement = vouchers[index];
        final selected = selectedVoucherId == entitlement.voucher.id;
        return _VoucherCard(
          entitlement: entitlement,
          selected: selected,
          onSelect: () => onSelect(entitlement.voucher.id),
          onUse: entitlement.isUsable
              ? () => onUseVoucher(entitlement.voucher.id)
              : null,
        );
      },
    ),
  );
}

final class _VoucherCard extends StatelessWidget {
  const _VoucherCard({
    required this.entitlement,
    required this.selected,
    required this.onSelect,
    required this.onUse,
  });

  final VoucherEntitlement entitlement;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final voucher = entitlement.voucher;
    final lifecycleLabel = voucherLifecycleLabel(entitlement.lifecycle);
    return Semantics(
      button: true,
      selected: selected,
      label: '${voucher.title}, $lifecycleLabel',
      child: Material(
        key: ValueKey<String>('voucher-${voucher.id}'),
        color: entitlement.isUsable ? Colors.white : AppColors.surfaceMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.primary : const Color(0xFFE1E5EA),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySurface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(voucher.title, style: rewardsHeading(size: 16)),
                          const SizedBox(height: 3),
                          Text(
                            voucher.code,
                            style: rewardsBody(
                              size: 13,
                              weight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LifecycleBadge(
                      label: lifecycleLabel,
                      emphasized:
                          entitlement.lifecycle ==
                          VoucherLifecycle.expiringSoon,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Expires ${voucherExpiryLabel(entitlement.expiresAt)}',
                  style: rewardsBody(size: 12, color: const Color(0xFF697386)),
                ),
                if (selected) ...[
                  const Divider(height: 24),
                  Text(
                    'Minimum spend ${voucher.minimumSpend.format()}',
                    style: rewardsBody(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: ValueKey<String>('voucher-use-${voucher.id}'),
                    onPressed: onUse,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: Text(onUse == null ? 'Already used' : 'Use voucher'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _LifecycleBadge extends StatelessWidget {
  const _LifecycleBadge({required this.label, required this.emphasized});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 92),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFFFF4D8) : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: rewardsBody(
          size: 11,
          weight: FontWeight.w700,
          color: emphasized ? const Color(0xFF8A5B00) : AppColors.textPrimary,
        ),
      ),
    ),
  );
}
