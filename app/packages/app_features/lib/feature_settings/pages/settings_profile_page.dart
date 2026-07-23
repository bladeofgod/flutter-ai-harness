import 'package:app_data/app_data.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/settings_controller.dart';
import '../widgets/settings_components.dart';

final class SettingsProfilePage extends StatefulWidget {
  const SettingsProfilePage({required this.controller, super.key});

  final SettingsController controller;

  @override
  State<SettingsProfilePage> createState() => _SettingsProfilePageState();
}

final class _SettingsProfilePageState extends State<SettingsProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _callingCodeController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    final user = widget.controller.currentUser;
    _nameController = TextEditingController(text: user?.displayName);
    _emailController = TextEditingController(text: user?.email.value);
    _callingCodeController = TextEditingController(
      text: user?.callingCode.value,
    );
    _phoneController = TextEditingController(text: user?.phoneNumber.value);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _callingCodeController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GetBuilder<SettingsController>(
    init: widget.controller,
    global: false,
    autoRemove: false,
    dispose: (state) => state.controller.onDelete(),
    builder: (controller) => SettingsPageFrame(
      title: 'Profile',
      bottom: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: settingsContentMaxWidth,
            ),
            child: Obx(
              () => FilledButton(
                key: const ValueKey('settings-profile-save'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: controller.isSaving ? null : () => _save(controller),
                child: controller.isSaving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Changes'),
              ),
            ),
          ),
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          key: const ValueKey('settings-profile-form'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Center(child: _ProfileAvatar(user: controller.currentUser)),
            const SizedBox(height: 24),
            _ProfileField(
              keyValue: 'settings-profile-name',
              label: 'Name',
              controller: _nameController,
              textInputAction: TextInputAction.next,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name'
                  : null,
            ),
            const SizedBox(height: 14),
            _ProfileField(
              keyValue: 'settings-profile-email',
              label: 'Email',
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                try {
                  EmailAddress(value ?? '');
                  return null;
                } on FormatException {
                  return 'Enter a valid email';
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 94,
                  child: _ProfileField(
                    keyValue: 'settings-profile-calling-code',
                    label: 'Code',
                    controller: _callingCodeController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      try {
                        CountryCallingCode(value ?? '');
                        return null;
                      } on FormatException {
                        return 'Invalid';
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ProfileField(
                    keyValue: 'settings-profile-phone',
                    label: 'Phone',
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    validator: (value) {
                      try {
                        PhoneNumber(value ?? '');
                        return null;
                      } on FormatException {
                        return 'Enter a valid phone number';
                      }
                    },
                  ),
                ),
              ],
            ),
            Obx(() {
              if (controller.operationFailure == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Unable to update your profile. Please try again.',
                  key: const ValueKey('settings-profile-error'),
                  style: settingsBodyStyle(color: const Color(0xFFB42A31)),
                ),
              );
            }),
          ],
        ),
      ),
    ),
  );

  Future<void> _save(SettingsController controller) async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final user = controller.currentUser;
    if (user == null) {
      return;
    }
    final saved = await controller.updateProfile(
      ProfileEditInput(
        displayName: _nameController.text,
        email: EmailAddress(_emailController.text),
        callingCode: CountryCallingCode(_callingCodeController.text),
        phoneNumber: PhoneNumber(_phoneController.text),
        avatar: user.avatar,
      ),
    );
    if (saved && mounted) {
      Navigator.of(context).pop();
    }
  }
}

final class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.user});

  final UserEntity? user;

  @override
  Widget build(BuildContext context) {
    final avatar = user?.avatar;
    final ImageProvider<Object>? provider = switch (avatar?.kind) {
      UserAvatarKind.asset when avatar?.assetKey != null => AssetImage(
        avatar!.assetKey!,
        package: 'app_features',
      ),
      UserAvatarKind.memory when avatar?.bytes != null => MemoryImage(
        avatar!.bytes!,
      ),
      _ => null,
    };
    return CircleAvatar(
      key: const ValueKey('settings-profile-avatar'),
      radius: 48,
      backgroundColor: AppColors.primarySurface,
      backgroundImage: provider,
      child: provider == null
          ? const Icon(Icons.person_rounded, size: 44, color: AppColors.primary)
          : null,
    );
  }
}

final class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.keyValue,
    required this.label,
    required this.controller,
    required this.textInputAction,
    required this.validator,
    this.keyboardType,
  });

  final String keyValue;
  final String label;
  final TextEditingController controller;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey<String>(keyValue),
    controller: controller,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    validator: validator,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    decoration: InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.formBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
