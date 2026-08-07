import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Wishlist reuses bundled Catalog assets without duplicate keys',
    () async {
      const assets = <String, ui.Size>{
        'shop_product_02.png': ui.Size(400, 266),
        'shop_product_03.png': ui.Size(266, 400),
        'shop_product_04.png': ui.Size(266, 400),
      };

      for (final entry in assets.entries) {
        final data = await rootBundle.load(
          'packages/app_features/assets/images/catalog/products/${entry.key}',
        );
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final codec = await ui.instantiateImageCodec(bytes);
        addTearDown(codec.dispose);
        final frame = await codec.getNextFrame();
        addTearDown(frame.image.dispose);

        expect(
          ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
          entry.value,
        );
      }

      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(
        manifest.listAssets().where(
          (asset) => asset.contains('assets/images/wishlist/'),
        ),
        isEmpty,
      );
    },
  );
}
