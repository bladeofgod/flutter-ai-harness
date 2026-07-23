import 'package:app_data/app_data.dart';
import 'package:app_features/api/current_user_provider.dart';
import 'package:app_features/api/settings_api.dart';
import 'package:app_features/feature_settings/controllers/settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads and updates preferences through the narrow API', () async {
    final api = _FakeSettingsApi();
    final provider = _FakeCurrentUserProvider(_user());
    final controller = _controller(api: api, provider: provider);

    controller.onInit();
    await _flush();
    expect(controller.viewState, isA<SettingsData>());
    expect(provider.listenerCount, 1);

    expect(await controller.setCountry(SettingsCountry.japan), isTrue);
    final data = controller.viewState as SettingsData;
    expect(data.preferences.country, SettingsCountry.japan);
    expect(api.preferences.country, SettingsCountry.japan);

    controller.onClose();
    expect(provider.listenerCount, 0);
  });

  test('updates current user once without changing identity', () async {
    final api = _FakeSettingsApi();
    final provider = _FakeCurrentUserProvider(_user());
    final updatedUsers = <UserEntity>[];
    final controller = _controller(
      api: api,
      provider: provider,
      onUserUpdated: updatedUsers.add,
    );
    controller.onInit();
    await _flush();

    final saved = await controller.updateProfile(
      ProfileEditInput(
        displayName: 'New Shopper',
        email: EmailAddress('new@example.com'),
        callingCode: CountryCallingCode('+44'),
        phoneNumber: PhoneNumber('2071234567'),
        avatar: _user().avatar,
      ),
    );

    expect(saved, isTrue);
    expect(updatedUsers, hasLength(1));
    expect(updatedUsers.single.id, 'user-1');
    expect(updatedUsers.single.displayName, 'New Shopper');
    controller.onClose();
  });

  test(
    'reports Settings failure and retries without losing lifecycle',
    () async {
      final api = _FakeSettingsApi(failLoadCount: 1);
      final provider = _FakeCurrentUserProvider(_user());
      final controller = _controller(api: api, provider: provider);
      controller.onInit();
      await _flush();

      expect(controller.viewState, isA<SettingsError>());
      await controller.load();
      expect(controller.viewState, isA<SettingsData>());
      controller.onClose();
    },
  );

  test('keeps the previous snapshot when a preference update fails', () async {
    final api = _FakeSettingsApi(failUpdateCount: 1);
    final provider = _FakeCurrentUserProvider(_user());
    final controller = _controller(api: api, provider: provider);
    controller.onInit();
    await _flush();
    final before = (controller.viewState as SettingsData).preferences;

    final saved = await controller.setLanguage(SettingsLanguage.german);

    expect(saved, isFalse);
    expect((controller.viewState as SettingsData).preferences, before);
    expect(controller.operationFailure, isNotNull);
    expect(controller.isSaving, isFalse);
    controller.onClose();
  });

  test('delete callback is idempotent', () async {
    final api = _FakeSettingsApi();
    final provider = _FakeCurrentUserProvider(_user());
    var deleteCount = 0;
    final controller = _controller(
      api: api,
      provider: provider,
      onDelete: () => deleteCount += 1,
    );
    controller.onInit();
    await _flush();

    controller.deleteAccount();
    controller.deleteAccount();

    expect(deleteCount, 1);
    controller.onClose();
  });
}

SettingsController _controller({
  required _FakeSettingsApi api,
  required _FakeCurrentUserProvider provider,
  void Function(UserEntity)? onUserUpdated,
  VoidCallback? onDelete,
}) => SettingsController(
  settingsApi: api,
  currentUserProvider: provider,
  onUserUpdated: onUserUpdated ?? (_) {},
  onDeleteAccount: onDelete ?? () {},
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _FakeSettingsApi implements SettingsApi {
  _FakeSettingsApi({this.failLoadCount = 0, this.failUpdateCount = 0});

  int failLoadCount;
  int failUpdateCount;
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
  ) async {
    if (failUpdateCount > 0) {
      failUpdateCount -= 1;
      throw const SettingsFailure(SettingsFailureCode.unavailable);
    }
    return this.preferences = preferences;
  }

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

  final UserEntity? _value;
  int listenerCount = 0;

  @override
  UserEntity? get value => _value;

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
  avatar: UserAvatar.asset('assets/images/profile/profile_avatar.png'),
);
