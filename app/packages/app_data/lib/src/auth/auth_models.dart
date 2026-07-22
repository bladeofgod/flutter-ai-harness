import 'dart:typed_data';

import 'package:app_core/app_core.dart';

/// 经过裁剪和小写归一化的 Email 地址。
final class EmailAddress {
  factory EmailAddress(String input) {
    final value = input.trim().toLowerCase();
    if (!_pattern.hasMatch(value)) {
      throw const FormatException('Invalid email address.');
    }
    return EmailAddress._(value);
  }

  const EmailAddress._(this.value);

  static final RegExp _pattern = RegExp(
    r"^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$",
  );

  final String value;

  @override
  String toString() => 'EmailAddress(<redacted>)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EmailAddress && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Shoppe Demo 的固定八位密码。
///
/// 明文不会通过 getter 或字符串化暴露；只有数据适配层构造请求时显式转为
/// [Secret]，并在 Transport 的受控边界中读取。
final class Password {
  factory Password(String value) {
    if (value.length != requiredLength) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'Password must contain exactly $requiredLength characters.',
      );
    }
    return Password._(value);
  }

  const Password._(this._value);

  static const int requiredLength = 8;

  final String _value;

  Secret<String> toSecret() => Secret<String>(_value);

  @override
  String toString() => 'Password(<redacted>)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Password && _value == other._value;

  @override
  int get hashCode => Object.hash(Password, _value);
}

/// E.164 风格的国家/地区区号，不包含本地号码。
final class CountryCallingCode {
  factory CountryCallingCode(String input) {
    final value = input.trim();
    if (!_pattern.hasMatch(value)) {
      throw const FormatException('Invalid country calling code.');
    }
    return CountryCallingCode._(value);
  }

  const CountryCallingCode._(this.value);

  static final RegExp _pattern = RegExp(r'^\+[1-9][0-9]{0,2}$');

  final String value;

  @override
  String toString() => 'CountryCallingCode($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryCallingCode && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// 只包含数字的本地电话号码。
final class PhoneNumber {
  factory PhoneNumber(String input) {
    final value = input.replaceAll(RegExp(r'[\s()-]'), '');
    if (!_pattern.hasMatch(value)) {
      throw const FormatException('Invalid phone number.');
    }
    return PhoneNumber._(value);
  }

  const PhoneNumber._(this.value);

  static final RegExp _pattern = RegExp(r'^[0-9]{4,15}$');

  final String value;

  @override
  String toString() => 'PhoneNumber(<redacted>)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PhoneNumber && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Flutter 和图片选择插件中立的头像值对象。
final class UserAvatar {
  factory UserAvatar.asset(String assetKey) {
    final value = assetKey.trim();
    final uri = Uri.tryParse(value);
    final hasParentSegment = value.split('/').contains('..');
    final isWindowsAbsolute = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.contains('\\') ||
        hasParentSegment ||
        isWindowsAbsolute ||
        (uri?.hasScheme ?? false)) {
      throw ArgumentError.value(
        '<redacted>',
        'assetKey',
        'Avatar asset key must be a relative, platform-neutral identifier.',
      );
    }
    return UserAvatar._(assetKey: value);
  }

  factory UserAvatar.memory(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        '<redacted>',
        'bytes',
        'Avatar bytes must not be empty.',
      );
    }
    return UserAvatar._(bytes: Uint8List.fromList(bytes));
  }

  UserAvatar._({this.assetKey, Uint8List? bytes})
    : _bytes = bytes == null ? null : Uint8List.fromList(bytes),
      kind = assetKey == null ? UserAvatarKind.memory : UserAvatarKind.asset;

  final UserAvatarKind kind;
  final String? assetKey;
  final Uint8List? _bytes;

  Uint8List? get bytes {
    final value = _bytes;
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  String toString() => 'UserAvatar(${kind.name}, <redacted>)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! UserAvatar ||
        kind != other.kind ||
        assetKey != other.assetKey) {
      return false;
    }
    final left = _bytes;
    final right = other._bytes;
    if (left == null || right == null) {
      return left == right;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var bytesHash = 0;
    for (final byte in _bytes ?? const <int>[]) {
      bytesHash = Object.hash(bytesHash, byte);
    }
    return Object.hash(kind, assetKey, bytesHash);
  }
}

