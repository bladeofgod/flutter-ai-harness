import 'package:app_data/app_data.dart';
import 'package:test/test.dart';

void main() {
  test('preference values expose stable ids and reject unknown ids', () {
    expect(SettingsCountry.unitedStates.id, 'us');
    expect(SettingsLanguage.simplifiedChinese.id, 'zh-hans');
    expect(SettingsCurrency.usd.id, 'usd');
    expect(SettingsSizeType.international.id, 'international');
    expect(
      () => SettingsCountry.fromId('United States'),
      throwsA(isA<FormatException>()),
    );
  });

  test('ProfileEditInput normalizes name without exposing contact data', () {
    final input = ProfileEditInput(
      displayName: '  Romina  ',
      email: EmailAddress('romina@example.com'),
      callingCode: CountryCallingCode('+1'),
      phoneNumber: PhoneNumber('5551234567'),
      avatar: UserAvatar.asset('assets/images/profile/avatar.png'),
    );

    expect(input.displayName, 'Romina');
    expect(input.toString(), isNot(contains('romina@example.com')));
    expect(input.toString(), isNot(contains('5551234567')));
  });
}
