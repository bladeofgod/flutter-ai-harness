import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../widgets/settings_components.dart';
import '../widgets/settings_payment_components.dart';

enum SettingsPaymentTab { cards, history }

final class SettingsPaymentMethodsPage extends StatefulWidget {
  const SettingsPaymentMethodsPage({
    required this.overview,
    required this.isMutating,
    required this.onAdd,
    required this.onEdit,
    required this.onSelect,
    required this.onRemove,
    super.key,
  });

  final SettingsPaymentOverview overview;
  final bool isMutating;
  final VoidCallback onAdd;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  @override
  State<SettingsPaymentMethodsPage> createState() =>
      _SettingsPaymentMethodsPageState();
}

final class _SettingsPaymentMethodsPageState
    extends State<SettingsPaymentMethodsPage> {
  SettingsPaymentTab _tab = SettingsPaymentTab.cards;

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: 'Payment',
    bottom: _tab == SettingsPaymentTab.cards
        ? SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: settingsContentMaxWidth,
                ),
                child: SettingsPaymentPrimaryButton(
                  key: const ValueKey('settings-payment-add'),
                  label: 'Add new card',
                  icon: Icons.add_card_rounded,
                  onPressed: widget.isMutating ? null : widget.onAdd,
                ),
              ),
            ),
          )
        : null,
    child: CustomScrollView(
      key: const ValueKey('settings-payment-scroll'),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          sliver: SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: settingsContentMaxWidth,
              ),
              child: SegmentedButton<SettingsPaymentTab>(
                segments: const <ButtonSegment<SettingsPaymentTab>>[
                  ButtonSegment<SettingsPaymentTab>(
                    value: SettingsPaymentTab.cards,
                    icon: Icon(Icons.credit_card_rounded),
                    label: Text('Cards'),
                  ),
                  ButtonSegment<SettingsPaymentTab>(
                    value: SettingsPaymentTab.history,
                    icon: Icon(Icons.receipt_long_rounded),
                    label: Text('History'),
                  ),
                ],
                selected: <SettingsPaymentTab>{_tab},
                onSelectionChanged: (selection) =>
                    setState(() => _tab = selection.single),
              ),
            ),
          ),
        ),
        if (_tab == SettingsPaymentTab.cards)
          _cardsSliver(widget.overview.paymentProfile)
        else
          _historySliver(widget.overview.receipts),
      ],
    ),
  );

  Widget _cardsSliver(PaymentProfileSnapshot profile) {
    if (profile.paymentMethods.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: SettingsPaymentEmptyState(
          icon: Icons.credit_card_off_rounded,
          title: 'No saved cards',
          message: 'Add a Demo card to use it during checkout.',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      sliver: SliverList.separated(
        itemCount: profile.paymentMethods.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final method = profile.paymentMethods[index];
          return _PaymentMethodCard(
            method: method,
            selected: method.id == profile.selectedPaymentMethodId,
            enabled: !widget.isMutating,
            onSelect: () => widget.onSelect(method.id),
            onEdit: () => widget.onEdit(method.id),
            onRemove: () => widget.onRemove(method.id),
          );
        },
      ),
    );
  }

  Widget _historySliver(List<CheckoutReceipt> receipts) {
    if (receipts.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: SettingsPaymentEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No payment history',
          message: 'Successful Demo checkouts will appear here.',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      sliver: SliverList.separated(
        itemCount: receipts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _ReceiptCard(receipt: receipts[index]),
      ),
    );
  }
}

final class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onEdit,
    required this.onRemove,
  });

  final PaymentMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Semantics(
    label: method.maskedLabel,
    selected: selected,
    child: SettingsPaymentSectionCard(
      key: ValueKey<String>('settings-payment-method-${method.id}'),
      child: Row(
        children: [
          Icon(
            Icons.credit_card_rounded,
            color: selected ? AppColors.primary : AppColors.textPrimary,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: InkWell(
              key: ValueKey<String>('settings-payment-select-${method.id}'),
              onTap: enabled ? onSelect : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(method.brand, style: settingsTitleStyle(size: 16)),
                    const SizedBox(height: 3),
                    Text(
                      '•••• ${method.lastFour}',
                      style: settingsBodyStyle(color: const Color(0xFF686868)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey<String>('settings-payment-edit-${method.id}'),
            tooltip: 'Edit card',
            onPressed: enabled ? onEdit : null,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey<String>('settings-payment-remove-${method.id}'),
            tooltip: 'Remove card',
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: selected ? AppColors.primary : const Color(0xFF9A9A9A),
          ),
        ],
      ),
    ),
  );
}

final class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.receipt});

  final CheckoutReceipt receipt;

  @override
  Widget build(BuildContext context) => SettingsPaymentSectionCard(
    key: ValueKey<String>('settings-payment-receipt-${receipt.id}'),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: AppColors.primarySurface,
          foregroundColor: AppColors.primary,
          child: Icon(Icons.check_rounded),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settingsPaymentMoneyLabel(
                  receipt.amount.minorUnits,
                  receipt.amount.currency.code,
                ),
                style: settingsTitleStyle(size: 16),
              ),
              const SizedBox(height: 4),
              Text(
                receipt.maskedPaymentLabel,
                style: settingsBodyStyle(color: const Color(0xFF686868)),
              ),
            ],
          ),
        ),
        Text(
          '${receipt.issuedAt.toLocal().month}/${receipt.issuedAt.toLocal().day}',
          style: settingsBodyStyle(color: const Color(0xFF777777)),
        ),
      ],
    ),
  );
}
