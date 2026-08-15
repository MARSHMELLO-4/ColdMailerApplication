class ParsedEmails {
  const ParsedEmails({
    required this.valid,
    required this.invalid,
    required this.duplicates,
    required this.totalTokens,
  });

  final List<String> valid;
  final List<String> invalid;
  final List<String> duplicates;
  final int totalTokens;

  bool get hasInvalidEntries => invalid.isNotEmpty;
  bool get hasValidEntries => valid.isNotEmpty;
}

class EmailParser {
  static final RegExp _emailPattern = RegExp(
    r'^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$',
    caseSensitive: false,
  );

  static ParsedEmails parse(String input) {
    final tokens = input
        .split(RegExp(r'[\s,;]+'))
        .map(_cleanToken)
        .where((token) => token.isNotEmpty)
        .toList();
    final valid = <String>[];
    final invalid = <String>[];
    final duplicates = <String>[];
    final seen = <String>{};

    for (final token in tokens) {
      final normalized = token.toLowerCase();

      if (!_emailPattern.hasMatch(normalized)) {
        invalid.add(token);
        continue;
      }

      if (!seen.add(normalized)) {
        duplicates.add(normalized);
        continue;
      }

      valid.add(normalized);
    }

    return ParsedEmails(
      valid: valid,
      invalid: invalid,
      duplicates: duplicates,
      totalTokens: tokens.length,
    );
  }

  static String _cleanToken(String token) {
    var value = token.trim();

    while (value.startsWith('<') ||
        value.startsWith('"') ||
        value.startsWith("'")) {
      value = value.substring(1).trim();
    }

    while (value.endsWith('>') || value.endsWith('"') || value.endsWith("'")) {
      value = value.substring(0, value.length - 1).trim();
    }

    return value;
  }
}
