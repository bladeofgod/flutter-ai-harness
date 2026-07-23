import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:app_features/feature_auth/login_flow_scope.dart';
import 'package:app_features/feature_auth/widgets/auth_components.dart';
import 'package:app_features/feature_auth/widgets/login_flow_components.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadAuthFonts);

  testWidgets('matches the email-step reference structure', (tester) async {
    final router = _router(_FakeAuthApi());
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));
    await _pumpRouter(tester, router);

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Good to see you back!'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    final title = tester.widget<Text>(find.text('Login'));
    expect(title.style?.fontSize, 52);
    expect(title.style?.height, 61 / 52);
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.letterSpacing, 0);
    expect(tester.getRect(find.text('Login')).top, closeTo(438, 0.1));

    final emailRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('login-email')),
        matching: find.byType(TextField),
      ),
    );
    final nextRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('login-next')),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(emailRect.top, closeTo(555, 0.2));
    expect(nextRect.top, closeTo(644, 0.2));
    expect(nextRect.size, const Size(335, 61));
  });

  testWidgets('renders the identified user and an intermediate dot state', (
    tester,
  ) async {
    final router = _router(_FakeAuthApi());
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));
    await _pumpRouter(tester, router);
    await _goToPassword(tester);

    expect(find.text('Hello, Romina!!'), findsOneWidget);
    expect(find.text('Type your password'), findsOneWidget);
    expect(find.bySemanticsLabel('Profile photo for Romina'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('login-user-avatar'))).size,
      const Size(105, 105),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('login-user-avatar'))).top,
      closeTo(149, 0.1),
    );

    await tester.enterText(
      find.byKey(const ValueKey('login-password-input')),
      '12345',
    );
    await tester.pump();
    final dots = tester.widget<PasswordDots>(
      find.byKey(const ValueKey('login-password-dots')),
    );
    expect(dots.enteredCharacters, 5);
    expect(dots.showError, isFalse);
    expect(
      find.bySemanticsLabel('Password entry, 5 of 8 characters entered'),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('login-password-input')),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
    final hiddenInputSemantics = tester
        .getSemantics(find.byKey(const ValueKey('login-password-input')))
        .getSemanticsData();
    expect(hiddenInputSemantics.flagsCollection.isTextField, isFalse);
    expect(hiddenInputSemantics.value, isEmpty);

    final controller = LoginFlowScope.of(
      tester.element(find.byKey(const ValueKey('login-password-dots'))),
    );
    controller.passwordFocusNode.unfocus();
    await tester.pump();
    final dotsSemantics = tester.getSemantics(
      find.byKey(const ValueKey('login-password-dots')),
    );
    expect(
      dotsSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: dotsSemantics.id,
      ),
    );
    await tester.pump();
    expect(controller.passwordFocusNode.hasFocus, isTrue);

    final textInputCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        textInputCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('login-password-dots')));
    await tester.pump();
    expect(textInputCalls, contains('TextInput.show'));
  });

  testWidgets('shows eight red dots after a rejected credential', (
    tester,
  ) async {
    final router = _router(
      _FakeAuthApi(
        loginHandler: (_) async =>
            throw const AuthFailure(AuthFailureCode.invalidCredentials),
      ),
    );
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));
    await _pumpRouter(tester, router);
    await _goToPassword(tester);

    await tester.enterText(
      find.byKey(const ValueKey('login-password-input')),
      '12345678',
    );
    await tester.pump();
    await tester.pump();

    final dots = tester.widget<PasswordDots>(
      find.byKey(const ValueKey('login-password-dots')),
    );
    expect(dots.enteredCharacters, 0);
    expect(dots.showError, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('login-password-dots')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color == authErrorColor,
        ),
      ),
      findsNWidgets(8),
    );
    expect(find.byKey(const ValueKey('login-forgot-password')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Password entry, 8 of 8 characters entered'),
      findsOneWidget,
    );
  });

  testWidgets('Recovery switches choices and Next has no business effect', (
    tester,
  ) async {
    final api = _FakeAuthApi(
      loginHandler: (_) async =>
          throw const AuthFailure(AuthFailureCode.invalidCredentials),
    );
    final router = _router(api);
    addTearDown(router.dispose);
    await _setViewport(tester, const Size(375, 812));
    await _pumpRouter(tester, router);
    await _goToRecovery(tester);

    expect(find.text('Password Recovery'), findsOneWidget);
    expect(
      find.text('How you would like to restore your password?'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<PasswordRecoveryChoice>(
            find.byKey(const ValueKey('recovery-sms')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('recovery-email')));
    await tester.pump();
    expect(
      tester
          .widget<PasswordRecoveryChoice>(
            find.byKey(const ValueKey('recovery-email')),
          )
          .selected,
      isTrue,
    );

    final calls = (api.findCount, api.loginCount);
    await tester.tap(find.byKey(const ValueKey('recovery-next')));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, recoveryRoutePath);
    expect((api.findCount, api.loginCount), calls);
  });

  testWidgets('all flow states remain reachable with keyboard constraints', (
    tester,
  ) async {
    const cases = <({Size size, double scale, double inset, int step})>[
      (size: Size(320, 568), scale: 1, inset: 260, step: 0),
      (size: Size(812, 375), scale: 1, inset: 150, step: 1),
      (size: Size(375, 812), scale: 1.3, inset: 300, step: 2),
    ];

    for (final testCase in cases) {
      final api = _FakeAuthApi(
        loginHandler: (_) async =>
            throw const AuthFailure(AuthFailureCode.invalidCredentials),
      );
      final router = _router(api);
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      await _pumpRouter(
        tester,
        router,
        textScale: testCase.scale,
        keyboardInset: testCase.inset,
      );
      expect(
        MediaQuery.viewInsetsOf(tester.element(find.byType(Scaffold))).bottom,
        testCase.inset,
      );

      if (testCase.step >= 1) {
        await _goToPassword(tester);
      }
      if (testCase.step >= 2) {
        await _goToRecovery(tester, fromPassword: true);
      }
      final target = switch (testCase.step) {
        0 => find.text('Cancel'),
        1 => find.byKey(const ValueKey('login-password-dots')),
        _ => find.byKey(const ValueKey('recovery-next')),
      };
      await tester.ensureVisible(target);
      await tester.pump();
      final targetRect = tester.getRect(target);

      expect(tester.takeException(), isNull, reason: '${testCase.size}');
      expect(target, findsOneWidget);
      expect(targetRect.top, greaterThanOrEqualTo(0));
      expect(
        targetRect.bottom,
        lessThanOrEqualTo(testCase.size.height - testCase.inset),
      );

      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });
}

Future<void> _goToPassword(WidgetTester tester) async {
  await tester.enterText(_emailField, 'romina@example.com');
  await tester.ensureVisible(find.byKey(const ValueKey('login-next')));
  await tester.tap(find.byKey(const ValueKey('login-next')));
  await _finishNavigation(tester);
}

Future<void> _goToRecovery(
  WidgetTester tester, {
  bool fromPassword = false,
}) async {
  if (!fromPassword) {
    await _goToPassword(tester);
  }
  await tester.enterText(
    find.byKey(const ValueKey('login-password-input')),
    '12345678',
  );
  await tester.pump();
  await tester.pump();
  final forgot = find.byKey(const ValueKey('login-forgot-password'));
  await tester.ensureVisible(forgot);
  await tester.pump();
  await tester.tap(forgot);
  await _finishNavigation(tester);
}

Finder get _emailField => find.descendant(
  of: find.byKey(const ValueKey('login-email')),
  matching: find.byType(TextField),
);

GoRouter _router(_FakeAuthApi api) => GoRouter(
  initialLocation: loginRoutePath,
  routes: buildLoginRoutes(
    authApi: api,
    onAuthenticated: (_) {},
    onCancel: (_) {},
  ),
);

Future<void> _pumpRouter(
  WidgetTester tester,
  GoRouter router, {
  double textScale = 1,
  double keyboardInset = 0,
}) async {
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

Future<void> _finishNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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
  id: 'fixture-user-romina',
  displayName: 'Romina',
  email: EmailAddress('romina@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('2015550123'),
  avatar: UserAvatar.asset('assets/images/profile/avatar_romina.png'),
);
final _authResult = AuthResult(
  user: _user,
  session: AuthSession(id: 'fixture-session-romina', userId: _user.id),
);

final class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.loginHandler});

  final Future<AuthResult> Function(LoginInput input)? loginHandler;
  var findCount = 0;
  var loginCount = 0;

  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) async {
    findCount += 1;
    return email == _user.email ? _user : null;
  }

  @override
  Future<AuthResult> login(LoginInput input) {
    loginCount += 1;
    return loginHandler?.call(input) ?? Future.value(_authResult);
  }

  @override
  Future<AuthResult> register(RegistrationInput input) =>
      throw UnimplementedError();
}
