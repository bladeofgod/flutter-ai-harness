import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/settings_payment_controller.dart';
import '../widgets/settings_components.dart';
import '../widgets/settings_payment_components.dart';

final class SettingsCardFormPage extends StatefulWidget {
  const SettingsCardFormPage({
    required this.controller,
    required this.existingMethod,
    required this.onSaved,
    super.key,
  });

  final SettingsPaymentController controller;
  final PaymentMethod? existingMethod;
  final VoidCallback onSaved;

  @override
  State<SettingsCardFormPage> createState() => _SettingsCardFormPageState();
}

final class _SettingsCardFormPageState extends State<SettingsCardFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _cardholder = TextEditingController();
  final _cardNumber = TextEditingController();
  final _expiry = TextEditingController();
  final _securityCode = TextEditingController();
  bool _isSaving = false;

  bool get _isEditing => widget.existingMethod != null;

  @override
  void dispose() {
    _clearSensitiveInput();
    _cardholder.dispose();
    _cardNumber.dispose();
    _expiry.dispose();
    _securityCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsPageFrame(
    title: _isEditing ? 'Edit Card' : 'Add Card',
    bottom: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: settingsContentMaxWidth),
          child: SettingsPaymentPrimaryButton(
            key: const ValueKey('settings-card-save'),
            label: _isSaving ? 'Saving...' : 'Save card',
            onPressed: _isSaving ? null : _save,
          ),
        ),
      ),
    ),
    child: Form(
      key: _formKey,
      child: ListView(
        key: const ValueKey('settings-card-form'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          28 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          if (_isEditing) ...[
            Text(
              'Replace ${widget.existingMethod!.maskedLabel}',
              style: settingsBodyStyle(color: const Color(0xFF676767)),
            ),
            const SizedBox(height: 18),
          ],
          _CardField(
            keyValue: 'settings-card-holder',
            label: 'Cardholder name',
            controller: _cardholder,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 14),
          _CardField(
            keyValue: 'settings-card-number',
            label: 'Card number',
            controller: _cardNumber,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            obscureText: true,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(19),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CardField(
                  keyValue: 'settings-card-expiry',
                  label: 'MM/YY',
                  controller: _expiry,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      RegExp(
                        r'^(0[1-9]|1[0-2])/\d{2}$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use MM/YY',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CardField(
                  keyValue: 'settings-card-security-code',
                  label: 'CVV',
                  controller: _securityCode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  obscureText: true,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  validator: (value) =>
                      RegExp(r'^\d{3,4}$').hasMatch(value?.trim() ?? '')
                      ? null
                      : '3 or 4 digits',
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    PaymentCardInput input;
    try {
      input = PaymentCardInput(
        cardNumber: _cardNumber.text,
        cardholderName: _cardholder.text,
        expiry: _expiry.text,
        securityCode: _securityCode.text,
      );
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    setState(() => _isSaving = true);
    final saveOperation = widget.controller.saveCard(
      methodId: widget.existingMethod?.id,
      input: input,
    );
    _clearSensitiveInput();
    final saved = await saveOperation;
    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() => _isSaving = false);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('settings-card-saved-dialog'),
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary),
        title: Text(_isEditing ? 'Card updated' : 'Card added'),
        content: const Text('Your masked Demo payment method is ready.'),
        actions: [
          FilledButton(
            key: const ValueKey('settings-card-saved-done'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) {
      widget.onSaved();
    }
  }

  void _clearSensitiveInput() {
    _cardholder.clear();
    _cardNumber.clear();
    _expiry.clear();
    _securityCode.clear();
  }
}

final class _CardField extends StatelessWidget {
  const _CardField({
    required this.keyValue,
    required this.label,
    required this.controller,
    required this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.obscureText = false,
    this.onSubmitted,
  });

  final String keyValue;
  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey<String>(keyValue),
    controller: controller,
    textInputAction: textInputAction,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    obscureText: obscureText,
    enableSuggestions: false,
    autocorrect: false,
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
  );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;
