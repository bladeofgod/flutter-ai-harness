import 'dart:typed_data';

import 'package:app_data/app_data.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../api/auth_api.dart';
import '../avatar/registration_avatar_picker.dart';
import '../models/registration_country.dart';

enum RegistrationEmailError { required, invalid, duplicate }

enum RegistrationPasswordError { required, exactLength }

enum RegistrationPhoneError { required, invalid }

enum RegistrationFormError { unavailable }

/// 管理注册输入、校验和提交，不持有导航或壳工程回调。
base class RegistrationController extends GetxController {
  RegistrationController({
    required AuthApi authApi,
    required RegistrationAvatarPicker avatarPicker,
  }) : _authApi = authApi,
       _avatarPicker = avatarPicker;

  static const defaultAvatarAsset =
      'assets/images/auth/registration_photo_placeholder.png';

  final AuthApi _authApi;
  final RegistrationAvatarPicker _avatarPicker;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();

  RegistrationCountry _selectedCountry = defaultRegistrationCountry;
  RegistrationEmailError? _emailError;
  RegistrationPasswordError? _passwordError;
  RegistrationPhoneError? _phoneError;
  RegistrationAvatarFailure? _avatarFailure;
  RegistrationFormError? _formError;
  Uint8List? _avatarBytes;
  bool _passwordVisible = false;
  bool _isSubmitting = false;
  bool _isPickingAvatar = false;
  bool _isDisposed = false;
  var _operationGeneration = 0;

  RegistrationCountry get selectedCountry => _selectedCountry;
  RegistrationEmailError? get emailError => _emailError;
  RegistrationPasswordError? get passwordError => _passwordError;
  RegistrationPhoneError? get phoneError => _phoneError;
  RegistrationAvatarFailure? get avatarFailure => _avatarFailure;
  RegistrationFormError? get formError => _formError;
  Uint8List? get avatarBytes {
    final value = _avatarBytes;
    return value == null ? null : Uint8List.fromList(value);
  }

  bool get passwordVisible => _passwordVisible;
  bool get isSubmitting => _isSubmitting;
  bool get isPickingAvatar => _isPickingAvatar;

  @override
  void onInit() {
    super.onInit();
    emailController.addListener(_handleEmailChanged);
    passwordController.addListener(_handlePasswordChanged);
    phoneController.addListener(_handlePhoneChanged);
  }

  void togglePasswordVisibility() {
    if (_isDisposed) {
      return;
    }
    _passwordVisible = !_passwordVisible;
    update();
  }

  void selectCountry(RegistrationCountry country) {
    if (_isDisposed || _selectedCountry == country) {
      return;
    }
    _selectedCountry = country;
    _phoneError = null;
    _formError = null;
    update();
  }

  Future<void> pickAvatar() async {
    if (_isDisposed || _isPickingAvatar) {
      return;
    }
    _isPickingAvatar = true;
    _avatarFailure = null;
    final generation = _operationGeneration;
    update();

    try {
      final result = await _avatarPicker.pickFromGallery();
      if (_isDisposed || generation != _operationGeneration) {
        return;
      }

      switch (result) {
        case RegistrationAvatarPickCanceled():
          break;
        case RegistrationAvatarPickSuccess(:final bytes):
          _avatarBytes = Uint8List.fromList(bytes);
        case RegistrationAvatarPickFailed(:final failure):
          _avatarFailure = failure;
      }
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        _isPickingAvatar = false;
        update();
      }
    }
  }

  Future<AuthResult?> submit() async {
    if (_isDisposed || _isSubmitting || !_validate()) {
      return null;
    }

    _isSubmitting = true;
    _formError = null;
    final generation = _operationGeneration;
    update();

    try {
      final avatarBytes = _avatarBytes;
      final result = await _authApi.register(
        RegistrationInput(
          email: EmailAddress(emailController.text),
          password: Password(passwordController.text),
          callingCode: _selectedCountry.domainCallingCode,
          phoneNumber: PhoneNumber(phoneController.text),
          avatar: avatarBytes == null
              ? UserAvatar.asset(defaultAvatarAsset)
              : UserAvatar.memory(avatarBytes),
        ),
      );
      if (_isDisposed || generation != _operationGeneration) {
        return null;
      }
      return result;
    } on AuthFailure catch (failure) {
      if (!_isDisposed && generation == _operationGeneration) {
        if (failure.code == AuthFailureCode.duplicateAccount) {
          _emailError = RegistrationEmailError.duplicate;
        } else {
          _formError = RegistrationFormError.unavailable;
        }
      }
      return null;
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        _isSubmitting = false;
        update();
      }
    }
  }

  void reset() {
    if (_isDisposed) {
      return;
    }
    _operationGeneration += 1;
    emailController.clear();
    passwordController.clear();
    phoneController.clear();
    _selectedCountry = defaultRegistrationCountry;
    _emailError = null;
    _passwordError = null;
    _phoneError = null;
    _avatarFailure = null;
    _formError = null;
    _avatarBytes = null;
    _passwordVisible = false;
    _isSubmitting = false;
    _isPickingAvatar = false;
    update();
  }

  bool _validate() {
    _emailError = _validateEmail(emailController.text);
    _passwordError = _validatePassword(passwordController.text);
    _phoneError = _validatePhone(phoneController.text);
    _formError = null;
    final isValid =
        _emailError == null && _passwordError == null && _phoneError == null;
    update();
    return isValid;
  }

  RegistrationEmailError? _validateEmail(String value) {
    if (value.trim().isEmpty) {
      return RegistrationEmailError.required;
    }
    try {
      EmailAddress(value);
      return null;
    } on FormatException {
      return RegistrationEmailError.invalid;
    }
  }

  RegistrationPasswordError? _validatePassword(String value) {
    if (value.isEmpty) {
      return RegistrationPasswordError.required;
    }
    if (value.length != Password.requiredLength) {
      return RegistrationPasswordError.exactLength;
    }
    return null;
  }

  RegistrationPhoneError? _validatePhone(String value) {
    if (value.trim().isEmpty) {
      return RegistrationPhoneError.required;
    }
    if (!RegExp(r'^[0-9]{6,15}$').hasMatch(value.trim())) {
      return RegistrationPhoneError.invalid;
    }
    return null;
  }

  void _handleEmailChanged() {
    if (_emailError != null || _formError != null) {
      _emailError = null;
      _formError = null;
      update();
    }
  }

  void _handlePasswordChanged() {
    if (_passwordError != null || _formError != null) {
      _passwordError = null;
      _formError = null;
      update();
    }
  }

  void _handlePhoneChanged() {
    if (_phoneError != null || _formError != null) {
      _phoneError = null;
      _formError = null;
      update();
    }
  }

  @override
  void onClose() {
    _isDisposed = true;
    _operationGeneration += 1;
    _avatarBytes = null;
    emailController.removeListener(_handleEmailChanged);
    passwordController.removeListener(_handlePasswordChanged);
    phoneController.removeListener(_handlePhoneChanged);
    emailController.clear();
    passwordController.clear();
    phoneController.clear();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    super.onClose();
  }
}
