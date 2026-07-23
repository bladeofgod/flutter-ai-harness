import 'package:app_data/support.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/support_chat_api.dart';
import 'controllers/support_chat_controller.dart';
import 'pages/support_chat_page.dart';

const supportRoutePath = '/support';

typedef SupportVoucherNavigation =
    void Function(BuildContext context, Voucher voucher);

List<RouteBase> buildSupportRoutes({
  required SupportChatApi supportChatApi,
  required SupportVoucherNavigation onOpenVoucher,
  SupportTransitionDelay? transitionDelay,
}) => <RouteBase>[
  GoRoute(
    path: supportRoutePath,
    builder: (context, state) => SupportChatPage(
      controller: SupportChatController(
        supportChatApi: supportChatApi,
        transitionDelay:
            transitionDelay ?? (duration) => Future<void>.delayed(duration),
      ),
      onOpenVoucher: (voucher) => onOpenVoucher(context, voucher),
      onDone: () => context.pop(),
    ),
  ),
];
