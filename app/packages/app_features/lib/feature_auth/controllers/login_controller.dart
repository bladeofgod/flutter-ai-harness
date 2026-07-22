import 'package:app_data/app_data.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../api/auth_api.dart';

enum LoginEmailError { required, invalid, accountNotFound }

enum LoginPasswordError { exactLength, invalidCredentials }

enum LoginFormError { unavailable }

enum PasswordRecoveryMethod { sms, email }

/// 管理登录三步流程，只依赖 Auth API，不持有导航或壳工程状态。
base class LoginController extends GetxController {
  LoginController({required AuthApi authApi}) : _authApi = authApi;

  final AuthApi _authApi;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordFocusNode = FocusNode();

  UserEntity? _recognizedUser;
  LoginEmailError? _emailError;
  LoginPasswordError? _passwordError;
  LoginFormError? _formError;
  PasswordRecoveryMethod _recoveryMethod = PasswordRecoveryMethod.sms;
  bool _isFindingAccount = false;
  bool _isLoggingIn = false;
  bool _showFailedPasswordDots = false;
  bool _hasAuthenticated = false;
  bool _isDisposed = false;
  var _operationGeneration = 0;

  UserEntity? get recognizedUser => _recognizedUser;
  LoginEmailError? get emailError => _emailError;
  LoginPasswordError? get passwordError => _passwordError;
  LoginFormError? get formError => _formError;
  PasswordRecoveryMethod get recoveryMethod => _recoveryMethod;
  bool get isFindingAccount => _isFindingAccount;
  bool get isLoggingIn => _isLoggingIn;
  bool get showFailedPasswordDots => _showFailedPasswordDots;
  int get enteredPasswordCharacters => passwordController.text.length;

  @override
  void onInit() {
    super.onInit();
    emailController.addListener(_handleEmailChanged);
    passwordController.addListener(_handlePasswordChanged);
  }

  Future<UserEntity?> findAccount() async {
    if (_isDisposed || _isFindingAccount) {
      return null;
    }
    final email = _parseEmail();
    if (email == null) {
      update();
      return null;
    }

    _isFindingAccount = true;
    _formError = null;
    final generation = _operationGeneration;
    update();
    try {
      final user = await _authApi.findAccountByEmail(email);
      if (_isDisposed || generation != _operationGeneration) {
        return null;
      }
      if (user == null) {
        _emailError = LoginEmailError.accountNotFound;
        return null;
      }
      _recognizedUser = user;
      _emailError = null;
      return user;
    } on AuthFailure {
      if (!_isDisposed && generation == _operationGeneration) {
        _formError = LoginFormError.unavailable;
      }
      return null;
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        _isFindingAccount = false;
        update();
      }
    }
  }

  Future<AuthResult?> submitPassword() async {
    if (_isDisposed ||
        _recognizedUser == null ||
        _isLoggingIn ||
        _hasAuthenticated) {
      return null;
    }
    if (passwordController.text.length != Password.requiredLength) {
      _passwordError = LoginPasswordError.exactLength;
      _showFailedPasswordDots = false;
      update();
      return null;
    }

    _isLoggingIn = true;
    _passwordError = null;
    _formError = null;
    final generation = _operationGeneration;
    update();
    try {
      final result = await _authApi.login(
        LoginInput(
          email: _recognizedUser!.email,
          password: Password(passwordController.text),
        ),
      );
      if (_isDisposed || generation != _operationGeneration) {
        return null;
      }
      _hasAuthenticated = true;
      return result;
    } on AuthFailure catch (failure) {
      if (!_isDisposed && generation == _operationGeneration) {
        passwordController.clear();
        if (failure.code == AuthFailureCode.invalidCredentials) {
          _passwordError = LoginPasswordError.invalidCredentials;
          _showFailedPasswordDots = true;
        } else {
          _formError = LoginFormError.unavailable;
        }
      }
      return null;
    } finally {
      if (!_isDisposed && generation == _operationGeneration) {
        _isLoggingIn = false;
        update();
      }
    }
  }

  void returnToEmail() {
    if (_isDisposed) {
      return;
    }
    _clearPassword();
    _formError = null;
    update();
  }

  void prepareRecovery() {
    if (_isDisposed) {
      return;
    }
    _clearPassword();
    update();
  }

  void selectRecoveryMethod(PasswordRecoveryMethod method) {
    if (_isDisposed || method == _recoveryMethod) {
      return;
    }
    _recoveryMethod = method;
    update();
  }

  /// Recovery 在当前任务中只有可操作 UI，没有发送或后续业务。
  void consumeRecoveryNext() {}

  void resetFlow() {
    if (_isDisposed) {
      return;
    }
    _operationGeneration += 1;
    _recognizedUser = null;
    _emailError = null;
    _passwordError = null;
    _formError = null;
    _recoveryMethod = PasswordRecoveryMethod.sms;
    _showFailedPasswordDots = false;
    _hasAuthenticated = false;
    _isFindingAccount = false;
    _isLoggingIn = false;
    emailController.clear();
    passwordController.clear();
    update();
  }

  EmailAddress? _parseEmail() {
    if (emailController.text.trim().isEmpty) {
      _emailError = LoginEmailError.required;
      return null;
    }
    try {
      _emailError = null;
      return EmailAddress(emailController.text);
    } on FormatException {
      _emailError = LoginEmailError.invalid;
      return null;
    }
  }

  void _clearPassword() {
    passwordController.clear();
    _passwordError = null;
    _showFailedPasswordDots = false;
  }

  void _handleEmailChanged() {
    if (_isDisposed) {
      return;
    }
    _recognizedUser = null;
    _emailError = null;
    _formError = null;
    update();
  }

  void _handlePasswordChanged() {
    if (_isDisposed) {
      return;
    }
    if (passwordController.text.isNotEmpty) {
      _passwordError = null;
      _showFailedPasswordDots = false;
      _formError = null;
    }
    update();
  }

  @override
  void onClose() {
    _isDisposed = true;
    _operationGeneration += 1;
    _recognizedUser = null;
    _passwordError = null;
    _showFailedPasswordDots = false;
    emailController.removeListener(_handleEmailChanged);
    passwordController.removeListener(_handlePasswordChanged);
    emailController.clear();
    passwordController.clear();
    passwordFocusNode.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
