import 'package:app_data/app_data.dart';

/// 注册表单提供的本地国家/地区选项。
final class RegistrationCountry {
  const RegistrationCountry({
    required this.code,
    required this.name,
    required this.callingCode,
    required this.flagEmoji,
  });

  final String code;
  final String name;
  final String callingCode;
  final String flagEmoji;

  CountryCallingCode get domainCallingCode => CountryCallingCode(callingCode);

  String get semanticsLabel => '$name, $callingCode';
}

const defaultRegistrationCountry = RegistrationCountry(
  code: 'GB',
  name: 'United Kingdom',
  callingCode: '+44',
  flagEmoji: '🇬🇧',
);

const registrationCountries = <RegistrationCountry>[
  defaultRegistrationCountry,
  RegistrationCountry(
    code: 'US',
    name: 'United States',
    callingCode: '+1',
    flagEmoji: '🇺🇸',
  ),
  RegistrationCountry(
    code: 'CA',
    name: 'Canada',
    callingCode: '+1',
    flagEmoji: '🇨🇦',
  ),
  RegistrationCountry(
    code: 'CN',
    name: 'China',
    callingCode: '+86',
    flagEmoji: '🇨🇳',
  ),
  RegistrationCountry(
    code: 'JP',
    name: 'Japan',
    callingCode: '+81',
    flagEmoji: '🇯🇵',
  ),
  RegistrationCountry(
    code: 'KR',
    name: 'South Korea',
    callingCode: '+82',
    flagEmoji: '🇰🇷',
  ),
  RegistrationCountry(
    code: 'IN',
    name: 'India',
    callingCode: '+91',
    flagEmoji: '🇮🇳',
  ),
  RegistrationCountry(
    code: 'AU',
    name: 'Australia',
    callingCode: '+61',
    flagEmoji: '🇦🇺',
  ),
  RegistrationCountry(
    code: 'DE',
    name: 'Germany',
    callingCode: '+49',
    flagEmoji: '🇩🇪',
  ),
  RegistrationCountry(
    code: 'FR',
    name: 'France',
    callingCode: '+33',
    flagEmoji: '🇫🇷',
  ),
];
