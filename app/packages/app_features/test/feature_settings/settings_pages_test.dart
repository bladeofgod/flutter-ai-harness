import 'package:app_data/app_data.dart';
import 'package:app_features/api/current_user_provider.dart';
import 'package:app_features/api/settings_api.dart';
import 'package:app_features/feature_settings/routes.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('renders one long Settings page with designed destinations', (
    tester,
  ) async {
    await _setViewport(tester, const Size(375, 812));
    final fixture = await _pumpSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Romina'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Country'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    final scroll = find.byKey(const ValueKey('settings-scroll'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-delete-account')),
      450,
      scrollable: find.descendant(
        of: scroll,
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('About'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-delete-account')),
      findsOneWidget,
    );
    expect(fixture.provider.listenerCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updates a selected preference and keeps it after Back', (
    tester,
  ) async {
    final fixture = await _pumpSettings(tester);

    final countryTile = find.byKey(const ValueKey('settings-country'));
    await Scrollable.ensureVisible(tester.element(countryTile), alignment: 0.5);
    await tester.pump();
    expect(countryTile.hitTestable(), findsOneWidget);
    await tester.tap(countryTile.hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Choose Your Country'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-preference-jp')));
    await tester.pump();
    await tester.pump();
    expect(fixture.api.preferences.country, SettingsCountry.japan);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Japan'), findsOneWidget);
  });

  testWidgets('edits Profile and publishes one same-id user update', (
    tester,
  ) async {
    final fixture = await _pumpSettings(tester);

    await tester.tap(find.byKey(const ValueKey('settings-profile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('settings-profile-name')),
      'New Shopper',
    );
    await tester.tap(find.byKey(const ValueKey('settings-profile-save')));
    await tester.pumpAndSettle();

    expect(fixture.updatedUsers, hasLength(1));
    expect(fixture.updatedUsers.single.id, 'user-1');
    expect(fixture.updatedUsers.single.displayName, 'New Shopper');
    expect(fixture.router.routeInformationProvider.value.uri.path, '/settings');
  });

  testWidgets('Delete Cancel keeps session and Confirm calls root once', (
    tester,
  ) async {
    final fixture = await _pumpSettings(tester);
    final scroll = find.byKey(const ValueKey('settings-scroll'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-delete-account')),
      450,
      scrollable: find.descendant(
        of: scroll,
        matching: find.byType(Scrollable),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-delete-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings-delete-cancel')));
    await tester.pumpAndSettle();
    expect(fixture.deleteCount, 0);

    await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-delete-confirm')));
    await tester.pumpAndSettle();
    expect(fixture.deleteCount, 1);
  });

  testWidgets('opens all independent sub routes and supports Back', (
    tester,
  ) async {
    const destinations = <({String key, String label, String title})>[
      (
        key: 'settings-language',
        label: 'Language',
        title: 'Choose Your Language',
      ),
      (
        key: 'settings-currency',
        label: 'Currency',
        title: 'Choose Your Currency',
      ),
      (key: 'settings-size-type', label: 'Size Type', title: 'Size Types'),
      (key: 'settings-about', label: 'About', title: 'AI-Harness Shoppe Demo'),
    ];
    for (final destination in destinations) {
      await tester.pumpWidget(const SizedBox());
      final fixture = await _pumpSettings(tester);
      final tile = find.byKey(ValueKey<String>(destination.key));
      await tester.scrollUntilVisible(
        tile,
        300,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('settings-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      expect(tile.hitTestable(), findsOneWidget, reason: destination.label);
      await tester.tap(tile.hitTestable());
      await tester.pumpAndSettle();
      expect(find.text(destination.title), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-scroll')), findsOneWidget);
      fixture.router.dispose();
    }
  });

  testWidgets('has no overflow on compact, landscape and scaled viewports', (
    tester,
  ) async {
    const cases = <({Size size, double scale})>[
      (size: Size(320, 568), scale: 1),
      (size: Size(812, 375), scale: 1),
      (size: Size(375, 812), scale: 1.3),
    ];
    for (final testCase in cases) {
      await tester.pumpWidget(const SizedBox());
      await _setViewport(tester, testCase.size);
      final fixture = await _pumpSettings(tester, textScale: testCase.scale);
      final scroll = find.byKey(const ValueKey('settings-scroll'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-delete-account')),
        500,
        scrollable: find.descendant(
          of: scroll,
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull, reason: '${testCase.size}');
      fixture.router.dispose();
    }
  });

  testWidgets('keeps Profile fields reachable above keyboard insets', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 568));
    await _pumpSettings(tester, keyboardInset: 240);

    await tester.tap(find.byKey(const ValueKey('settings-profile')));
    await tester.pumpAndSettle();
    final phone = find.byKey(const ValueKey('settings-profile-phone'));
    await tester.scrollUntilVisible(
      phone,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('settings-profile-form')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(phone.hitTestable(), findsOneWidget);
    expect(tester.getRect(phone).bottom, lessThanOrEqualTo(328));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows retry state and recovers', (tester) async {
    final api = _FakeSettingsApi(failLoadCount: 1);
    await _pumpSettings(tester, api: api);

    expect(find.text('Unable to load Settings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-retry')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Romina'), findsOneWidget);
  });
}

Future<_SettingsFixture> _pumpSettings(
  WidgetTester tester, {
  _FakeSettingsApi? api,
  double textScale = 1,
  double keyboardInset = 0,
}) async {
  final resolvedApi = api ?? _FakeSettingsApi();
  final provider = _FakeCurrentUserProvider(_user());
  final updatedUsers = <UserEntity>[];
  var deleteCount = 0;
  final router = GoRouter(
    initialLocation: settingsRoutePath,
    routes: buildSettingsRoutes(
      settingsApi: resolvedApi,
      currentUserProvider: provider,
      onUserUpdated: (user) {
        updatedUsers.add(user);
        provider.setValue(user);
      },
      onDeleteAccount: () => deleteCount += 1,
    ),
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _SettingsFixture(
    api: resolvedApi,
    provider: provider,
    router: router,
    updatedUsers: updatedUsers,
    getDeleteCount: () => deleteCount,
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

final class _SettingsFixture {
  const _SettingsFixture({
    required this.api,
    required this.provider,
    required this.router,
    required this.updatedUsers,
    required int Function() getDeleteCount,
  }) : _getDeleteCount = getDeleteCount;

  final _FakeSettingsApi api;
  final _FakeCurrentUserProvider provider;
  final GoRouter router;
  final List<UserEntity> updatedUsers;
  final int Function() _getDeleteCount;

  int get deleteCount => _getDeleteCount();
}

final class _FakeSettingsApi implements SettingsApi {
  _FakeSettingsApi({this.failLoadCount = 0});

  int failLoadCount;
  SettingsPreferences preferences =
      SettingsFixtureHandler.defaultSettingsPreferences;

  @override
  Future<SettingsPreferences> load() async {
    if (failLoadCount > 0) {
      failLoadCount -= 1;
      throw const SettingsFailure(SettingsFailureCode.unavailable);
    }
    return preferences;
  }

  @override
  Future<SettingsPreferences> updatePreferences(
    SettingsPreferences preferences,
  ) async => this.preferences = preferences;

  @override
  Future<UserEntity> updateProfile({
    required UserEntity currentUser,
    required ProfileEditInput input,
  }) async => UserEntity(
    id: currentUser.id,
    displayName: input.displayName,
    email: input.email,
    callingCode: input.callingCode,
    phoneNumber: input.phoneNumber,
    avatar: input.avatar,
  );
}

final class _FakeCurrentUserProvider extends ChangeNotifier
    implements CurrentUserProvider {
  _FakeCurrentUserProvider(this._value);

  UserEntity? _value;
  int listenerCount = 0;

  @override
  UserEntity? get value => _value;

  void setValue(UserEntity? value) {
    _value = value;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    listenerCount += 1;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount -= 1;
    super.removeListener(listener);
  }
}

UserEntity _user() => UserEntity(
  id: 'user-1',
  displayName: 'Romina',
  email: EmailAddress('romina@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('5551234567'),
  avatar: UserAvatar.asset('assets/images/profile/avatar_romina.png'),
);
