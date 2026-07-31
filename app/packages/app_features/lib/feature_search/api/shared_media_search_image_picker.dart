import '../../api/search_image_picker.dart';
import '../../shared/media/gallery_media_picker.dart';
import '../../shared/media/image_picker_gallery_media_picker.dart';

final class SharedMediaSearchImagePicker implements SearchImagePicker {
  SharedMediaSearchImagePicker({
    GalleryMediaPicker? mediaPicker,
    SearchCameraMediaPicker? cameraPicker,
  }) : _mediaPicker = mediaPicker ?? ImagePickerGalleryMediaPicker(),
       _cameraPicker =
           cameraPicker ?? const UnavailableSearchCameraMediaPicker();

  final GalleryMediaPicker _mediaPicker;
  final SearchCameraMediaPicker _cameraPicker;

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

  @override
  Future<SearchImagePickResult> capturePhoto() => _cameraPicker.capturePhoto();

  @override
  Future<void> clearDrafts() => _cameraPicker.clearDrafts();

  @override
  Future<void> dispose() => _cameraPicker.dispose();

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

abstract interface class SearchCameraMediaPicker {
  Future<SearchImagePickResult> capturePhoto();

  Future<void> clearDrafts();

  Future<void> dispose();
}

final class UnavailableSearchCameraMediaPicker
    implements SearchCameraMediaPicker {
  const UnavailableSearchCameraMediaPicker();

  @override
  Future<SearchImagePickResult> capturePhoto() async =>
      const SearchImagePickFailed(
        SearchImagePickFailure(SearchImagePickFailureCode.pickerUnavailable),
      );

  @override
  Future<void> clearDrafts() async {}

  @override
  Future<void> dispose() async {}
}
