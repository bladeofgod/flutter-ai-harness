import 'dart:convert';
import 'dart:typed_data';

import 'package:app_features/feature_auth/widgets/registration_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exposes Add profile photo and forwards taps', (tester) async {
    final semantics = tester.ensureSemantics();
    var tapCount = 0;
    await _pumpAvatar(tester, onPressed: () => tapCount += 1);

    expect(find.bySemanticsLabel('Add profile photo'), findsOneWidget);
    await tester.tap(find.byType(InkWell));

    expect(tapCount, 1);
    semantics.dispose();
  });

  testWidgets('renders memory bytes with Change profile photo semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpAvatar(tester, bytes: _onePixelPng(), onPressed: () {});

    expect(find.bySemanticsLabel('Change profile photo'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(image.width, 82);
    expect(image.height, 82);
    semantics.dispose();
  });

  testWidgets('shows a disabled loading state', (tester) async {
    await _pumpAvatar(tester, isPicking: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });
}

Future<void> _pumpAvatar(
  WidgetTester tester, {
  Uint8List? bytes,
  bool isPicking = false,
  VoidCallback? onPressed,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(
        child: RegistrationAvatar(
          bytes: bytes,
          isPicking: isPicking,
          onPressed: onPressed,
        ),
      ),
    ),
  ),
);

Uint8List _onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
  'AQUBAScY42YAAAAASUVORK5CYII=',
);
