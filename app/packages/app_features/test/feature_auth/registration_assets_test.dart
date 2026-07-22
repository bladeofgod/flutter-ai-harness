import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles and parses the registration bubbles SVG safely', () async {
    const path =
        'packages/app_features/assets/images/auth/registration_bubbles.svg';
    final asset = await rootBundle.load(path);
    expect(asset.lengthInBytes, greaterThan(0), reason: path);

    final source = utf8.decode(
      asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
    );
    final sourceWithoutSvgNamespace = source.replaceAll(
      'http://www.w3.org/2000/svg',
      '',
    );
    final absoluteLocalPath = RegExp(
      r'(?:file:(?:/{2,3})|[a-z]:[\\/]|/(?:Users|home|private|tmp|var|opt)/)',
      caseSensitive: false,
    );

    expect(source.toLowerCase(), isNot(contains('localhost')), reason: path);
    expect(
      RegExp(
        r'https?://',
        caseSensitive: false,
      ).hasMatch(sourceWithoutSvgNamespace),
      isFalse,
      reason: path,
    );
    expect(
      absoluteLocalPath.hasMatch(sourceWithoutSvgNamespace),
      isFalse,
      reason: path,
    );
    expect(
      RegExp(r'var\s*\(\s*--fill', caseSensitive: false).hasMatch(source),
      isFalse,
      reason: path,
    );

    addTearDown(svg.cache.clear);
    final compiledSvg = await SvgStringLoader(source).loadBytes(null);
    expect(compiledSvg.lengthInBytes, greaterThan(0), reason: path);
  });

  test(
    'bundles and decodes registration raster assets at expected sizes',
    () async {
      const expectedSizes = <String, ui.Size>{
        'registration_photo_placeholder.png': ui.Size(180, 180),
        'flag_united_kingdom.png': ui.Size(90, 60),
      };

      for (final entry in expectedSizes.entries) {
        final path = 'packages/app_features/assets/images/auth/${entry.key}';
        final asset = await rootBundle.load(path);
        expect(asset.lengthInBytes, greaterThan(0), reason: path);
        final bytes = asset.buffer.asUint8List(
          asset.offsetInBytes,
          asset.lengthInBytes,
        );
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(
              ui.Size(
                frame.image.width.toDouble(),
                frame.image.height.toDouble(),
              ),
              entry.value,
              reason: path,
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    },
  );
}
