import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/settings_components.dart';
import '../widgets/settings_payment_components.dart';

final class SettingsAddressesPage extends StatelessWidget {
  const SettingsAddressesPage({
    required this.profile,
    required this.isMutating,
    required this.onAdd,
    required this.onEdit,
    required this.onSelect,
    required this.onRemove,
    super.key,
  });

  final PaymentProfileSnapshot profile;
  final bool isMutating;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: 'Shipping Address',
    bottom: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
          child: SettingsPaymentPrimaryButton(
            key: const ValueKey('settings-address-add'),
            label: 'Add new address',
            icon: Icons.add_location_alt_outlined,
            onPressed: isMutating ? null : onAdd,
          ),
        ),
      ),
    ),
    child: profile.addresses.isEmpty
        ? const SettingsPaymentEmptyState(
            icon: Icons.location_off_outlined,
            title: 'No shipping addresses',
            message: 'Add an address to use it during checkout.',
          )
        : ListView.separated(
            key: const ValueKey('settings-address-list'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            itemCount: profile.addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final address = profile.addresses[index];
              return _AddressCard(
                address: address,
                selected: address.id == profile.selectedAddressId,
                enabled: !isMutating,
                onSelect: () => onSelect(address.id),
                onEdit: () => onEdit(address.id),
                onRemove: () => onRemove(address.id),
              );
            },
          ),
  );
}

final class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onEdit,
    required this.onRemove,
  });

  final ShippingAddress address;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SettingsPaymentSectionCard(
    key: ValueKey<String>('settings-address-${address.id}'),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          selected ? Icons.home_rounded : Icons.location_on_outlined,
          color: selected ? AppColors.primary : AppColors.textPrimary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            key: ValueKey<String>('settings-address-select-${address.id}'),
            onTap: enabled ? onSelect : null,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.recipientName,
                    style: settingsTitleStyle(size: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    address.summary,
                    style: settingsBodyStyle(color: const Color(0xFF686868)),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          key: ValueKey<String>('settings-address-edit-${address.id}'),
          tooltip: 'Edit address',
          onPressed: enabled ? onEdit : null,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: ValueKey<String>('settings-address-remove-${address.id}'),
          tooltip: 'Remove address',
          onPressed: enabled ? onRemove : null,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}
