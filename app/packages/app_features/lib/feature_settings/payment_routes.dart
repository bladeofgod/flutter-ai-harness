import 'dart:async';

import 'package:app_data/app_data.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

import '../api/settings_payment_api.dart';
import 'controllers/settings_payment_controller.dart';
import 'pages/settings_address_form_page.dart';
import 'pages/settings_addresses_page.dart';
import 'pages/settings_card_form_page.dart';
import 'pages/settings_payment_methods_page.dart';
import 'widgets/settings_components.dart';

const _settingsPaymentMethodsRoutePath = '/settings/payment-methods';
const _settingsAddressesRoutePath = '/settings/addresses';
const settingsAddPaymentMethodRoutePath = '/settings/payment-methods/add';
const settingsAddAddressRoutePath = '/settings/addresses/add';

String settingsEditPaymentMethodLocation(String methodId) =>
    '$_settingsPaymentMethodsRoutePath/${Uri.encodeComponent(methodId)}/edit';

String settingsEditAddressLocation(String addressId) =>
    '$_settingsAddressesRoutePath/${Uri.encodeComponent(addressId)}/edit';

List<RouteBase> buildSettingsPaymentAddressRoutes({
  required SettingsPaymentAddressApi api,
}) {
  final coordinator = _SettingsPaymentScopeCoordinator(api: api);
  return <RouteBase>[
    GoRoute(
      path: _settingsPaymentMethodsRoutePath,
      builder: (context, state) => _SettingsPaymentRoutePage(
        coordinator: coordinator,
        mode: const _PaymentMethodsMode(),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: 'add',
          builder: (context, state) => _SettingsPaymentRoutePage(
            coordinator: coordinator,
            mode: const _CardFormMode(),
          ),
        ),
        GoRoute(
          path: ':methodId/edit',
          builder: (context, state) => _SettingsPaymentRoutePage(
            coordinator: coordinator,
            mode: _CardFormMode(methodId: state.pathParameters['methodId']),
          ),
        ),
      ],
    ),
    GoRoute(
      path: _settingsAddressesRoutePath,
      builder: (context, state) => _SettingsPaymentRoutePage(
        coordinator: coordinator,
        mode: const _AddressesMode(),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: 'add',
          builder: (context, state) => _SettingsPaymentRoutePage(
            coordinator: coordinator,
            mode: const _AddressFormMode(),
          ),
        ),
        GoRoute(
          path: ':addressId/edit',
          builder: (context, state) => _SettingsPaymentRoutePage(
            coordinator: coordinator,
            mode: _AddressFormMode(
              addressId: state.pathParameters['addressId'],
            ),
          ),
        ),
      ],
    ),
  ];
}

sealed class _SettingsPaymentRouteMode {
  const _SettingsPaymentRouteMode();
}

final class _PaymentMethodsMode extends _SettingsPaymentRouteMode {
  const _PaymentMethodsMode();
}

final class _CardFormMode extends _SettingsPaymentRouteMode {
  const _CardFormMode({this.methodId});

  final String? methodId;
}

final class _AddressesMode extends _SettingsPaymentRouteMode {
  const _AddressesMode();
}

final class _AddressFormMode extends _SettingsPaymentRouteMode {
  const _AddressFormMode({this.addressId});

  final String? addressId;
}

final class _SettingsPaymentRoutePage extends StatefulWidget {
  const _SettingsPaymentRoutePage({
    required this.coordinator,
    required this.mode,
  });

  final _SettingsPaymentScopeCoordinator coordinator;
  final _SettingsPaymentRouteMode mode;

  @override
  State<_SettingsPaymentRoutePage> createState() =>
      _SettingsPaymentRoutePageState();
}

