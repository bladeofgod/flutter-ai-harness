import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadAuthFonts);

  testWidgets('matches the registration reference structure at 375 x 812', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    await _pumpRegistration(tester);

    expect(find.text('Create\nAccount'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Your number'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.bySemanticsLabel('Add profile photo'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Choose country, United Kingdom, +44'),
      findsOneWidget,
    );

    final title = tester.widget<Text>(find.text('Create\nAccount'));
    expect(title.style?.fontSize, 50);
    expect(title.style?.height, 54 / 50);
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.letterSpacing, 0);

    final emailField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('registration-email')),
        matching: find.byType(TextField),
      ),
    );
    expect(emailField.style?.fontFamily, 'packages/app_ui/Poppins');
    expect(emailField.style?.fontSize, 13.83);
    expect(emailField.style?.fontWeight, FontWeight.w500);

    final avatarRect = tester.getRect(
      find.byKey(const ValueKey('registration-avatar')),
    );
    final buttonRect = tester.getRect(find.byType(ElevatedButton));
    expect(avatarRect.size, const Size(90, 90));
    expect(avatarRect.top, closeTo(284, 0.1));
    expect(buttonRect.size, const Size(335, 61));
    expect(buttonRect.top, closeTo(634, 0.1));
  });

  testWidgets('toggles password visibility and switches country', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _setViewport(tester, const Size(375, 812));
    await _pumpRegistration(tester);
    final passwordFinder = find.descendant(
      of: find.byKey(const ValueKey('registration-password')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(passwordFinder).obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(passwordFinder).obscureText, isFalse);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Country or region'), findsOneWidget);
    expect(find.bySemanticsLabel('Germany, +49'), findsOneWidget);
    await tester.tap(find.text('Germany'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.bySemanticsLabel('Choose country, Germany, +49'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('submits one AuthResult through the Route callback', (
    tester,
  ) async {
    AuthResult? authenticated;
    await _setViewport(tester, const Size(375, 812));
    await _pumpRegistration(
      tester,
      onAuthenticated: (result) => authenticated = result,
    );

    await tester.enterText(
      _field('registration-email'),
      'new.shopper@example.com',
    );
    await tester.enterText(_field('registration-password'), 'shopper1');
    await tester.enterText(_field('registration-phone'), '7700900123');
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump();

    expect(authenticated, _authResult);
  });

  testWidgets('Cancel and system back clear the form through one callback', (
    tester,
  ) async {
    var cancelCount = 0;
    await _setViewport(tester, const Size(375, 812));
    await _pumpRegistration(tester, onCancel: () => cancelCount += 1);
    await tester.enterText(_field('registration-email'), 'draft@example.com');
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(cancelCount, 1);
    expect(
      tester.widget<TextField>(_field('registration-email')).controller?.text,
      isEmpty,
    );

    await tester.pumpWidget(const SizedBox());
    cancelCount = 0;
    await _pumpRegistration(tester, onCancel: () => cancelCount += 1);
    await tester.enterText(_field('registration-phone'), '123456');
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(cancelCount, 1);
    expect(
      tester.widget<TextField>(_field('registration-phone')).controller?.text,
      isEmpty,
    );
  });

  testWidgets('keeps Done and Cancel reachable across constrained layouts', (
    tester,
  ) async {
    const cases = <({Size size, double textScale, double keyboardInset})>[
      (size: Size(320, 568), textScale: 1, keyboardInset: 260),
      (size: Size(812, 375), textScale: 1, keyboardInset: 150),
      (size: Size(375, 812), textScale: 1.3, keyboardInset: 300),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      await _pumpRegistration(
        tester,
        textScale: testCase.textScale,
        keyboardInset: testCase.keyboardInset,
      );
      expect(
        MediaQuery.viewInsetsOf(tester.element(find.byType(Scaffold))).bottom,
        testCase.keyboardInset,
      );
      await tester.ensureVisible(find.text('Done'));
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pump();

      final cancelRect = tester.getRect(
        find.byKey(const ValueKey('registration-cancel')),
      );

      expect(tester.takeException(), isNull, reason: '${testCase.size}');
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(cancelRect.top, greaterThanOrEqualTo(0));
      expect(
        cancelRect.bottom,
        lessThanOrEqualTo(testCase.size.height - testCase.keyboardInset),
      );
    }
  });
}

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

Future<void> _pumpRegistration(
  WidgetTester tester, {
  ValueChanged<AuthResult>? onAuthenticated,
  VoidCallback? onCancel,
  double textScale = 1,
  double keyboardInset = 0,
}) async {
  final router = GoRouter(
    initialLocation: registrationRoutePath,
    routes: buildRegistrationRoutes(
      authApi: _FakeAuthApi(),
      onAuthenticated: onAuthenticated ?? (_) {},
      onCancel: (_) => onCancel?.call(),
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 44, bottom: 34),
          viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _loadAuthFonts() async {
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
  final poppins = FontLoader('packages/app_ui/${AppFonts.poppins}')
    ..addFont(
      rootBundle.load('packages/app_ui/assets/fonts/Poppins-Medium.ttf'),
    );
  await Future.wait([raleway.load(), nunitoSans.load(), poppins.load()]);
}

final _user = UserEntity(
  id: 'registered-user',
  displayName: 'New Shopper',
  email: EmailAddress('new.shopper@example.com'),
  callingCode: CountryCallingCode('+44'),
  phoneNumber: PhoneNumber('7700900123'),
  avatar: UserAvatar.asset(
    'assets/images/auth/registration_photo_placeholder.png',
  ),
);
final _authResult = AuthResult(
  user: _user,
  session: AuthSession(id: 'registered-session', userId: _user.id),
);

final class _FakeAuthApi implements AuthApi {
  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) async => null;

  @override
  Future<AuthResult> login(LoginInput input) => throw UnimplementedError();

  @override
  Future<AuthResult> register(RegistrationInput input) async => _authResult;
}
