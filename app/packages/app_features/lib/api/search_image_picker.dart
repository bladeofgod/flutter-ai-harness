import 'dart:typed_data';

/// Search 业务只消费内存图片及稳定错误码。
abstract interface class SearchImagePicker {
  Future<SearchImagePickResult> pickFromGallery();

  Future<SearchImagePickResult> capturePhoto();

  Future<void> clearDrafts();

  Future<void> dispose();
}

sealed class SearchImagePickResult {
  const SearchImagePickResult();
}

final class SearchImagePickCanceled extends SearchImagePickResult {
  const SearchImagePickCanceled();
}

final class SearchImagePickSuccess extends SearchImagePickResult {
  SearchImagePickSuccess(Uint8List bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'SearchImagePickSuccess(<redacted>)';
}

final class SearchImagePickFailed extends SearchImagePickResult {
  const SearchImagePickFailed(this.failure);

  final SearchImagePickFailure failure;
}

final class SearchImagePickFailure {
  const SearchImagePickFailure(this.code);

  final SearchImagePickFailureCode code;

  @override
  String toString() => 'SearchImagePickFailure(${code.name})';
}

enum SearchImagePickFailureCode {
  permissionDenied,
  pickerUnavailable,
  readFailed,
  tooLarge,
  invalidImage,
}

final class SearchImagePickerDisposalException implements Exception {
  const SearchImagePickerDisposalException();

  @override
  String toString() => 'SearchImagePickerDisposalException(<redacted>)';
}
