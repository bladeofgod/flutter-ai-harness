import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Wishlist Figma assets are bundled and decodable', () async {
    const assets = <String, ui.Size>{
      'recent_hat.png': ui.Size(400, 266),
      'recent_pink_dress.png': ui.Size(266, 400),
      'recent_red_dress.png': ui.Size(266, 400),
    };

    for (final entry in assets.entries) {
      final data = await rootBundle.load('assets/images/wishlist/${entry.key}');
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
  });
}
