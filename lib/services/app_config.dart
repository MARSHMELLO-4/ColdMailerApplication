import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.resumeBucket,
    required this.sendEmailFunction,
    required this.defaultSubject,
    required this.defaultBody,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String resumeBucket;
  final String sendEmailFunction;
  final String defaultSubject;
  final String defaultBody;

  static Future<AppConfig> load() async {
    Map<String, String> env = {};

    try {
      await dotenv.load(fileName: '.env');
      env = dotenv.env;
    } catch (_) {
      // .env could not be loaded; use empty environment.
    }

    return AppConfig.fromEnv(env);
  }

  factory AppConfig.fromEnv(Map<String, String> env) {
    String read(String key, [String fallback = '']) {
      return (env[key] ?? fallback).trim().replaceAll(r'\n', '\n');
    }

    return AppConfig(
      supabaseUrl: read('SUPABASE_URL'),
      supabaseAnonKey: read('SUPABASE_ANON_KEY'),
      resumeBucket: read('SUPABASE_RESUME_BUCKET', 'resume_uploads'),
      sendEmailFunction: read(
        'SUPABASE_SEND_EMAIL_FUNCTION',
        'send-cold-email',
      ),
      defaultSubject: read(
        'DEFAULT_EMAIL_SUBJECT',
        'Application for Software Engineer Role',
      ),
      defaultBody: read(
        'DEFAULT_EMAIL_BODY',
        'Hi {{first_name}},\n\nI hope you are doing well. I am reaching out to share my resume and explore any relevant opportunities.\n\nThank you for your time.',
      ),
    );
  }

  bool get hasSupabaseClientConfig {
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        supabaseAnonKey.isNotEmpty;
  }

  List<String> get missingClientKeys {
    final missing = <String>[];
    final uri = Uri.tryParse(supabaseUrl);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      missing.add('SUPABASE_URL');
    }

    if (supabaseAnonKey.isEmpty) {
      missing.add('SUPABASE_ANON_KEY');
    }

    return missing;
  }
}
