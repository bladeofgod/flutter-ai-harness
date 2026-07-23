import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/rewards_api.dart';
import 'controllers/rewards_controller.dart';
import 'pages/rewards_page.dart';
import 'pages/vouchers_page.dart';

const rewardsRoutePath = '/rewards';
const vouchersRoutePath = '/vouchers';

typedef RewardsCheckoutNavigation =
    void Function(BuildContext context, String voucherId);

List<RouteBase> buildRewardsRoutes({
  required RewardsApi rewardsApi,
  required RewardsCheckoutNavigation onUseVoucher,
}) => <RouteBase>[
  GoRoute(
    path: rewardsRoutePath,
    builder: (context, state) => RewardsPage(
      controller: RewardsController(rewardsApi: rewardsApi),
      onOpenVouchers: () => context.push(vouchersRoutePath),
    ),
  ),
  GoRoute(
    path: vouchersRoutePath,
    builder: (context, state) => VouchersPage(
      controller: RewardsController(rewardsApi: rewardsApi),
      onUseVoucher: (voucherId) => onUseVoucher(context, voucherId),
    ),
  ),
];
