import 'dart:typed_data';

import 'package:app_features/feature_search/media/search_image_picker.dart';
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
}

final class _FakeGalleryPicker implements GalleryMediaPicker {
  _FakeGalleryPicker(List<GalleryMediaPickResult> results)
    : _results = List<GalleryMediaPickResult>.of(results);

  final List<GalleryMediaPickResult> _results;

  @override
  Future<GalleryMediaPickResult> pickImage() async => _results.removeAt(0);
}
