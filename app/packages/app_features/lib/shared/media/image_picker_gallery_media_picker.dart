import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'gallery_media_picker.dart';

/// 将系统图库收敛为有尺寸、字节和诊断边界的内存图片结果。
final class ImagePickerGalleryMediaPicker implements GalleryMediaPicker {
  ImagePickerGalleryMediaPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  static const double maxWidth = 1024;
  static const double maxHeight = 1024;
  static const int imageQuality = 85;
  static const int maxBytes = 2 * 1024 * 1024;

  final ImagePicker _imagePicker;

  @override
  Future<GalleryMediaPickResult> pickImage() async {
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
      return GalleryMediaPickFailed(
        GalleryMediaFailure(_mapPickerFailure(error.code)),
      );
    }

    if (file == null) {
      return const GalleryMediaPickCanceled();
    }

    final int length;
    try {
      length = await file.length();
    } on IOException {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.readFailed),
      );
    } on PlatformException {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.readFailed),
      );
    }
    if (length > maxBytes) {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.tooLarge),
      );
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on IOException {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.readFailed),
      );
    } on PlatformException {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.readFailed),
      );
    }
    if (bytes.lengthInBytes > maxBytes) {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.tooLarge),
      );
    }

    try {
      await _validateImage(bytes);
    } on Exception {
      return const GalleryMediaPickFailed(
        GalleryMediaFailure(GalleryMediaFailureCode.invalidImage),
      );
    }
    return GalleryMediaPickSuccess(bytes);
  }

  GalleryMediaFailureCode _mapPickerFailure(String code) {
    final normalized = code.toLowerCase();
    if (normalized.contains('denied') || normalized.contains('restricted')) {
      return GalleryMediaFailureCode.permissionDenied;
    }
    return GalleryMediaFailureCode.pickerUnavailable;
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
