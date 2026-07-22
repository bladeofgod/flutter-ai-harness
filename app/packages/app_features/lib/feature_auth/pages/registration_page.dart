import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../avatar/registration_avatar_picker.dart';
import '../controllers/registration_controller.dart';
import '../models/registration_country.dart';
import '../widgets/auth_components.dart';
import '../widgets/registration_avatar.dart';

final class RegistrationPage extends StatefulWidget {
  const RegistrationPage({
    required this.createController,
    required this.onAuthenticated,
    required this.onCancel,
    super.key,
  });

  final RegistrationController Function() createController;
  final ValueChanged<AuthResult> onAuthenticated;
  final VoidCallback onCancel;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

final class _RegistrationPageState extends State<RegistrationPage> {
  static const _referenceSafeHeight = 734.0;
  static const _systemUiStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  var _isLeaving = false;
  late final RegistrationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.createController();
  }

  @override
  void dispose() {
    _controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        _cancel();
      }
    },
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiStyle,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: GetBuilder<RegistrationController>(
            init: _controller,
            global: false,
            autoRemove: false,
            builder: (controller) => LayoutBuilder(
              builder: (context, constraints) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left:
                        (constraints.maxWidth - authContentMaxWidth) / 2 -
                        131.97,
                    top: -249.67,
                    child: const AuthBubbleBackground(),
                  ),
                  SingleChildScrollView(
                    key: const ValueKey('registration-scroll'),
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: authContentMaxWidth,
                          minHeight: _referenceSafeHeight,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: authHorizontalPadding,
                          ),
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 78),
                                const Padding(
                                  padding: EdgeInsets.only(left: 10),
                                  child: Text(
                                    'Create\nAccount',
                                    style: _RegistrationTextStyles.title,
                                  ),
                                ),
                                const SizedBox(height: 54),
                                Padding(
                                  padding: const EdgeInsets.only(left: 10),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: RegistrationAvatar(
                                      key: const ValueKey(
                                        'registration-avatar',
                                      ),
                                      bytes: controller.avatarBytes,
                                      isPicking: controller.isPickingAvatar,
                                      onPressed: controller.isSubmitting
                                          ? null
                                          : controller.pickAvatar,
                                    ),
                                  ),
                                ),
                                if (_avatarErrorText(controller.avatarFailure)
                                    case final avatarError?) ...[
                                  const SizedBox(height: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: Text(
                                      avatarError,
                                      style: AuthTextStyles.fieldError,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 32),
                                AuthCapsuleTextField(
                                  key: const ValueKey('registration-email'),
                                  controller: controller.emailController,
                                  hintText: 'Email',
                                  semanticsLabel: 'Email',
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  enabled: !controller.isSubmitting,
                                  errorText: _emailErrorText(
                                    controller.emailError,
                                  ),
                                ),
                                const SizedBox(height: 7.906),
                                AuthCapsuleTextField(
                                  key: const ValueKey('registration-password'),
                                  controller: controller.passwordController,
                                  hintText: 'Password',
                                  semanticsLabel:
                                      'Password, exactly 8 characters',
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  obscureText: !controller.passwordVisible,
                                  enabled: !controller.isSubmitting,
                                  errorText: _passwordErrorText(
                                    controller.passwordError,
                                  ),
                                  suffix: IconButton(
                                    onPressed: controller.isSubmitting
                                        ? null
                                        : controller.togglePasswordVisibility,
                                    tooltip: controller.passwordVisible
                                        ? 'Hide password'
                                        : 'Show password',
                                    icon: Icon(
                                      controller.passwordVisible
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: AppColors.textStrong,
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 7.906),
                                AuthCapsuleTextField(
                                  key: const ValueKey('registration-phone'),
                                  controller: controller.phoneController,
                                  hintText: 'Your number',
                                  semanticsLabel:
                                      'Phone number, ${controller.selectedCountry.semanticsLabel}',
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumberNational,
                                  ],
                                  enabled: !controller.isSubmitting,
                                  height: 55.339,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(15),
                                  ],
                                  onSubmitted: (_) => _submit(controller),
                                  errorText: _phoneErrorText(
                                    controller.phoneError,
                                  ),
                                  prefix: _CountrySelector(
                                    country: controller.selectedCountry,
                                    enabled: !controller.isSubmitting,
                                    onPressed: () => _showCountries(controller),
                                  ),
                                ),
                                if (_formErrorText(controller.formError)
                                    case final formError?) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    formError,
                                    textAlign: TextAlign.center,
                                    style: AuthTextStyles.fieldError,
                                  ),
                                ],
                                const SizedBox(height: 52.099),
                                AuthPrimaryButton(
                                  key: const ValueKey('registration-done'),
                                  label: 'Done',
                                  isLoading: controller.isSubmitting,
                                  onPressed: controller.isSubmitting
                                      ? null
                                      : () => _submit(controller),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  child: AuthCancelButton(
                                    key: const ValueKey('registration-cancel'),
                                    onPressed: _cancel,
                                  ),
                                ),
                                const SizedBox(height: 25),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _submit(RegistrationController controller) async {
    final result = await controller.submit();
    if (result != null && mounted && !_isLeaving) {
      _isLeaving = true;
      widget.onAuthenticated(result);
    }
  }

  void _cancel() {
    if (_isLeaving) {
      return;
    }
    _isLeaving = true;
    _controller.reset();
    widget.onCancel();
  }

  Future<void> _showCountries(RegistrationController controller) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<RegistrationCountry>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      builder: (context) =>
          _CountryPickerSheet(selectedCountry: controller.selectedCountry),
    );
    if (selected != null && mounted) {
      controller.selectCountry(selected);
    }
  }
}

