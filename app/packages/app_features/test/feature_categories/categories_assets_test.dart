import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles and decodes every localized Categories product', () async {
    for (var number = 1; number <= 9; number += 1) {
      final name = number.toString().padLeft(2, '0');
      final path =
          'packages/app_features/assets/images/catalog/products/categories_product_$name.png';
      final asset = await rootBundle.load(path);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();

      expect(asset.lengthInBytes, greaterThan(0), reason: path);
      expect(frame.image.width, lessThanOrEqualTo(600), reason: path);
      expect(frame.image.height, lessThanOrEqualTo(600), reason: path);

      frame.image.dispose();
      codec.dispose();
    }
  });
}
