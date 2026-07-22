import 'dart:convert';

import 'package:app_features/feature_auth/avatar/image_picker_registration_avatar_picker.dart';
import 'package:app_features/feature_auth/avatar/registration_avatar_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the fixed gallery request and preserves cancellation', () async {
    final imagePicker = _RecordingImagePicker(result: null);
    final picker = ImagePickerRegistrationAvatarPicker(
      imagePicker: imagePicker,
    );

    final result = await picker.pickFromGallery();

    expect(result, isA<RegistrationAvatarPickCanceled>());
    expect(imagePicker.source, ImageSource.gallery);
    expect(imagePicker.maxWidth, ImagePickerRegistrationAvatarPicker.maxWidth);
    expect(
      imagePicker.maxHeight,
      ImagePickerRegistrationAvatarPicker.maxHeight,
    );
    expect(
      imagePicker.imageQuality,
      ImagePickerRegistrationAvatarPicker.imageQuality,
    );
    expect(imagePicker.requestFullMetadata, isFalse);
  });

  test('returns defensive memory bytes without XFile metadata', () async {
    final source = _onePixelPng();
    final picker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(
        result: XFile.fromData(
          source,
          name: 'private-profile-name.png',
          mimeType: 'image/png',
        ),
      ),
    );

    final result =
        await picker.pickFromGallery() as RegistrationAvatarPickSuccess;
    final firstRead = result.bytes;
    firstRead[0] = 0;

    expect(result.bytes, orderedEquals(source));
    expect(result.toString(), isNot(contains('private-profile-name')));
    expect(result.toString(), isNot(contains(source.length.toString())));
  });

  test('rejects a file larger than two MiB', () async {
    final bytes = Uint8List(ImagePickerRegistrationAvatarPicker.maxBytes + 1);
    final picker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(result: XFile.fromData(bytes)),
    );

    final result =
        await picker.pickFromGallery() as RegistrationAvatarPickFailed;

    expect(result.failure.code, RegistrationAvatarFailureCode.tooLarge);
  });

  test('maps invalid image bytes without exposing them', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final picker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(result: XFile.fromData(bytes)),
    );

    final result =
        await picker.pickFromGallery() as RegistrationAvatarPickFailed;

    expect(result.failure.code, RegistrationAvatarFailureCode.invalidImage);
    expect(result.failure.toString(), isNot(contains('[1, 2, 3, 4]')));
  });

  test('maps an unreadable XFile without leaking its path', () async {
    const privatePath = '/missing/private/profile-photo.png';
    final picker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(result: XFile(privatePath)),
    );

    final result =
        await picker.pickFromGallery() as RegistrationAvatarPickFailed;

    expect(result.failure.code, RegistrationAvatarFailureCode.readFailed);
    expect(result.failure.toString(), isNot(contains(privatePath)));
  });

  test('maps denied and unavailable platform failures', () async {
    final deniedPicker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(
        error: PlatformException(code: 'photo_access_denied'),
      ),
    );
    final unavailablePicker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(
        error: PlatformException(code: 'already_active'),
      ),
    );

    final denied =
        await deniedPicker.pickFromGallery() as RegistrationAvatarPickFailed;
    final unavailable =
        await unavailablePicker.pickFromGallery()
            as RegistrationAvatarPickFailed;

    expect(denied.failure.code, RegistrationAvatarFailureCode.permissionDenied);
    expect(
      unavailable.failure.code,
      RegistrationAvatarFailureCode.pickerUnavailable,
    );
  });

  test('does not catch programming Errors', () async {
    final picker = ImagePickerRegistrationAvatarPicker(
      imagePicker: _RecordingImagePicker(
        error: StateError('programming failure'),
      ),
    );

    await expectLater(picker.pickFromGallery(), throwsStateError);
  });
}

final class _RecordingImagePicker extends ImagePicker {
  _RecordingImagePicker({this.result, this.error});

  final XFile? result;
  final Object? error;

  ImageSource? source;
  double? maxWidth;
  double? maxHeight;
  int? imageQuality;
  bool? requestFullMetadata;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    this.maxWidth = maxWidth;
    this.maxHeight = maxHeight;
    this.imageQuality = imageQuality;
    this.requestFullMetadata = requestFullMetadata;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return result;
  }
}

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);
