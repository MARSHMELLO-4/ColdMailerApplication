import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/configuration_screen.dart';
import 'screens/home_screen.dart';
import 'services/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await AppConfig.load();

  if (!config.hasSupabaseClientConfig) {
    runApp(ColdMailerApp(config: config));
    return;
  }

  try {
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
    runApp(ColdMailerApp(config: config));
  } catch (error) {
    runApp(ColdMailerApp(config: config, startupError: error.toString()));
  }
}

class ColdMailerApp extends StatelessWidget {
  const ColdMailerApp({super.key, required this.config, this.startupError});

  final AppConfig config;
  final String? startupError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cold Mailer',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.only(bottom: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
        ),
      ),
      home: config.hasSupabaseClientConfig && startupError == null
          ? HomeScreen(config: config)
          : ConfigurationScreen(config: config, error: startupError),
    );
  }
}
