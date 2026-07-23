import 'dart:typed_data';

import '../../shared/media/gallery_media_picker.dart';
import '../../shared/media/image_picker_gallery_media_picker.dart';

/// Search 只消费内存图片及稳定错误码。
abstract interface class SearchImagePicker {
  Future<SearchImagePickResult> pickFromGallery();
}

final class SharedMediaSearchImagePicker implements SearchImagePicker {
  SharedMediaSearchImagePicker({GalleryMediaPicker? mediaPicker})
    : _mediaPicker = mediaPicker ?? ImagePickerGalleryMediaPicker();

  final GalleryMediaPicker _mediaPicker;

  @override
  Future<SearchImagePickResult> pickFromGallery() async {
    final result = await _mediaPicker.pickImage();
    return switch (result) {
      GalleryMediaPickCanceled() => const SearchImagePickCanceled(),
      GalleryMediaPickSuccess(:final bytes) => SearchImagePickSuccess(bytes),
      GalleryMediaPickFailed(:final failure) => SearchImagePickFailed(
        SearchImagePickFailure(_mapFailure(failure.code)),
      ),
    };
  }

  SearchImagePickFailureCode _mapFailure(GalleryMediaFailureCode code) =>
      switch (code) {
        GalleryMediaFailureCode.permissionDenied =>
          SearchImagePickFailureCode.permissionDenied,
        GalleryMediaFailureCode.pickerUnavailable =>
          SearchImagePickFailureCode.pickerUnavailable,
        GalleryMediaFailureCode.readFailed =>
          SearchImagePickFailureCode.readFailed,
        GalleryMediaFailureCode.tooLarge => SearchImagePickFailureCode.tooLarge,
        GalleryMediaFailureCode.invalidImage =>
          SearchImagePickFailureCode.invalidImage,
      };
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