enum UserAvatarKind { asset, memory }

/// 可跨数据层与 Feature 边界传递的当前用户 Entity。
final class UserEntity {
  factory UserEntity({
    required String id,
    required String displayName,
    required EmailAddress email,
    required CountryCallingCode callingCode,
    required PhoneNumber phoneNumber,
    required UserAvatar avatar,
  }) {
    if (id.isEmpty || displayName.trim().isEmpty) {
      throw ArgumentError(
        'UserEntity requires non-empty identifiers and display name.',
      );
    }
    return UserEntity._(
      id: id,
      displayName: displayName,
      email: email,
      callingCode: callingCode,
      phoneNumber: phoneNumber,
      avatar: avatar,
    );
  }

  const UserEntity._({
    required this.id,
    required this.displayName,
    required this.email,
    required this.callingCode,
    required this.phoneNumber,
    required this.avatar,
  });

  final String id;
  final String displayName;
  final EmailAddress email;
  final CountryCallingCode callingCode;
  final PhoneNumber phoneNumber;
  final UserAvatar avatar;

  UserEntity copyWith({String? displayName, UserAvatar? avatar}) => UserEntity(
    id: id,
    displayName: displayName ?? this.displayName,
    email: email,
    callingCode: callingCode,
    phoneNumber: phoneNumber,
    avatar: avatar ?? this.avatar,
  );

  @override
  String toString() => 'UserEntity(id: $id, displayName: $displayName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserEntity &&
          id == other.id &&
          displayName == other.displayName &&
          email == other.email &&
          callingCode == other.callingCode &&
          phoneNumber == other.phoneNumber &&
          avatar == other.avatar;

  @override
  int get hashCode =>
      Object.hash(id, displayName, email, callingCode, phoneNumber, avatar);
}

/// Demo 的进程内认证会话，不包含 Token。
final class AuthSession {
  factory AuthSession({required String id, required String userId}) {
    if (id.isEmpty || userId.isEmpty) {
      throw ArgumentError('AuthSession requires non-empty identifiers.');
    }
    return AuthSession._(id: id, userId: userId);
  }

  const AuthSession._({required this.id, required this.userId});

  final String id;
  final String userId;

  @override
  String toString() => 'AuthSession(id: $id, userId: $userId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession && id == other.id && userId == other.userId;

  @override
  int get hashCode => Object.hash(id, userId);
}

/// 注册需要的完整 Domain 输入。
final class RegistrationInput {
  const RegistrationInput({
    required this.email,
    required this.password,
    required this.callingCode,
    required this.phoneNumber,
    required this.avatar,
  });

  final EmailAddress email;
  final Password password;
  final CountryCallingCode callingCode;
  final PhoneNumber phoneNumber;
  final UserAvatar avatar;

  @override
  String toString() =>
      'RegistrationInput(email: $email, password: <redacted>, '
      'callingCode: $callingCode, phoneNumber: $phoneNumber, '
      'avatar: $avatar)';
}

/// 登录需要的 Domain 输入。
final class LoginInput {
  const LoginInput({required this.email, required this.password});

  final EmailAddress email;
  final Password password;

  @override
  String toString() => 'LoginInput(email: $email, password: <redacted>)';
}

/// Auth 成功返回的原子用户与会话快照。
final class AuthResult {
  AuthResult({required this.user, required this.session}) {
    if (user.id != session.userId) {
      throw ArgumentError(
        'AuthResult requires matching User and Session identifiers.',
      );
    }
  }

  final UserEntity user;
  final AuthSession session;

  @override
  String toString() => 'AuthResult(user: $user, session: $session)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthResult && user == other.user && session == other.session;

  @override
  int get hashCode => Object.hash(user, session);
}
