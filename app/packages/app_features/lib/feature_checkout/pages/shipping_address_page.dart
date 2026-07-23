import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../controllers/checkout_controller.dart';
import '../widgets/checkout_components.dart';

final class CheckoutShippingAddressPage extends StatefulWidget {
  const CheckoutShippingAddressPage({required this.controller, super.key});

  final CheckoutController controller;

  @override
  State<CheckoutShippingAddressPage> createState() =>
      _CheckoutShippingAddressPageState();
}

final class _CheckoutShippingAddressPageState
    extends State<CheckoutShippingAddressPage> {
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
    final address = widget.controller.session?.paymentProfile.selectedAddress;
    _name = TextEditingController(text: address?.recipientName ?? '');
    _street = TextEditingController(text: address?.streetLine ?? '');
    _city = TextEditingController(text: address?.city ?? '');
    _region = TextEditingController(text: address?.region ?? '');
    _postalCode = TextEditingController(text: address?.postalCode ?? '');
    _country = TextEditingController(text: address?.country ?? '');
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

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    final current = widget.controller.session?.paymentProfile.selectedAddress;
    final saved = await widget.controller.saveAddress(
      ShippingAddress(
        id: current?.id ?? 'shipping-demo',
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
      Navigator.of(context).pop();
    } else {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CheckoutPageScaffold(
    title: 'Shipping Address',
    bottomAction: CheckoutPrimaryButton(
      key: const ValueKey('checkout-save-address'),
      label: _isSaving ? 'Saving...' : 'Save address',
      onPressed: _isSaving ? null : _save,
    ),
    child: CheckoutContent(
      child: Form(
        key: _formKey,
        child: ListView(
          key: const ValueKey('checkout-address-form'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            28 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            _AddressField(
              key: const ValueKey('checkout-address-name'),
              label: 'Recipient name',
              controller: _name,
              textInputAction: TextInputAction.next,
            ),
            _AddressField(
              key: const ValueKey('checkout-address-street'),
              label: 'Street address',
              controller: _street,
              textInputAction: TextInputAction.next,
              maxLines: 2,
            ),
            _AddressField(
              key: const ValueKey('checkout-address-city'),
              label: 'City',
              controller: _city,
              textInputAction: TextInputAction.next,
            ),
            _AddressField(
              key: const ValueKey('checkout-address-region'),
              label: 'State / Region',
              controller: _region,
              textInputAction: TextInputAction.next,
            ),
            _AddressField(
              key: const ValueKey('checkout-address-postal'),
              label: 'Postal code',
              controller: _postalCode,
              keyboardType: TextInputType.streetAddress,
              textInputAction: TextInputAction.next,
              validator: _validatePostalCode,
            ),
            _AddressField(
              key: const ValueKey('checkout-address-country'),
              label: 'Country',
              controller: _country,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    ),
  );
}

String? _validateRequired(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;

String? _validatePostalCode(String? value) {
  final requiredError = _validateRequired(value);
  if (requiredError != null) {
    return requiredError;
  }
  return RegExp(r'^[A-Za-z0-9 -]{3,12}$').hasMatch(value!.trim())
      ? null
      : 'Enter a valid postal code';
}

final class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.label,
    required this.controller,
    required this.textInputAction,
    this.keyboardType,
    this.maxLines = 1,
    this.validator = _validateRequired,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?) validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: checkoutBody(size: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: checkoutBody(size: 13, color: const Color(0xFF777777)),
        filled: true,
        fillColor: AppColors.formBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}
