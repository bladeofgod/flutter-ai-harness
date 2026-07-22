import 'package:app_data/app_data.dart';
import 'package:app_features/app_features.dart';
import 'package:app_features/feature_auth/login_flow_scope.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('keeps one scope across all login flow routes', (tester) async {
    final api = _FakeAuthApi(
      loginHandler: (_) async =>
          throw const AuthFailure(AuthFailureCode.invalidCredentials),
    );
    var cancelCount = 0;
    final router = _router(
      api: api,
      onCancel: (context) {
        cancelCount += 1;
        context.go('/outside');
      },
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);
    final controller = LoginFlowScope.of(
      tester.element(find.byKey(const ValueKey('login-email'))),
    );

    await tester.enterText(_textField('login-email'), 'romina@example.com');
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await _finishNavigation(tester);

    expect(router.routeInformationProvider.value.uri.path, passwordRoutePath);
    expect(
      LoginFlowScope.of(
        tester.element(find.byKey(const ValueKey('login-password-input'))),
      ),
      same(controller),
    );

    await tester.enterText(
      find.byKey(const ValueKey('login-password-input')),
      '12345678',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('login-forgot-password')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('login-forgot-password')));
    await _finishNavigation(tester);

    expect(router.routeInformationProvider.value.uri.path, recoveryRoutePath);
    expect(
      LoginFlowScope.of(
        tester.element(find.byKey(const ValueKey('recovery-sms'))),
      ),
      same(controller),
    );
    expect(controller.enteredPasswordCharacters, 0);

    await tester.tap(find.byKey(const ValueKey('recovery-email')));
    await tester.pump();
    final callsBeforeNext = (api.findCount, api.loginCount);
    await tester.tap(find.byKey(const ValueKey('recovery-next')));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, recoveryRoutePath);
    expect((api.findCount, api.loginCount), callsBeforeNext);

    await tester.tap(find.text('Cancel'));
    await _finishNavigation(tester);
    expect(router.routeInformationProvider.value.uri.path, passwordRoutePath);
    expect(controller.isClosed, isFalse);
    expect(controller.recognizedUser, _user);
    expect(controller.enteredPasswordCharacters, 0);

    controller.passwordFocusNode.unfocus();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await _finishNavigation(tester);
    expect(router.routeInformationProvider.value.uri.path, loginRoutePath);
    expect(controller.emailController.text, isNotEmpty);
    expect(controller.isClosed, isFalse);

    await tester.tap(find.text('Cancel'));
    await _finishNavigation(tester);
    expect(cancelCount, 1);
    expect(find.text('Outside login flow'), findsOneWidget);
    expect(controller.isClosed, isTrue);
    expect(controller.emailController.text, isEmpty);
    expect(controller.passwordController.text, isEmpty);
  });

  testWidgets('direct later-step locations synchronously redirect to login', (
    tester,
  ) async {
    for (final location in [passwordRoutePath, recoveryRoutePath]) {
      final api = _FakeAuthApi();
      final router = _router(api: api, initialLocation: location);
      await _pumpRouter(tester, router);

      expect(router.routeInformationProvider.value.uri.path, loginRoutePath);
      expect(find.byKey(const ValueKey('login-email')), findsOneWidget);
      expect(api.findCount, 0);
      expect(api.loginCount, 0);

      await tester.pumpWidget(const SizedBox());
      router.dispose();
    }
  });

  testWidgets('rejects missing, mismatched, and stale flow access', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    final router = _router(api: api);
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);
    var controller = LoginFlowScope.of(
      tester.element(find.byKey(const ValueKey('login-email'))),
    );

    await tester.enterText(_textField('login-email'), 'romina@example.com');
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await _finishNavigation(tester);
    final rominaAccess = router.routerDelegate.currentConfiguration.extra;
    expect(rominaAccess, isNotNull);

    controller.resetFlow();
    final callsBeforeMissingUser = (api.findCount, api.loginCount);
    router.go(passwordRoutePath, extra: rominaAccess);
    await _finishNavigation(tester);
    expect(router.routeInformationProvider.value.uri.path, loginRoutePath);
    expect((api.findCount, api.loginCount), callsBeforeMissingUser);

    await tester.enterText(_textField('login-email'), 'second@example.com');
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await _finishNavigation(tester);
    final secondUserAccess = router.routerDelegate.currentConfiguration.extra;
    expect(secondUserAccess, isNotNull);
    router.go(loginRoutePath);
    await _finishNavigation(tester);

    final callsBeforeMismatch = (api.findCount, api.loginCount);
    router.go(passwordRoutePath, extra: rominaAccess);
    await _finishNavigation(tester);
    expect(router.routeInformationProvider.value.uri.path, loginRoutePath);
    expect((api.findCount, api.loginCount), callsBeforeMismatch);

    router.go('/outside');
    await _finishNavigation(tester);
    expect(controller.isClosed, isTrue);
    final callsBeforeStaleAccess = (api.findCount, api.loginCount);
    router.go(recoveryRoutePath, extra: secondUserAccess);
    await _finishNavigation(tester);
    expect(router.routeInformationProvider.value.uri.path, loginRoutePath);
    expect((api.findCount, api.loginCount), callsBeforeStaleAccess);

    controller = LoginFlowScope.of(
      tester.element(find.byKey(const ValueKey('login-email'))),
    );
    expect(controller.recognizedUser, isNull);
  });

  testWidgets('successful flow only returns one AuthResult to root assembly', (
    tester,
  ) async {
    final api = _FakeAuthApi();
    late final GoRouter router;
    var authenticatedCount = 0;
    AuthResult? authenticated;
    router = _router(
      api: api,
      onAuthenticated: (result) {
        authenticatedCount += 1;
        authenticated = result;
        router.go('/outside');
      },
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);
    final controller = LoginFlowScope.of(
      tester.element(find.byKey(const ValueKey('login-email'))),
    );

    await tester.enterText(_textField('login-email'), 'romina@example.com');
    await tester.tap(find.byKey(const ValueKey('login-next')));
    await _finishNavigation(tester);
    await tester.enterText(
      find.byKey(const ValueKey('login-password-input')),
      '12345678',
    );
    await _finishNavigation(tester);

    expect(authenticatedCount, 1);
    expect(authenticated, _authResult);
    expect(api.loginCount, 1);
    expect(find.text('Outside login flow'), findsOneWidget);
    expect(controller.isClosed, isTrue);
  });
}

GoRouter _router({
  required _FakeAuthApi api,
  String initialLocation = loginRoutePath,
  ValueChanged<AuthResult>? onAuthenticated,
  void Function(BuildContext context)? onCancel,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ...buildLoginRoutes(
      authApi: api,
      onAuthenticated: onAuthenticated ?? (_) {},
      onCancel: onCancel ?? (context) => context.go('/outside'),
    ),
    GoRoute(
      path: '/outside',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('Outside login flow'))),
    ),
  ],
);

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 812);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
  await tester.pump();
}

Future<void> _finishNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Finder _textField(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

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
final _secondUser = UserEntity(
  id: 'fixture-user-second',
  displayName: 'Second',
  email: EmailAddress('second@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('2015550199'),
  avatar: UserAvatar.asset('assets/images/profile/avatar_romina.png'),
);

final class _FakeAuthApi implements AuthApi {
  _FakeAuthApi({this.loginHandler});

  final Future<AuthResult> Function(LoginInput input)? loginHandler;
  var findCount = 0;
  var loginCount = 0;

  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) async {
    findCount += 1;
    if (email == _user.email) {
      return _user;
    }
    if (email == _secondUser.email) {
      return _secondUser;
    }
    return null;
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
