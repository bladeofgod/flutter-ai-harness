import 'dart:typed_data';

import 'package:app_features/api/search_image_picker.dart';
import 'package:app_features/feature_search/api/shared_media_search_image_picker.dart';
import 'package:app_features/shared/media/gallery_media_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps cancellation and success without leaking image bytes', () async {
    final adapter = SharedMediaSearchImagePicker(
      mediaPicker: _FakeGalleryPicker(<GalleryMediaPickResult>[
        const GalleryMediaPickCanceled(),
        GalleryMediaPickSuccess(Uint8List.fromList(<int>[1, 2, 3])),
      ]),
    );

    expect(await adapter.pickFromGallery(), isA<SearchImagePickCanceled>());
    final success = await adapter.pickFromGallery() as SearchImagePickSuccess;
    final firstRead = success.bytes;
    firstRead[0] = 9;
    expect(success.bytes, <int>[1, 2, 3]);
    expect(success.toString(), 'SearchImagePickSuccess(<redacted>)');
  });

  test(
    'maps all stable shared failure codes into the Search boundary',
    () async {
      for (final code in GalleryMediaFailureCode.values) {
        final adapter = SharedMediaSearchImagePicker(
          mediaPicker: _FakeGalleryPicker(<GalleryMediaPickResult>[
            GalleryMediaPickFailed(GalleryMediaFailure(code)),
          ]),
        );

        final result = await adapter.pickFromGallery() as SearchImagePickFailed;
        expect(result.failure.code.name, code.name);
        expect(result.failure.toString(), isNot(contains('path')));
      }
    },
  );

  test('forwards camera capture and lifecycle to the camera adapter', () async {
    final camera = _FakeCameraPicker();
    final adapter = SharedMediaSearchImagePicker(cameraPicker: camera);

    expect(await adapter.capturePhoto(), isA<SearchImagePickCanceled>());
    await adapter.clearDrafts();
    await adapter.dispose();

    expect(camera.captureCount, 1);
    expect(camera.clearCount, 1);
    expect(camera.disposeCount, 1);
  });
}

final class _FakeGalleryPicker implements GalleryMediaPicker {
  _FakeGalleryPicker(List<GalleryMediaPickResult> results)
    : _results = List<GalleryMediaPickResult>.of(results);

  final List<GalleryMediaPickResult> _results;

  @override
  Future<GalleryMediaPickResult> pickImage() async => _results.removeAt(0);
}

final class _FakeCameraPicker implements SearchCameraMediaPicker {
  var captureCount = 0;
  var clearCount = 0;
  var disposeCount = 0;

  @override
  Future<SearchImagePickResult> capturePhoto() async {
    captureCount += 1;
    return const SearchImagePickCanceled();
  }

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
