import 'package:app_core/app_core.dart';
import 'package:test/test.dart';

void main() {
  group('MediaResourceId', () {
    const value = 'mr_0123456789abcdef0123456789abcdef';

    test('accepts only the closed lowercase representation', () {
      final id = MediaResourceId(value);

      expect(id.value, value);
      expect(MediaResourceId.tryParse(value), id);
      expect(id.toString(), 'MediaResourceId(<redacted>)');
      expect(id.toString(), isNot(contains(value)));
    });

    test('rejects malformed, uppercase, oversized, and handle-like values', () {
      for (final invalid in <String>[
        '',
        'mr_0123',
        'mr_0123456789ABCDEF0123456789ABCDEF',
        'mr_0123456789abcdef0123456789abcdef0',
        'media_handle_0123456789abcdef01234567',
        '/private/cache/mr_0123456789abcdef0123456789abcdef',
      ]) {
        expect(MediaResourceId.tryParse(invalid), isNull);
        expect(() => MediaResourceId(invalid), throwsFormatException);
      }
    });
  });
}
