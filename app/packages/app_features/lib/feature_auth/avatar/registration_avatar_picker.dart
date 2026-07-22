import 'dart:typed_data';

/// 注册流程只需要从系统图库选择一张内存头像。
abstract interface class RegistrationAvatarPicker {
  Future<RegistrationAvatarPickResult> pickFromGallery();
}

sealed class RegistrationAvatarPickResult {
  const RegistrationAvatarPickResult();
}

final class RegistrationAvatarPickCanceled
    extends RegistrationAvatarPickResult {
  const RegistrationAvatarPickCanceled();
}

final class RegistrationAvatarPickSuccess extends RegistrationAvatarPickResult {
  RegistrationAvatarPickSuccess(Uint8List bytes)
    : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'RegistrationAvatarPickSuccess(<redacted>)';
}

final class RegistrationAvatarPickFailed extends RegistrationAvatarPickResult {
  const RegistrationAvatarPickFailed(this.failure);

  final RegistrationAvatarFailure failure;
}

final class RegistrationAvatarFailure {
  const RegistrationAvatarFailure(this.code);

  final RegistrationAvatarFailureCode code;

  @override
  String toString() => 'RegistrationAvatarFailure(${code.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegistrationAvatarFailure && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

enum RegistrationAvatarFailureCode {
  permissionDenied,
  pickerUnavailable,
  readFailed,
  tooLarge,
  invalidImage,
}
