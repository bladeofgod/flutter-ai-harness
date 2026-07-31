import 'package:app_data/support.dart';
import 'package:app_media/app_media.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/support_chat_api.dart';
import '../api/support_media_picker.dart';
import 'controllers/support_chat_controller.dart';
import 'pages/support_chat_page.dart';

const supportRoutePath = '/support';
const supportMediaPreviewRoutePath = '/support/media-preview';
const supportMediaPreviewRouteName = 'support-media-preview';

final class SupportMediaPreviewRouteData {
  const SupportMediaPreviewRouteData(this.content);

  final SupportMediaContent content;

  @override
  String toString() => 'SupportMediaPreviewRouteData(<redacted>)';
}

typedef SupportVoucherNavigation =
    void Function(BuildContext context, Voucher voucher);

List<RouteBase> buildSupportRoutes({
  required SupportChatApi supportChatApi,
  required SupportMediaPicker supportMediaPicker,
  required MediaResourceStore mediaResourceStore,
  required SupportVoucherNavigation onOpenVoucher,
  SupportTransitionDelay? transitionDelay,
}) => <RouteBase>[
  GoRoute(
    path: supportRoutePath,
    builder: (context, state) => SupportChatPage(
      mediaResourceStore: mediaResourceStore,
      createController: () => SupportChatController(
        supportChatApi: supportChatApi,
        supportMediaPicker: supportMediaPicker,
        transitionDelay:
            transitionDelay ?? (duration) => Future<void>.delayed(duration),
      ),
      onOpenVoucher: (voucher) => onOpenVoucher(context, voucher),
      onOpenMedia: (content) => context.pushNamed(
        supportMediaPreviewRouteName,
        extra: SupportMediaPreviewRouteData(content),
      ),
      onDone: () => context.pop(),
    ),
  ),
  GoRoute(
    path: supportMediaPreviewRoutePath,
    name: supportMediaPreviewRouteName,
    builder: (context, state) {
      final extra = state.extra;
      if (extra is! SupportMediaPreviewRouteData) {
        return _MissingSupportMediaPreview(
          onClose: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(supportRoutePath);
            }
          },
        );
      }
      return MediaPreviewPage(
        resourceId: extra.content.resourceId,
        store: mediaResourceStore,
        onClose: () => context.pop(),
      );
    },
  ),
];

final class _MissingSupportMediaPreview extends StatelessWidget {
  const _MissingSupportMediaPreview({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: Semantics(
            label: 'Media preview unavailable',
            child: Icon(Icons.error_outline, color: Colors.white, size: 48),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: 'Close preview',
              onPressed: onClose,
              color: Colors.white,
              icon: const Icon(Icons.close),
            ),
          ),
        ),
      ],
    ),
  );
}
