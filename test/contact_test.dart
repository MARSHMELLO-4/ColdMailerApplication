import 'package:cold_mailer/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Contact', () {
    test('parses from valid json map', () {
      final json = {
        'id': 'contact-123',
        'email': 'recruiter@tech.corp',
        'total_sent': 3,
        'last_status': 'sent',
        'first_contacted_at': '2026-08-01T10:00:00Z',
        'last_contacted_at': '2026-08-15T12:00:00Z',
        'last_attempted_at': '2026-08-15T12:00:00Z',
        'last_subject': 'Software Engineer Opportunity',
      };

      final contact = Contact.fromJson(json);

      expect(contact.id, 'contact-123');
      expect(contact.email, 'recruiter@tech.corp');
      expect(contact.totalSent, 3);
      expect(contact.lastStatus, 'sent');
      expect(contact.lastSubject, 'Software Engineer Opportunity');
      expect(contact.firstContactedAt, isNotNull);
      expect(contact.lastContactedAt, isNotNull);
      expect(contact.lastAttemptedAt, isNotNull);
    });

    test('handles missing or nullable fields gracefully', () {
      final json = {
        'id': null,
        'email': null,
        'total_sent': '5',
        'last_status': null,
      };

      final contact = Contact.fromJson(json);

      expect(contact.id, '');
      expect(contact.email, '');
      expect(contact.totalSent, 5);
      expect(contact.lastStatus, 'sent');
      expect(contact.firstContactedAt, isNull);
      expect(contact.lastSubject, isNull);
    });
  });
}
