import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles and decodes every Promotions-consumed local raster', () async {
    const paths = <String>[
      'packages/app_features/assets/images/catalog/big_sale.png',
      'packages/app_features/assets/images/profile/story_01.png',
      'packages/app_features/assets/images/profile/story_02.png',
      'packages/app_features/assets/images/profile/story_03.png',
      'packages/app_features/assets/images/profile/story_04.png',
      'packages/app_features/assets/images/profile/product_01.png',
      'packages/app_features/assets/images/profile/product_02.png',
      'packages/app_features/assets/images/profile/product_03.png',
      'packages/app_features/assets/images/profile/product_04.png',
      'packages/app_features/assets/images/profile/product_05.png',
      'packages/app_features/assets/images/profile/product_06.png',
      'packages/app_features/assets/images/profile/product_07.png',
      'packages/app_features/assets/images/profile/product_08.png',
      'packages/app_features/assets/images/profile/product_09.png',
    ];

    for (final path in paths) {
      final asset = await rootBundle.load(path);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      expect(asset.lengthInBytes, greaterThan(0), reason: path);
      expect(frame.image.width, greaterThan(0), reason: path);
      expect(frame.image.height, greaterThan(0), reason: path);

      frame.image.dispose();
      codec.dispose();
    }
  });
}
