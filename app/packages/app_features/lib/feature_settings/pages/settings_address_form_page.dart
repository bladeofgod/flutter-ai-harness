import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../controllers/settings_payment_controller.dart';
import '../widgets/settings_components.dart';
import '../widgets/settings_payment_components.dart';

final class SettingsAddressFormPage extends StatefulWidget {
  const SettingsAddressFormPage({
    required this.controller,
    required this.existingAddress,
    required this.onSaved,
    super.key,
  });

  final SettingsPaymentController controller;
  final ShippingAddress? existingAddress;
  final VoidCallback onSaved;

  @override
  State<SettingsAddressFormPage> createState() =>
      _SettingsAddressFormPageState();
}

final class _SettingsAddressFormPageState
    extends State<SettingsAddressFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _street;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _postalCode;
  late final TextEditingController _country;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final address = widget.existingAddress;
    _name = TextEditingController(text: address?.recipientName);
    _street = TextEditingController(text: address?.streetLine);
    _city = TextEditingController(text: address?.city);
    _region = TextEditingController(text: address?.region);
    _postalCode = TextEditingController(text: address?.postalCode);
    _country = TextEditingController(text: address?.country);
  }

  @override
  void dispose() {
    _name.dispose();
    _street.dispose();
    _city.dispose();
    _region.dispose();
    _postalCode.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: widget.existingAddress == null ? 'Add Address' : 'Edit Address',
    bottom: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
          child: SettingsPaymentPrimaryButton(
            key: const ValueKey('settings-address-save'),
            label: _isSaving ? 'Saving...' : 'Save address',
            onPressed: _isSaving ? null : _save,
          ),
        ),
      ),
    ),
    child: Form(
      key: _formKey,
      child: ListView(
        key: const ValueKey('settings-address-form'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          28 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          _AddressField(
            keyValue: 'settings-address-name',
            label: 'Recipient name',
            controller: _name,
            textInputAction: TextInputAction.next,
          ),
          _AddressField(
            keyValue: 'settings-address-street',
            label: 'Street address',
            controller: _street,
            textInputAction: TextInputAction.next,
            maxLines: 2,
          ),
          _AddressField(
            keyValue: 'settings-address-city',
            label: 'City',
            controller: _city,
            textInputAction: TextInputAction.next,
          ),
          _AddressField(
            keyValue: 'settings-address-region',
            label: 'State / Region',
            controller: _region,
            textInputAction: TextInputAction.next,
          ),
          _AddressField(
            keyValue: 'settings-address-postal',
            label: 'Postal code',
            controller: _postalCode,
            textInputAction: TextInputAction.next,
            validator: (value) =>
                RegExp(r'^[A-Za-z0-9 -]{3,12}$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter a valid postal code',
          ),
          _AddressField(
            keyValue: 'settings-address-country',
            label: 'Country',
            controller: _country,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSaving = true);
    final saved = await widget.controller.saveAddress(
      ShippingAddress(
        id: widget.existingAddress?.id ?? widget.controller.nextAddressId(),
        recipientName: _name.text,
        streetLine: _street.text,
        city: _city.text,
        region: _region.text,
        postalCode: _postalCode.text,
        country: _country.text,
      ),
    );
    if (!mounted) {
      return;
    }
    if (saved) {
      widget.onSaved();
    } else {
      setState(() => _isSaving = false);
    }
  }
}

final class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.keyValue,
    required this.label,
    required this.controller,
    required this.textInputAction,
    this.maxLines = 1,
    this.validator,
    this.onSubmitted,
  });

  final String keyValue;
  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final int maxLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey<String>(keyValue),
      controller: controller,
      textInputAction: textInputAction,
      maxLines: maxLines,
      validator: validator ?? _required,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.formBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;
