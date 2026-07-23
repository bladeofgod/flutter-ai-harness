import 'package:app_data/rewards.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/rewards_controller.dart';
import '../widgets/rewards_components.dart';

final class RewardsPage extends StatelessWidget {
  const RewardsPage({
    required this.controller,
    required this.onOpenVouchers,
    super.key,
  });

  final RewardsController controller;
  final VoidCallback onOpenVouchers;

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
            child: CircularProgressIndicator(key: ValueKey('rewards-loading')),
          ),
        ),
        RewardsError() => RewardsLoadError(
          onRetry: managedController.retryFromUi,
        ),
        RewardsEmpty(:final balance, :final progress) => _RewardsContent(
          balance: balance,
          progress: progress,
          voucherCount: 0,
          expiringVoucher: null,
          isConsumingReminder: false,
          onOpenVouchers: onOpenVouchers,
          onDismissReminder: null,
        ),
        RewardsData(:final snapshot) => _RewardsContent(
          balance: snapshot.balance,
          progress: snapshot.progress,
          voucherCount: snapshot.summary.usableVoucherCount,
          expiringVoucher: snapshot.summary.expiringVoucher,
          isConsumingReminder: managedController.isConsumingReminder,
          onOpenVouchers: onOpenVouchers,
          onDismissReminder: managedController.consumeReminderFromUi,
        ),
      };
    }),
  );
}

final class _RewardsContent extends StatelessWidget {
  const _RewardsContent({
    required this.balance,
    required this.progress,
    required this.voucherCount,
    required this.expiringVoucher,
    required this.isConsumingReminder,
    required this.onOpenVouchers,
    required this.onDismissReminder,
  });

  final RewardBalance balance;
  final RewardProgress progress;
  final int voucherCount;
  final VoucherEntitlement? expiringVoucher;
  final bool isConsumingReminder;
  final VoidCallback onOpenVouchers;
  final ValueChanged<String>? onDismissReminder;

  @override
  Widget build(BuildContext context) => RewardsPageScaffold(
    title: 'My Rewards',
    child: CustomScrollView(
      key: const ValueKey('rewards-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          sliver: SliverList.list(
            children: [
              _BalanceCard(balance: balance, tier: progress.currentTier),
              const SizedBox(height: 18),
              _ProgressCard(progress: progress),
              if (expiringVoucher case final voucher?) ...[
                const SizedBox(height: 18),
                _ReminderCard(
                  entitlement: voucher,
                  isDismissing: isConsumingReminder,
                  onOpen: onOpenVouchers,
                  onDismiss: onDismissReminder == null
                      ? null
                      : () => onDismissReminder!(voucher.voucher.id),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text('My vouchers', style: rewardsHeading(size: 20)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$voucherCount available',
                      style: rewardsBody(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('rewards-open-vouchers'),
                onPressed: onOpenVouchers,
                icon: const Icon(Icons.confirmation_number_outlined),
                label: const Text('View all vouchers'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.tier});

  final RewardBalance balance;
  final RewardTier tier;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${balance.availablePoints} reward points, ${rewardTierLabel(tier)} tier',
    container: true,
    child: Container(
      key: const ValueKey('rewards-balance'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rewardTierLabel(tier),
            style: rewardsBody(color: Colors.white, weight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            '${balance.availablePoints}',
            style: rewardsHeading(size: 38, color: Colors.white),
          ),
          Text('available points', style: rewardsBody(color: Colors.white)),
        ],
      ),
    ),
  );
}

final class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final RewardProgress progress;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('rewards-progress'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rewards progress', style: rewardsHeading(size: 18)),
        const SizedBox(height: 8),
        Text(
          '${progress.remainingPoints} points to ${rewardTierLabel(progress.nextTier)}',
          style: rewardsBody(color: const Color(0xFF697386)),
        ),
        const SizedBox(height: 14),
        Semantics(
          label:
              '${progress.pointsEarned} of ${progress.pointsRequired} points',
          value: '${(progress.fraction * 100).round()} percent',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress.fraction,
              backgroundColor: AppColors.primarySurface,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    ),
  );
}

final class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.entitlement,
    required this.isDismissing,
    required this.onOpen,
    required this.onDismiss,
  });

  final VoucherEntitlement entitlement;
  final bool isDismissing;
  final VoidCallback onOpen;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('rewards-voucher-reminder'),
    color: const Color(0xFFFFF4D8),
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.schedule, color: Color(0xFF8A5B00)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Voucher expires soon', style: rewardsHeading(size: 16)),
                  const SizedBox(height: 3),
                  Text(
                    '${entitlement.voucher.title} · ${voucherExpiryLabel(entitlement.expiresAt)}',
                    style: rewardsBody(size: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('rewards-dismiss-reminder'),
              tooltip: 'Dismiss voucher reminder',
              onPressed: isDismissing ? null : onDismiss,
              icon: const Icon(Icons.close, size: 20),
            ),
          ],
        ),
      ),
    ),
  );
}
