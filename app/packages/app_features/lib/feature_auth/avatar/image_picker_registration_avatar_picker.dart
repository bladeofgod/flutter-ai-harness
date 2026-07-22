import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'registration_avatar_picker.dart';

/// 将 Flutter 官方 Image Picker 收敛为注册流程的平台中立头像结果。
final class ImagePickerRegistrationAvatarPicker
    implements RegistrationAvatarPicker {
  ImagePickerRegistrationAvatarPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  static const double maxWidth = 1024;
  static const double maxHeight = 1024;
  static const int imageQuality = 85;
  static const int maxBytes = 2 * 1024 * 1024;

  final ImagePicker _imagePicker;

  @override
  Future<RegistrationAvatarPickResult> pickFromGallery() async {
    final XFile? file;
    try {
      file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
        requestFullMetadata: false,
      );
    } on PlatformException catch (error) {
      return RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(_mapPickerFailure(error.code)),
      );
    }

    if (file == null) {
      return const RegistrationAvatarPickCanceled();
    }

    final int length;
    try {
      length = await file.length();
    } on IOException {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.readFailed),
      );
    } on PlatformException {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.readFailed),
      );
    }
    if (length > maxBytes) {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.tooLarge),
      );
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on IOException {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.readFailed),
      );
    } on PlatformException {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.readFailed),
      );
    }
    if (bytes.lengthInBytes > maxBytes) {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.tooLarge),
      );
    }

    try {
      await _validateImage(bytes);
    } on Exception {
      return const RegistrationAvatarPickFailed(
        RegistrationAvatarFailure(RegistrationAvatarFailureCode.invalidImage),
      );
    }
    return RegistrationAvatarPickSuccess(bytes);
  }

  RegistrationAvatarFailureCode _mapPickerFailure(String code) {
    final normalized = code.toLowerCase();
    if (normalized.contains('denied') || normalized.contains('restricted')) {
      return RegistrationAvatarFailureCode.permissionDenied;
    }
    return RegistrationAvatarFailureCode.pickerUnavailable;
  }

  Future<void> _validateImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } finally {
      codec.dispose();
    }
  }
}
