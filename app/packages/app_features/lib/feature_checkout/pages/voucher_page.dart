import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

import '../controllers/checkout_controller.dart';
import '../widgets/checkout_components.dart';

final class CheckoutVoucherPage extends StatefulWidget {
  const CheckoutVoucherPage({required this.controller, super.key});

  final CheckoutController controller;

  @override
  State<CheckoutVoucherPage> createState() => _CheckoutVoucherPageState();
}

final class _CheckoutVoucherPageState extends State<CheckoutVoucherPage> {
  late final TextEditingController _codeController;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(
      text: widget.controller.session?.voucher?.code ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_isSubmitting) {
      return;
    }
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a voucher code');
      return;
    }
    setState(() {
      _error = null;
      _isSubmitting = true;
    });
    final applied = await widget.controller.applyVoucher(code);
    if (!mounted) {
      return;
    }
    if (applied) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = 'This Demo voucher is not available';
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) => CheckoutPageScaffold(
    title: 'Add Voucher',
    bottomAction: CheckoutPrimaryButton(
      key: const ValueKey('checkout-apply-voucher'),
      label: _isSubmitting ? 'Applying...' : 'Apply voucher',
      onPressed: _isSubmitting ? null : _apply,
    ),
    child: CheckoutContent(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Text('Voucher code', style: checkoutHeading(size: 16)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('checkout-voucher-code'),
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            decoration: InputDecoration(
              hintText: 'Voucher code',
              errorText: _error,
              filled: true,
              fillColor: AppColors.formBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: 14),
          Text(
            'Use an available Demo voucher on an eligible order.',
            style: checkoutBody(size: 12, color: const Color(0xFF777777)),
          ),
        ],
      ),
    ),
  );
}
