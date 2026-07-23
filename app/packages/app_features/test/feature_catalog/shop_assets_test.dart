import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles and decodes the localized Big Sale asset', () async {
    const path = 'packages/app_features/assets/images/catalog/big_sale.png';
    final asset = await rootBundle.load(path);
    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    expect(asset.lengthInBytes, greaterThan(0));
    expect(frame.image.width, 1005);
    expect(frame.image.height, 390);

    frame.image.dispose();
    codec.dispose();
  });

  test('bundles and decodes every localized Category image', () async {
    const names = <String>[
      'shoes_02',
      'shoes_03',
      'shoes_04',
      'lingerie_01',
      'lingerie_02',
      'lingerie_03',
      'lingerie_04',
      'hoodies_01',
      'hoodies_02',
      'hoodies_03',
      'hoodies_04',
      'watch_01',
      'watch_02',
      'watch_03',
      'watch_04',
    ];

    for (final name in names) {
      final path =
          'packages/app_features/assets/images/catalog/categories/category_$name.png';
      final asset = await rootBundle.load(path);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      expect(asset.lengthInBytes, greaterThan(0), reason: path);
      expect(frame.image.width, lessThanOrEqualTo(300), reason: path);
      expect(frame.image.height, lessThanOrEqualTo(300), reason: path);

      frame.image.dispose();
      codec.dispose();
    }
  });

  test('bundles and decodes every localized Shop product image', () async {
    for (var number = 1; number <= 6; number += 1) {
      final name = number.toString().padLeft(2, '0');
      final path =
          'packages/app_features/assets/images/catalog/products/shop_product_$name.png';
      final asset = await rootBundle.load(path);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      expect(asset.lengthInBytes, greaterThan(0), reason: path);
      expect(frame.image.width, lessThanOrEqualTo(400), reason: path);
      expect(frame.image.height, lessThanOrEqualTo(400), reason: path);

      frame.image.dispose();
      codec.dispose();
    }
  });
}
