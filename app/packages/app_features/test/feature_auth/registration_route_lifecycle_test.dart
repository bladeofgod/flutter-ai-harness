import 'package:app_data/app_data.dart';
import 'package:app_features/api/auth_api.dart';
import 'package:app_features/feature_auth/avatar/registration_avatar_picker.dart';
import 'package:app_features/feature_auth/controllers/registration_controller.dart';
import 'package:app_features/feature_auth/pages/registration_page.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'route builder rebuild keeps one Controller until the route leaves',
    (tester) async {
      final avatarData = await rootBundle.load(
        'packages/app_features/assets/images/auth/'
        'registration_photo_placeholder.png',
      );
      final avatarBytes = avatarData.buffer.asUint8List(
        avatarData.offsetInBytes,
        avatarData.lengthInBytes,
      );
      final parentRebuild = ValueNotifier<int>(0);
      addTearDown(parentRebuild.dispose);
      final controllers = <_TrackingRegistrationController>[];
      var routeBuildCount = 0;
      final router = _router(
        parentRebuild: parentRebuild,
        onRouteBuild: () => routeBuildCount += 1,
        createController: () {
          final controller = _TrackingRegistrationController(
            authApi: const _SuccessfulAuthApi(),
            avatarPicker: _SuccessfulAvatarPicker(avatarBytes),
          );
          controllers.add(controller);
          return controller;
        },
      );
      addTearDown(router.dispose);

      await _pumpRouter(tester, router);
      expect(routeBuildCount, 1);
      expect(controllers, hasLength(1));
      final controller = controllers.single;
      controller.emailController.text = 'draft@example.com';
      controller.passwordController.text = 'shopper1';
      await controller.pickAvatar();
      await tester.pump();
      expect(controller.avatarBytes, isNotEmpty);

      parentRebuild.value += 1;
      await tester.pump();

      expect(routeBuildCount, greaterThan(1));
      expect(controllers, hasLength(1));
      expect(controllers.single, same(controller));
      expect(controller.closeCount, 0);

      router.go('/done');
      await _finishNavigation(tester);

      _expectClosedOnce(controller);
    },
  );

  testWidgets('Cancel closes the route Controller exactly once', (
    tester,
  ) async {
    final controllers = <_TrackingRegistrationController>[];
    final router = _router(
      createController: () => _trackController(controllers),
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);

    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await _finishNavigation(tester);

    expect(find.text('Route destination'), findsOneWidget);
    _expectClosedOnce(controllers.single);
  });

  testWidgets('system back closes the route Controller exactly once', (
    tester,
  ) async {
    final controllers = <_TrackingRegistrationController>[];
    final router = _router(
      createController: () => _trackController(controllers),
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);

    await tester.binding.handlePopRoute();
    await _finishNavigation(tester);

    expect(find.text('Route destination'), findsOneWidget);
    _expectClosedOnce(controllers.single);
  });

  testWidgets('authentication transition closes the Controller exactly once', (
    tester,
  ) async {
    final controllers = <_TrackingRegistrationController>[];
    final router = _router(
      createController: () => _trackController(controllers),
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);

    await tester.enterText(_field('registration-email'), 'new@example.com');
    await tester.enterText(_field('registration-password'), 'shopper1');
    await tester.enterText(_field('registration-phone'), '7700900123');
    await tester.ensureVisible(find.text('Done'));
    await tester.tap(find.text('Done'));
    await _finishNavigation(tester);

    expect(find.text('Route destination'), findsOneWidget);
    _expectClosedOnce(controllers.single);
  });
}

GoRouter _router({
  required _TrackingRegistrationController Function() createController,
  ValueListenable<int>? parentRebuild,
  VoidCallback? onRouteBuild,
}) => GoRouter(
  initialLocation: '/register',
  routes: [
    GoRoute(
      path: '/register',
      builder: (context, state) {
        Widget buildRouteScope() {
          onRouteBuild?.call();
          return RegistrationPage(
            createController: createController,
            onAuthenticated: (_) => context.go('/done'),
            onCancel: () => context.go('/done'),
          );
        }

        final rebuild = parentRebuild;
        if (rebuild == null) {
          return buildRouteScope();
        }
        return ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (context, value, child) => buildRouteScope(),
        );
      },
    ),
    GoRoute(
      path: '/done',
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('Route destination'))),
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

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey<String>(key)),
  matching: find.byType(TextField),
);

_TrackingRegistrationController _trackController(
  List<_TrackingRegistrationController> controllers,
) {
  final controller = _TrackingRegistrationController(
    authApi: const _SuccessfulAuthApi(),
    avatarPicker: const _CanceledAvatarPicker(),
  );
  controllers.add(controller);
  return controller;
}

void _expectClosedOnce(_TrackingRegistrationController controller) {
  expect(controller.closeCount, 1);
  expect(controller.emailController.text, isEmpty);
  expect(controller.passwordController.text, isEmpty);
  expect(controller.phoneController.text, isEmpty);
  expect(controller.avatarBytes, isNull);
  expect(
    () => controller.emailController.addListener(() {}),
    throwsFlutterError,
  );
}

final class _TrackingRegistrationController extends RegistrationController {
  _TrackingRegistrationController({
    required super.authApi,
    required super.avatarPicker,
  });

  var closeCount = 0;

  @override
  void onClose() {
    closeCount += 1;
    super.onClose();
  }
}

final class _SuccessfulAuthApi implements AuthApi {
  const _SuccessfulAuthApi();

  @override
  Future<UserEntity?> findAccountByEmail(EmailAddress email) async => null;

  @override
  Future<AuthResult> login(LoginInput input) => throw UnimplementedError();

  @override
  Future<AuthResult> register(RegistrationInput input) async => _authResult;
}

final class _SuccessfulAvatarPicker implements RegistrationAvatarPicker {
  _SuccessfulAvatarPicker(Uint8List bytes)
    : _result = RegistrationAvatarPickSuccess(bytes);

  final RegistrationAvatarPickResult _result;

  @override
  Future<RegistrationAvatarPickResult> pickFromGallery() async => _result;
}

final class _CanceledAvatarPicker implements RegistrationAvatarPicker {
  const _CanceledAvatarPicker();

  @override
  Future<RegistrationAvatarPickResult> pickFromGallery() async =>
      const RegistrationAvatarPickCanceled();
}

final _user = UserEntity(
  id: 'registered-user',
  displayName: 'New Shopper',
  email: EmailAddress('new@example.com'),
  callingCode: CountryCallingCode('+44'),
  phoneNumber: PhoneNumber('7700900123'),
  avatar: UserAvatar.asset(RegistrationController.defaultAvatarAsset),
);
final _authResult = AuthResult(
  user: _user,
  session: AuthSession(id: 'registered-session', userId: _user.id),
);
