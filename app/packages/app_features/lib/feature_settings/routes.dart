import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../api/current_user_provider.dart';
import '../api/settings_api.dart';
import 'controllers/settings_controller.dart';
import 'pages/settings_about_page.dart';
import 'pages/settings_page.dart';
import 'pages/settings_preference_page.dart';
import 'pages/settings_profile_page.dart';

export 'payment_routes.dart'
    show
        buildSettingsPaymentAddressRoutes,
        settingsAddAddressRoutePath,
        settingsAddPaymentMethodRoutePath,
        settingsEditAddressLocation,
        settingsEditPaymentMethodLocation;

const settingsRoutePath = '/settings';
const settingsProfileRoutePath = '/settings/profile';
const settingsCountryRoutePath = '/settings/country';
const settingsLanguageRoutePath = '/settings/language';
const settingsCurrencyRoutePath = '/settings/currency';
const settingsSizeTypeRoutePath = '/settings/size-type';
const settingsAboutRoutePath = '/settings/about';

/// 由后续 Payment/Address 任务实现的公开导航目标，本卡不注册页面。
const settingsPaymentMethodsRoutePath = '/settings/payment-methods';
const settingsAddressesRoutePath = '/settings/addresses';

typedef SettingsTargetNavigation = void Function(BuildContext context);

List<RouteBase> buildSettingsRoutes({
  required SettingsApi settingsApi,
  required CurrentUserProvider currentUserProvider,
  required SettingsUserUpdated onUserUpdated,
  required VoidCallback onDeleteAccount,
  SettingsTargetNavigation? openPaymentMethods,
  SettingsTargetNavigation? openAddresses,
}) {
  SettingsController controller() => SettingsController(
    settingsApi: settingsApi,
    currentUserProvider: currentUserProvider,
    onUserUpdated: onUserUpdated,
    onDeleteAccount: onDeleteAccount,
  );

  return <RouteBase>[
    GoRoute(
      path: settingsRoutePath,
      builder: (context, state) {
        final rootController = controller();
        void openAndRefresh(String location) {
          unawaited(
            context.push<void>(location).then((_) => rootController.load()),
          );
        }

        return SettingsPage(
          controller: rootController,
          onOpenProfile: () => openAndRefresh(settingsProfileRoutePath),
          onOpenCountry: () => openAndRefresh(settingsCountryRoutePath),
          onOpenLanguage: () => openAndRefresh(settingsLanguageRoutePath),
          onOpenCurrency: () => openAndRefresh(settingsCurrencyRoutePath),
          onOpenSizeType: () => openAndRefresh(settingsSizeTypeRoutePath),
          onOpenAbout: () => openAndRefresh(settingsAboutRoutePath),
          onOpenPaymentMethods: openPaymentMethods == null
              ? null
              : () => openPaymentMethods(context),
          onOpenAddresses: openAddresses == null
              ? null
              : () => openAddresses(context),
        );
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'profile',
          builder: (context, state) =>
              SettingsProfilePage(controller: controller()),
        ),
        GoRoute(
          path: 'country',
          builder: (context, state) => SettingsPreferencePage(
            controller: controller(),
            kind: SettingsPreferenceKind.country,
          ),
        ),
        GoRoute(
          path: 'language',
          builder: (context, state) => SettingsPreferencePage(
            controller: controller(),
            kind: SettingsPreferenceKind.language,
          ),
        ),
        GoRoute(
          path: 'currency',
          builder: (context, state) => SettingsPreferencePage(
            controller: controller(),
            kind: SettingsPreferenceKind.currency,
          ),
        ),
        GoRoute(
          path: 'size-type',
          builder: (context, state) => SettingsPreferencePage(
            controller: controller(),
            kind: SettingsPreferenceKind.sizeType,
          ),
        ),
        GoRoute(
          path: 'about',
          builder: (context, state) => const SettingsAboutPage(),
        ),
      ],
    ),
  ];
}
