import 'package:flutter/material.dart';

import '../services/app_config.dart';

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key, required this.config, this.error});

  final AppConfig config;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final missingKeys = config.missingClientKeys;

    return Scaffold(
      appBar: AppBar(title: const Text('Cold Mailer Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.settings_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Add your Supabase client values',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Paste the missing values into the root .env file, then restart the app.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (missingKeys.isNotEmpty)
              _SetupPanel(
                title: 'Missing client keys',
                children: missingKeys
                    .map(
                      (key) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.key_outlined),
                        title: Text(key),
                      ),
                    )
                    .toList(),
              ),
            if (error != null) ...[
              const SizedBox(height: 16),
              _SetupPanel(
                title: 'Startup error',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(error!),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  const _SetupPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
        ],
      ),
    );
  }
}