final class _CountrySelector extends StatelessWidget {
  const _CountrySelector({
    required this.country,
    required this.enabled,
    required this.onPressed,
  });

  final RegistrationCountry country;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: 'Choose country, ${country.semanticsLabel}',
    child: ExcludeSemantics(
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.only(left: 19.764, right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CountryFlag(country: country),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: AppColors.textStrong,
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: const Color(0x4D1F1F1F)),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _CountryFlag extends StatelessWidget {
  const _CountryFlag({required this.country});

  final RegistrationCountry country;

  @override
  Widget build(BuildContext context) {
    if (country.code == 'GB') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Image.asset(
          'assets/images/auth/flag_united_kingdom.png',
          package: 'app_features',
          width: 24,
          height: 18,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      );
    }
    return SizedBox(
      width: 24,
      height: 20,
      child: FittedBox(fit: BoxFit.contain, child: Text(country.flagEmoji)),
    );
  }
}

final class _CountryPickerSheet extends StatelessWidget {
  const _CountryPickerSheet({required this.selectedCountry});

  final RegistrationCountry selectedCountry;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.72,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text(
            'Country or region',
            style: _RegistrationTextStyles.sheetTitle,
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: registrationCountries.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final country = registrationCountries[index];
              final selected = country == selectedCountry;
              return Semantics(
                button: true,
                selected: selected,
                label: country.semanticsLabel,
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(country),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          _CountryFlag(country: country),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              country.name,
                              style: _RegistrationTextStyles.countryName,
                            ),
                          ),
                          Text(
                            country.callingCode,
                            style: _RegistrationTextStyles.countryCode,
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected
                                ? AppColors.primary
                                : AppColors.formPlaceholder,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

String? _emailErrorText(RegistrationEmailError? error) => switch (error) {
  null => null,
  RegistrationEmailError.required => 'Email is required.',
  RegistrationEmailError.invalid => 'Enter a valid email address.',
  RegistrationEmailError.duplicate =>
    'An account already exists for this email.',
};

String? _passwordErrorText(RegistrationPasswordError? error) => switch (error) {
  null => null,
  RegistrationPasswordError.required => 'Password is required.',
  RegistrationPasswordError.exactLength =>
    'Password must contain exactly 8 characters.',
};

String? _phoneErrorText(RegistrationPhoneError? error) => switch (error) {
  null => null,
  RegistrationPhoneError.required => 'Phone number is required.',
  RegistrationPhoneError.invalid => 'Enter 6 to 15 digits.',
};

String? _avatarErrorText(RegistrationAvatarFailure? failure) =>
    switch (failure?.code) {
      null => null,
      RegistrationAvatarFailureCode.permissionDenied =>
        'Photo access was not granted.',
      RegistrationAvatarFailureCode.tooLarge =>
        'Choose an image smaller than 2 MiB.',
      RegistrationAvatarFailureCode.invalidImage =>
        'Choose a valid image file.',
      RegistrationAvatarFailureCode.pickerUnavailable ||
      RegistrationAvatarFailureCode.readFailed =>
        'The selected image could not be used.',
    };

String? _formErrorText(RegistrationFormError? error) => switch (error) {
  null => null,
  RegistrationFormError.unavailable =>
    'Registration is unavailable. Try again.',
};

abstract final class _RegistrationTextStyles {
  static const title = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.raleway,
    package: AppFonts.package,
    fontSize: 50,
    fontWeight: FontWeight.w700,
    height: 54 / 50,
    letterSpacing: 0,
  );

  static const sheetTitle = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.raleway,
    package: AppFonts.package,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: 0,
  );

  static const countryName = TextStyle(
    color: AppColors.textStrong,
    fontFamily: AppFonts.poppins,
    package: AppFonts.package,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
  );

  static const countryCode = TextStyle(
    color: AppColors.textPrimary,
    fontFamily: AppFonts.poppins,
    package: AppFonts.package,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
  );
}
