import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles and decodes every declared Profile raster asset', () async {
    const expectedSizes = <String, ui.Size>{
      'avatar_romina.png': ui.Size(128, 128),
      'recent_01.png': ui.Size(122, 160),
      'recent_02.png': ui.Size(98, 160),
      'recent_03.png': ui.Size(98, 160),
      'recent_04.png': ui.Size(98, 160),
      'recent_05.png': ui.Size(72, 160),
      'story_01.png': ui.Size(420, 280),
      'story_02.png': ui.Size(280, 420),
      'story_03.png': ui.Size(420, 280),
      'story_04.png': ui.Size(280, 420),
      'product_01.png': ui.Size(360, 240),
      'product_02.png': ui.Size(360, 240),
      'product_03.png': ui.Size(240, 360),
      'product_04.png': ui.Size(360, 240),
      'product_05.png': ui.Size(360, 240),
      'product_06.png': ui.Size(290, 360),
      'product_07.png': ui.Size(290, 360),
      'product_08.png': ui.Size(290, 360),
      'product_09.png': ui.Size(290, 360),
      'product_10.png': ui.Size(290, 360),
      'product_11.png': ui.Size(290, 360),
      'product_12.png': ui.Size(360, 240),
      'product_13.png': ui.Size(360, 240),
      'product_14.png': ui.Size(360, 240),
      'product_15.png': ui.Size(360, 240),
      'product_16.png': ui.Size(240, 360),
      'product_17.png': ui.Size(360, 201),
      'product_18.png': ui.Size(360, 240),
      'product_19.png': ui.Size(360, 240),
      'product_20.png': ui.Size(360, 240),
    };

    for (final entry in expectedSizes.entries) {
      final path = 'packages/app_features/assets/images/profile/${entry.key}';
      final asset = await rootBundle.load(path);
      expect(asset.lengthInBytes, greaterThan(0), reason: path);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(
        ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
        entry.value,
        reason: path,
      );
      frame.image.dispose();
      codec.dispose();
    }
  });
}
