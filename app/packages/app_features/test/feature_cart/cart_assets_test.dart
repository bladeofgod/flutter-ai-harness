import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cart Figma assets are local and declared by the package', () async {
    const assets = <String>[
      'assets/images/cart/cart_item_01.png',
      'assets/images/cart/cart_item_02.png',
      'assets/images/cart/empty_bag_body.svg',
      'assets/images/cart/empty_bag_handle.svg',
      'assets/images/cart/empty_bag_handle_inner.svg',
      'assets/images/cart/empty_bag_mark.svg',
    ];
    for (final asset in assets) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }

    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/images/cart/'));
    expect(pubspec, isNot(contains('localhost:3845')));
  });
}
