import 'package:app_data/rewards.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

TextStyle rewardsHeading({
  required double size,
  Color color = AppColors.textPrimary,
  FontWeight weight = FontWeight.w700,
}) => TextStyle(
  fontFamily: AppFonts.raleway,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
);

TextStyle rewardsBody({
  double size = 14,
  Color color = AppColors.textPrimary,
  FontWeight weight = FontWeight.w400,
}) => TextStyle(
  fontFamily: AppFonts.nunitoSans,
  package: AppFonts.package,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: 0,
);

String rewardTierLabel(RewardTier tier) => switch (tier) {
  RewardTier.silver => 'Silver',
  RewardTier.gold => 'Gold',
  RewardTier.platinum => 'Platinum',
};

String voucherLifecycleLabel(VoucherLifecycle lifecycle) => switch (lifecycle) {
  VoucherLifecycle.available => 'Available',
  VoucherLifecycle.expiringSoon => 'Expires soon',
  VoucherLifecycle.redeemed => 'Redeemed',
  VoucherLifecycle.expired => 'Expired',
};

String voucherExpiryLabel(DateTime value) {
  final utc = value.toUtc();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[utc.month - 1]} ${utc.day}, ${utc.year}';
}

final class RewardsPageScaffold extends StatelessWidget {
  const RewardsPageScaffold({
    required this.title,
    required this.child,
    this.showBack = true,
    super.key,
  });

  final String title;
  final Widget child;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: showBack,
      title: Text(title, style: rewardsHeading(size: 22)),
    ),
    body: SafeArea(top: false, child: child),
  );
}

final class RewardsLoadError extends StatelessWidget {
  const RewardsLoadError({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => RewardsPageScaffold(
    title: 'My Rewards',
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.card_giftcard_outlined, size: 48),
            const SizedBox(height: 14),
            Text('Rewards are unavailable', style: rewardsHeading(size: 20)),
            const SizedBox(height: 8),
            Text(
              'Retry the local Demo rewards.',
              textAlign: TextAlign.center,
              style: rewardsBody(color: const Color(0xFF697386)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('rewards-retry'),
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
