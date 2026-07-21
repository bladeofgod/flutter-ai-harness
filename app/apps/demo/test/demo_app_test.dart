import 'package:app_ui/app_ui.dart';
import 'package:demo_app/demo_app.dart';
import 'package:demo_app/main.dart' as demo_entrypoint;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadShoppeFonts);

  testWidgets('renders the Shoppe welcome screen', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    expect(find.text('Shoppe'), findsOneWidget);
    expect(find.text("Let's get started"), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('keeps welcome actions inert when no callbacks are supplied', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    await tester.tap(find.text("Let's get started"));
    await tester.tap(find.text('I already have an account'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Shoppe'), findsOneWidget);
  });

  testWidgets('forwards welcome actions when the shell wires them', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    var getStartedCount = 0;
    var signInCount = 0;
    await tester.pumpWidget(
      DemoApp(
        onGetStarted: () => getStartedCount += 1,
        onSignIn: () => signInCount += 1,
      ),
    );
    await tester.pump();

    await tester.tap(find.text("Let's get started"));
    await tester.tap(find.text('I already have an account'));

    expect(getStartedCount, 1);
    expect(signInCount, 1);
  });

  testWidgets('selects the 3x Shoppe brand asset on a 3x device', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1125, 2436);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final key = await image.image.obtainKey(
      const ImageConfiguration(devicePixelRatio: 3),
    );

    expect(key, isA<AssetBundleImageKey>());
    expect((key as AssetBundleImageKey).scale, 3);
  });

  testWidgets('main reuses the Flutter test binding', (tester) async {
    _setPhoneViewport(tester);
    demo_entrypoint.main();
    await tester.pump();

    expect(find.text('Shoppe'), findsOneWidget);
  });
}

Future<void> _loadShoppeFonts() async {
  final raleway = FontLoader('packages/app_ui/${AppFonts.raleway}')
    ..addFont(
      rootBundle.load(
        'packages/app_ui/assets/fonts/raleway/Raleway-Variable.ttf',
      ),
    );
  final nunitoSans = FontLoader('packages/app_ui/${AppFonts.nunitoSans}')
    ..addFont(
      rootBundle.load(
        'packages/app_ui/assets/fonts/nunito_sans/NunitoSans-Variable.ttf',
      ),
    );

  await Future.wait([raleway.load(), nunitoSans.load()]);
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.reset);
}
