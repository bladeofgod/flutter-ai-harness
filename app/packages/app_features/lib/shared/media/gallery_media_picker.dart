import 'dart:typed_data';

/// Feature 只依赖该平台中立边界，不接触文件路径或 Plugin 类型。
abstract interface class GalleryMediaPicker {
  Future<GalleryMediaPickResult> pickImage();
}

sealed class GalleryMediaPickResult {
  const GalleryMediaPickResult();
}

final class GalleryMediaPickCanceled extends GalleryMediaPickResult {
  const GalleryMediaPickCanceled();
}

final class GalleryMediaPickSuccess extends GalleryMediaPickResult {
  GalleryMediaPickSuccess(Uint8List bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'GalleryMediaPickSuccess(<redacted>)';
}

final class GalleryMediaPickFailed extends GalleryMediaPickResult {
  const GalleryMediaPickFailed(this.failure);

  final GalleryMediaFailure failure;
}

final class GalleryMediaFailure {
  const GalleryMediaFailure(this.code);

  final GalleryMediaFailureCode code;

  @override
  bool operator ==(Object other) =>
      other is GalleryMediaFailure && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'GalleryMediaFailure(${code.name})';
}

enum GalleryMediaFailureCode {
  permissionDenied,
  pickerUnavailable,
  readFailed,
  tooLarge,
  invalidImage,
}
