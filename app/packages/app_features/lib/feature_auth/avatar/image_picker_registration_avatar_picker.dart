import 'package:image_picker/image_picker.dart';

import '../../shared/media/gallery_media_picker.dart';
import '../../shared/media/image_picker_gallery_media_picker.dart';
import 'registration_avatar_picker.dart';

/// 将 Flutter 官方 Image Picker 收敛为注册流程的平台中立头像结果。
final class ImagePickerRegistrationAvatarPicker
    implements RegistrationAvatarPicker {
  ImagePickerRegistrationAvatarPicker({
    GalleryMediaPicker? mediaPicker,
    ImagePicker? imagePicker,
  }) : _mediaPicker =
           mediaPicker ??
           ImagePickerGalleryMediaPicker(imagePicker: imagePicker);

  static const double maxWidth = ImagePickerGalleryMediaPicker.maxWidth;
  static const double maxHeight = ImagePickerGalleryMediaPicker.maxHeight;
  static const int imageQuality = ImagePickerGalleryMediaPicker.imageQuality;
  static const int maxBytes = ImagePickerGalleryMediaPicker.maxBytes;

  final GalleryMediaPicker _mediaPicker;

  @override
  Future<RegistrationAvatarPickResult> pickFromGallery() async {
    final result = await _mediaPicker.pickImage();
    return switch (result) {
      GalleryMediaPickCanceled() => const RegistrationAvatarPickCanceled(),
      GalleryMediaPickSuccess(:final bytes) => RegistrationAvatarPickSuccess(
        bytes,
      ),
      GalleryMediaPickFailed(:final failure) => RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(_mapFailure(failure.code)),
      ),
    };
  }

  RegistrationAvatarFailureCode _mapFailure(GalleryMediaFailureCode code) =>
      switch (code) {
        GalleryMediaFailureCode.permissionDenied =>
          RegistrationAvatarFailureCode.permissionDenied,
        GalleryMediaFailureCode.pickerUnavailable =>
          RegistrationAvatarFailureCode.pickerUnavailable,
        GalleryMediaFailureCode.readFailed =>
          RegistrationAvatarFailureCode.readFailed,
        GalleryMediaFailureCode.tooLarge =>
          RegistrationAvatarFailureCode.tooLarge,
        GalleryMediaFailureCode.invalidImage =>
          RegistrationAvatarFailureCode.invalidImage,
      };
}