final class _SettingsPaymentRoutePageState
    extends State<_SettingsPaymentRoutePage> {
  late final SettingsPaymentController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.coordinator.acquire();
  }

  @override
  void dispose() {
    widget.coordinator.release(_controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    final state = _controller.viewState;
    return switch (state) {
      SettingsPaymentLoading() => const SettingsPageFrame(
        title: 'Settings',
        child: Center(
          child: CircularProgressIndicator(
            key: ValueKey('settings-payment-loading'),
          ),
        ),
      ),
      SettingsPaymentError(:final failure) => _SettingsPaymentErrorPage(
        failure: failure,
        onRetry: _controller.retryFromUi,
      ),
      SettingsPaymentReady(:final overview, :final isMutating) => _buildReady(
        context,
        overview.paymentProfile,
        overview,
        isMutating,
      ),
    };
  });

  Widget _buildReady(
    BuildContext context,
    PaymentProfileSnapshot profile,
    SettingsPaymentOverview overview,
    bool isMutating,
  ) => switch (widget.mode) {
    _PaymentMethodsMode() => SettingsPaymentMethodsPage(
      overview: overview,
      isMutating: isMutating,
      onAdd: () => unawaited(context.push(settingsAddPaymentMethodRoutePath)),
      onEdit: (methodId) =>
          unawaited(context.push(settingsEditPaymentMethodLocation(methodId))),
      onSelect: (methodId) =>
          unawaited(_controller.selectPaymentMethod(methodId)),
      onRemove: (methodId) => unawaited(
        _confirmRemoval(
          context,
          title: 'Remove this card?',
          message: 'Only the masked Demo payment method will be removed.',
          onConfirm: () => _controller.removePaymentMethod(methodId),
        ),
      ),
    ),
    _CardFormMode(:final methodId) =>
      methodId == null
          ? SettingsCardFormPage(
              controller: _controller,
              existingMethod: null,
              onSaved: context.pop,
            )
          : switch (_paymentMethod(profile.paymentMethods, methodId)) {
              final PaymentMethod method => SettingsCardFormPage(
                controller: _controller,
                existingMethod: method,
                onSaved: context.pop,
              ),
              null => const _MissingSettingsRecordPage(),
            },
    _AddressesMode() => SettingsAddressesPage(
      profile: profile,
      isMutating: isMutating,
      onAdd: () => unawaited(context.push(settingsAddAddressRoutePath)),
      onEdit: (addressId) =>
          unawaited(context.push(settingsEditAddressLocation(addressId))),
      onSelect: (addressId) => unawaited(_controller.selectAddress(addressId)),
      onRemove: (addressId) => unawaited(
        _confirmRemoval(
          context,
          title: 'Remove this address?',
          message: 'Checkout will immediately use the remaining selection.',
          onConfirm: () => _controller.removeAddress(addressId),
        ),
      ),
    ),
    _AddressFormMode(:final addressId) =>
      addressId == null
          ? SettingsAddressFormPage(
              controller: _controller,
              existingAddress: null,
              onSaved: context.pop,
            )
          : switch (_address(profile.addresses, addressId)) {
              final ShippingAddress address => SettingsAddressFormPage(
                controller: _controller,
                existingAddress: address,
                onSaved: context.pop,
              ),
              null => const _MissingSettingsRecordPage(),
            },
  };
}

final class _SettingsPaymentScopeCoordinator {
  _SettingsPaymentScopeCoordinator({required this.api});

  final SettingsPaymentAddressApi api;
  SettingsPaymentController? _controller;
  int _leases = 0;

  SettingsPaymentController acquire() {
    final controller = _controller ?? SettingsPaymentController(api: api);
    if (_controller == null) {
      _controller = controller;
      controller.onInit();
    }
    _leases += 1;
    return controller;
  }

  void release(SettingsPaymentController controller) {
    assert(identical(controller, _controller));
    _leases -= 1;
    assert(_leases >= 0);
    if (_leases == 0) {
      controller.onDelete();
      _controller = null;
    }
  }
}

final class _MissingSettingsRecordPage extends StatelessWidget {
  const _MissingSettingsRecordPage();

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: 'Settings',
    child: Center(
      child: Text('Item not found', style: settingsTitleStyle(size: 19)),
    ),
  );
}

final class _SettingsPaymentErrorPage extends StatelessWidget {
  const _SettingsPaymentErrorPage({
    required this.failure,
    required this.onRetry,
  });

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: 'Settings',
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 52),
            const SizedBox(height: 14),
            Text(
              'Unable to load payment settings',
              style: settingsTitleStyle(),
            ),
            const SizedBox(height: 8),
            Text(
              'Your saved Demo data has not changed.',
              textAlign: TextAlign.center,
              style: settingsBodyStyle(color: const Color(0xFF707070)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const ValueKey('settings-payment-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _confirmRemoval(
  BuildContext context, {
  required String title,
  required String message,
  required Future<bool> Function() onConfirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('settings-payment-remove-dialog'),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          key: const ValueKey('settings-payment-remove-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('settings-payment-remove-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await onConfirm();
  }
}

PaymentMethod? _paymentMethod(List<PaymentMethod> methods, String methodId) {
  for (final method in methods) {
    if (method.id == methodId) {
      return method;
    }
  }
  return null;
}

ShippingAddress? _address(List<ShippingAddress> addresses, String addressId) {
  for (final address in addresses) {
    if (address.id == addressId) {
      return address;
    }
  }
  return null;
}
