class Contact {
  const Contact({
    required this.id,
    required this.email,
    required this.totalSent,
    required this.lastStatus,
    this.firstContactedAt,
    this.lastContactedAt,
    this.lastAttemptedAt,
    this.lastSubject,
  });

  final String id;
  final String email;
  final int totalSent;
  final String lastStatus;
  final DateTime? firstContactedAt;
  final DateTime? lastContactedAt;
  final DateTime? lastAttemptedAt;
  final String? lastSubject;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      totalSent: _toInt(json['total_sent']),
      lastStatus: json['last_status']?.toString() ?? 'sent',
      firstContactedAt: _date(json['first_contacted_at']),
      lastContactedAt: _date(json['last_contacted_at']),
      lastAttemptedAt: _date(json['last_attempted_at']),
      lastSubject: json['last_subject']?.toString(),
    );
  }
}

DateTime? _date(Object? value) {
  if (value == null) {
    return null;
  }

  return DateTime.tryParse(value.toString())?.toLocal();
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
