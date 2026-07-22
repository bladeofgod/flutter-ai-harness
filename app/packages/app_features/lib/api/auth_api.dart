import 'package:app_data/app_data.dart';

/// Auth Feature 使用的最小业务能力边界。
abstract interface class AuthApi {
  Future<UserEntity?> findAccountByEmail(EmailAddress email);

  Future<AuthResult> register(RegistrationInput input);

  Future<AuthResult> login(LoginInput input);
}
