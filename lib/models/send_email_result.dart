class SendEmailResult {
  const SendEmailResult({
    required this.sent,
    required this.failed,
    required this.failedRecipients,
  });

  final int sent;
  final int failed;
  final List<String> failedRecipients;

  bool get hasFailures => failed > 0;

  String get summary {
    if (failed == 0) {
      return 'Sent $sent email${sent == 1 ? '' : 's'} successfully.';
    }

    return 'Sent $sent and failed $failed: ${failedRecipients.join(', ')}';
  }

  factory SendEmailResult.fromFunctionData(Object? data) {
    if (data is! Map) {
      return const SendEmailResult(sent: 0, failed: 0, failedRecipients: []);
    }

    final results = data['results'];
    final failedRecipients = <String>[];

    if (results is List) {
      for (final item in results) {
        if (item is Map && item['status'] == 'failed') {
          failedRecipients.add(item['recipient']?.toString() ?? 'unknown');
        }
      }
    }

    return SendEmailResult(
      sent: _toInt(data['sent']),
      failed: _toInt(data['failed']),
      failedRecipients: failedRecipients,
    );
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
