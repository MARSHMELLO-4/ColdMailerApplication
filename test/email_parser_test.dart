import 'package:cold_mailer/services/app_config.dart';
import 'package:cold_mailer/services/email_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmailParser', () {
    test('splits, normalizes, and de-duplicates email input', () {
      final parsed = EmailParser.parse(
        'A@Example.com, b@example.com\n<a@example.com>; bad-email',
      );

      expect(parsed.valid, ['a@example.com', 'b@example.com']);
      expect(parsed.duplicates, ['a@example.com']);
      expect(parsed.invalid, ['bad-email']);
      expect(parsed.totalTokens, 4);
    });

    test('handles empty input', () {
      final parsed = EmailParser.parse('');

      expect(parsed.valid, isEmpty);
      expect(parsed.invalid, isEmpty);
      expect(parsed.duplicates, isEmpty);
    });
  });

  group('AppConfig', () {
    test('loads escaped newlines from env values', () {
      final config = AppConfig.fromEnv({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'anon',
        'DEFAULT_EMAIL_BODY': r'Hi {{first_name}},\n\nBody',
      });

      expect(config.defaultBody, 'Hi {{first_name}},\n\nBody');
      expect(config.hasSupabaseClientConfig, isTrue);
    });

    test('reports missing client keys', () {
      final config = AppConfig.fromEnv({});

      expect(config.hasSupabaseClientConfig, isFalse);
      expect(
        config.missingClientKeys,
        containsAll(['SUPABASE_URL', 'SUPABASE_ANON_KEY']),
      );
    });
  });
}
