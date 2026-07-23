import 'package:app_core/app_core.dart';
import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test(
    'loads defaults, updates in memory, and reconstruction resets',
    () async {
      final first = _source(SettingsFixtureHandler());
      final initial = await first.load();
      final changed = initial.copyWith(
        country: SettingsCountry.japan,
        language: SettingsLanguage.japanese,
        currency: SettingsCurrency.jpy,
        sizeType: SettingsSizeType.unitedStates,
        notificationsEnabled: false,
      );

      expect(initial, SettingsFixtureHandler.defaultSettingsPreferences);
      expect(await first.updatePreferences(changed), changed);
      expect(await first.load(), changed);
      expect(
        await _source(SettingsFixtureHandler()).load(),
        SettingsFixtureHandler.defaultSettingsPreferences,
      );
    },
  );

  test('updates Profile while preserving the authenticated user id', () async {
    final source = _source(SettingsFixtureHandler());
    final user = _user();
    final updated = await source.updateProfile(
      currentUser: user,
      input: ProfileEditInput(
        displayName: 'New Shopper',
        email: EmailAddress('new@example.com'),
        callingCode: CountryCallingCode('+44'),
        phoneNumber: PhoneNumber('2071234567'),
        avatar: user.avatar,
      ),
    );

    expect(updated.id, user.id);
    expect(updated.displayName, 'New Shopper');
    expect(updated.email, EmailAddress('new@example.com'));
    expect(updated.callingCode, CountryCallingCode('+44'));
  });

  test('uses stable request keys', () async {
    final transport = _RecordingTransport();
    final source = SettingsLocalDataSource(
      apiClient: ApiClient(transport: transport),
    );
    final preferences = SettingsFixtureHandler.defaultSettingsPreferences;

    await source.load();
    await source.updatePreferences(preferences);
    await source.updateProfile(currentUser: _user(), input: _profileInput());

    expect(transport.keys, <String>[
      'settings.preferences.load',
      'settings.preferences.update',
      'settings.profile.update',
    ]);
  });

  test(
    'maps malformed payload and rejected mutation to stable failures',
    () async {
      final malformed = SettingsLocalDataSource(
        apiClient: ApiClient(transport: const _PayloadTransport(<Object?>[])),
      );
      await expectLater(
        malformed.load(),
        throwsA(const SettingsFailure(SettingsFailureCode.invalidResponse)),
      );

      final handler = SettingsFixtureHandler();
      final response = await handler.handle(
        const ApiRequest(
          key: SettingsFixtureHandler.updatePreferencesKey,
          payload: <String, Object?>{},
        ),
      );
      expect(response, isA<ApiError<Object?>>());
      expect(
        await _source(handler).load(),
        SettingsFixtureHandler.defaultSettingsPreferences,
      );
    },
  );
}

SettingsLocalDataSource _source(SettingsFixtureHandler handler) =>
    SettingsLocalDataSource(
      apiClient: ApiClient(
        transport: FixtureApiTransport(
          handlers: <FixtureRequestHandler>[handler],
        ),
      ),
    );

UserEntity _user() => UserEntity(
  id: 'user-1',
  displayName: 'Romina',
  email: EmailAddress('romina@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('5551234567'),
  avatar: UserAvatar.asset('assets/images/profile/profile_avatar.png'),
);

ProfileEditInput _profileInput() => ProfileEditInput(
  displayName: 'Romina',
  email: EmailAddress('romina@example.com'),
  callingCode: CountryCallingCode('+1'),
  phoneNumber: PhoneNumber('5551234567'),
  avatar: UserAvatar.asset('assets/images/profile/profile_avatar.png'),
);

final class _PayloadTransport implements ApiTransport {
  const _PayloadTransport(this.payload);

  final Object? payload;

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async =>
      ApiResponse<Object?>.success(payload);
}

final class _RecordingTransport implements ApiTransport {
  final List<String> keys = <String>[];

  @override
  Future<ApiResponse<Object?>> send(ApiRequest request) async {
    keys.add(request.key);
    return switch (request.key) {
      SettingsFixtureHandler.loadKey ||
      SettingsFixtureHandler.updatePreferencesKey =>
        ApiResponse<Object?>.success(<String, Object?>{
          'countryId': 'us',
          'languageId': 'en',
          'currencyId': 'usd',
          'sizeTypeId': 'international',
          'notificationsEnabled': true,
        }),
      SettingsFixtureHandler.updateProfileKey => ApiResponse<Object?>.success(
        request.payload,
      ),
      _ => throw UnknownApiRequestException(request.key),
    };
  }
}
