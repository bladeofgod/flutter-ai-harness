import 'package:app_data/app_data.dart';

import '../../api/auth_api.dart';

/// 通过本地数据源实现 Auth Feature 所需的业务能力。
final class LocalAuthApi implements AuthApi {
  const LocalAuthApi({required AuthLocalDataSource dataSource})
    : _dataSource = dataSource;

  final AuthLocalDataSource _dataSource;

  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) =>
      _dataSource.findAccountByEmail(email);

  @override
  Future<AuthResult> register(RegistrationInput input) =>
      _dataSource.register(input);

  @override
  Future<AuthResult> login(LoginInput input) => _dataSource.login(input);
}
