import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:app_ui/app_ui.dart';
import 'package:demo_app/auth/auth_state.dart';
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

  testWidgets('opens registration from the primary welcome action', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    await tester.tap(find.text("Let's get started"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Create\nAccount'), findsOneWidget);
  });

  testWidgets('opens Login from the secondary welcome action', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const DemoApp());
    await tester.pump();

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Good to see you back!'), findsOneWidget);
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

  testWidgets('disposes an internally created FeaturesRegistry exactly once', (
    tester,
  ) async {
    final mediaApi = _TrackingOrderReviewMediaApi();
    final registry = FeaturesRegistry.local(orderReviewMediaApi: mediaApi);
    final replacementMediaApi = _TrackingOrderReviewMediaApi();
    final replacementRegistry = FeaturesRegistry.local(
      orderReviewMediaApi: replacementMediaApi,
    );
    var factoryCalls = 0;

    await tester.pumpWidget(
      DemoApp(
        featuresRegistryFactory: () {
          factoryCalls += 1;
          return registry;
        },
      ),
    );
    await tester.pumpWidget(
      DemoApp(
        featuresRegistryFactory: () {
          factoryCalls += 1;
          return replacementRegistry;
        },
      ),
    );

    expect(factoryCalls, 1);
    expect(mediaApi.disposeCount, 0);
    expect(replacementMediaApi.disposeCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await registry.dispose();
    expect(mediaApi.disposeCount, 1);
    expect(replacementMediaApi.disposeCount, 0);
    await replacementRegistry.dispose();
  });

  testWidgets('does not dispose an externally owned FeaturesRegistry', (
    tester,
  ) async {
    final mediaApi = _TrackingOrderReviewMediaApi();
    final registry = FeaturesRegistry.local(orderReviewMediaApi: mediaApi);

    await tester.pumpWidget(DemoApp(featuresRegistry: registry));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(mediaApi.disposeCount, 0);
    await registry.dispose();
  });

  testWidgets(
    'detaches reset without disposing external coordinator or registry',
    (tester) async {
      final mediaApi = _TrackingOrderReviewMediaApi();
      final registry = FeaturesRegistry.local(orderReviewMediaApi: mediaApi);
      final coordinator = AuthStateCoordinator();
      addTearDown(() async {
        coordinator.dispose();
        await registry.dispose();
      });
      coordinator.authenticate(_authResult());

      await tester.pumpWidget(
        DemoApp(featuresRegistry: registry, authStateCoordinator: coordinator),
      );
      await tester.pumpWidget(const SizedBox.shrink());

      coordinator.logout();
      await tester.pump();

      expect(mediaApi.clearCount, 0);
      expect(mediaApi.disposeCount, 0);
      expect(coordinator.isLoggedIn, isFalse);
      coordinator.authenticate(_authResult());
      expect(coordinator.isLoggedIn, isTrue);
    },
  );

  testWidgets(
    'detaches before disposing an internal registry owned by the app',
    (tester) async {
      final mediaApi = _TrackingOrderReviewMediaApi();
      final registry = FeaturesRegistry.local(orderReviewMediaApi: mediaApi);
      final coordinator = AuthStateCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.authenticate(_authResult());

      await tester.pumpWidget(
        DemoApp(
          featuresRegistryFactory: () => registry,
          authStateCoordinator: coordinator,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await registry.dispose();

      coordinator.logout();
      await tester.pump();

      expect(mediaApi.disposeCount, 1);
      expect(mediaApi.clearCount, 0);
      expect(coordinator.isLoggedIn, isFalse);
    },
  );

  testWidgets('re-mount registers only the new registry once', (tester) async {
    final oldMediaApi = _TrackingOrderReviewMediaApi();
    final oldRegistry = FeaturesRegistry.local(
      orderReviewMediaApi: oldMediaApi,
    );
    final newMediaApi = _TrackingOrderReviewMediaApi();
    final newRegistry = FeaturesRegistry.local(
      orderReviewMediaApi: newMediaApi,
    );
    final coordinator = AuthStateCoordinator();
    addTearDown(() async {
      coordinator.dispose();
      await oldRegistry.dispose();
      await newRegistry.dispose();
    });
    coordinator.authenticate(_authResult());

    await tester.pumpWidget(
      DemoApp(featuresRegistry: oldRegistry, authStateCoordinator: coordinator),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      DemoApp(featuresRegistry: newRegistry, authStateCoordinator: coordinator),
    );

    coordinator.logout();
    await tester.pump();

    expect(oldMediaApi.clearCount, 0);
    expect(newMediaApi.clearCount, 1);
    expect(oldMediaApi.disposeCount, 0);
    expect(newMediaApi.disposeCount, 0);
  });

  testWidgets('re-mount clears a retained registry after detached logout', (
    tester,
  ) async {
    final mediaApi = _TrackingOrderReviewMediaApi();
    final registry = FeaturesRegistry.local(orderReviewMediaApi: mediaApi);
    final coordinator = AuthStateCoordinator();
    addTearDown(() async {
      coordinator.dispose();
      await registry.dispose();
    });
    coordinator.authenticate(_authResult());

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: coordinator),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.logout();
    await tester.pump();
    expect(mediaApi.clearCount, 0);

    await tester.pumpWidget(
      DemoApp(featuresRegistry: registry, authStateCoordinator: coordinator),
    );
    await tester.pump();

    expect(mediaApi.clearCount, 1);
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

final class _TrackingOrderReviewMediaApi implements OrderReviewMediaApi {
  var clearCount = 0;
  var disposeCount = 0;

  @override
  Future<OrderReviewMediaCaptureOutcome> capture() async =>
      const OrderReviewMediaCancelled();

  @override
  Future<OrderReviewMediaReleaseOutcome> release(
    OrderReviewMediaAttachment attachment,
  ) async => const OrderReviewMediaReleased();

  @override
  Future<void> clearDrafts() async {
    clearCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

AuthResult _authResult() {
  const userId = 'user-romina';
  return AuthResult(
    user: UserEntity(
      id: userId,
      displayName: 'Romina',
      email: EmailAddress('romina@example.com'),
      callingCode: CountryCallingCode('+44'),
      phoneNumber: PhoneNumber('7700900123'),
      avatar: UserAvatar.asset('images/auth/romina.png'),
    ),
    session: AuthSession(id: 'session-user-romina', userId: userId),
  );
}
