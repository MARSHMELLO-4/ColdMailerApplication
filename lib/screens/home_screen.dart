import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contact.dart';
import '../models/resume_record.dart';
import '../services/app_config.dart';
import '../services/email_parser.dart';
import '../services/supabase_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.config});

  final AppConfig config;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy h:mm a');

  late final SupabaseRepository _repository;
  late final TextEditingController _recipientsController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;

  List<Contact> _contacts = [];
  List<ResumeRecord> _resumes = [];
  ResumeRecord? _selectedResume;
  bool _loading = true;
  bool _sending = false;
  bool _uploading = false;
  int _selectedIndex = 0;

  ParsedEmails get _parsedEmails =>
      EmailParser.parse(_recipientsController.text);

  bool get _canSend {
    final parsed = _parsedEmails;
    return parsed.hasValidEntries &&
        !parsed.hasInvalidEntries &&
        _subjectController.text.trim().isNotEmpty &&
        _bodyController.text.trim().isNotEmpty &&
        !_sending;
  }

  @override
  void initState() {
    super.initState();
    _repository = SupabaseRepository(
      client: Supabase.instance.client,
      config: widget.config,
    );
    _recipientsController = TextEditingController()..addListener(_refresh);
    _subjectController = TextEditingController(
      text: widget.config.defaultSubject,
    )..addListener(_refresh);
    _bodyController = TextEditingController(text: widget.config.defaultBody)
      ..addListener(_refresh);
    _loadData();
  }

  @override
  void dispose() {
    _recipientsController
      ..removeListener(_refresh)
      ..dispose();
    _subjectController
      ..removeListener(_refresh)
      ..dispose();
    _bodyController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final contacts = await _repository.fetchContacts();
      final resumes = await _repository.fetchResumes();

      if (!mounted) {
        return;
      }

      setState(() {
        _contacts = contacts;
        _resumes = resumes;
        _selectedResume = _resolveSelectedResume(resumes);
      });
    } catch (error) {
      if (mounted) {
        _showSnack('Unable to load Supabase data: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  ResumeRecord? _resolveSelectedResume(List<ResumeRecord> resumes) {
    if (resumes.isEmpty) {
      return null;
    }

    final selectedId = _selectedResume?.id;
    for (final resume in resumes) {
      if (resume.id == selectedId) {
        return resume;
      }
    }

    return resumes.first;
  }

  Future<void> _pickAndUploadResume() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() => _uploading = true);
    }

    try {
      final resume = await _repository.uploadResume(result.files.single);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedResume = resume;
        _resumes = [resume, ..._resumes];
      });
      _showSnack('Resume uploaded: ${resume.fileName}');
    } catch (error) {
      if (mounted) {
        _showSnack('Resume upload failed: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _sendEmails() async {
    final parsed = _parsedEmails;

    if (!_canSend) {
      _showSnack('Add valid recipients, subject, and body.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _sending = true);

    try {
      final result = await _repository.sendColdEmails(
        recipients: parsed.valid,
        subject: _subjectController.text.trim(),
        body: _bodyController.text.trim(),
        resume: _selectedResume,
      );

      if (!mounted) {
        return;
      }

      _recipientsController.clear();
      _showSnack(result.summary, isError: result.hasFailures);
      await _loadData();

      if (mounted && result.sent > 0) {
        setState(() => _selectedIndex = 2);
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Email send failed: $error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildComposePage(context),
      _buildResumePage(context),
      _buildContactsPage(context),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cold Mailer'),
        actions: [
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              onPressed: _loading ? null : _loadData,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: const Icon(Icons.mail_outline),
            selectedIcon: const Icon(Icons.mail),
            label: 'Compose',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: 'Resume',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
        ],
      ),
    );
  }

  Widget _buildComposePage(BuildContext context) {
    final parsed = _parsedEmails;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _MetricStrip(
            metrics: [
              _Metric('Recipients', parsed.valid.length.toString()),
              _Metric('Contacts', _contacts.length.toString()),
              _Metric('Resumes', _resumes.length.toString()),
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedResume?.fileName ?? 'No resume selected',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Tooltip(
                      message: 'Upload resume',
                      child: IconButton.filledTonal(
                        onPressed: _uploading ? null : _pickAndUploadResume,
                        icon: _uploading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.upload_file),
                      ),
                    ),
                  ],
                ),
                if (_resumes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedResume?.id,
                    decoration: const InputDecoration(
                      labelText: 'Attached resume',
                      prefixIcon: Icon(Icons.attach_file),
                    ),
                    items: _resumes
                        .map(
                          (resume) => DropdownMenuItem(
                            value: resume.id,
                            child: Text(
                              resume.fileName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      setState(() {
                        _selectedResume = _resumeById(id);
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _recipientsController,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: 'Recipient emails',
              hintText: 'person@company.com, recruiter@example.com',
              prefixIcon: const Icon(Icons.alternate_email),
              errorText: parsed.hasInvalidEntries
                  ? 'Remove invalid emails.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          _RecipientSummary(parsed: parsed),
          const SizedBox(height: 16),
          TextField(
            controller: _subjectController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email subject',
              prefixIcon: Icon(Icons.subject),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bodyController,
            minLines: 8,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Email body',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _canSend ? _sendEmails : null,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(
              _sending
                  ? 'Sending'
                  : 'Send to ${parsed.valid.length} recipient${parsed.valid.length == 1 ? '' : 's'}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumePage(BuildContext context) {
    if (_loading && _resumes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          FilledButton.icon(
            onPressed: _uploading ? null : _pickAndUploadResume,
            icon: _uploading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_uploading ? 'Uploading' : 'Upload resume'),
          ),
          const SizedBox(height: 16),
          if (_resumes.isEmpty)
            const _EmptyState(
              icon: Icons.description_outlined,
              title: 'No resumes uploaded',
              message: 'Upload a PDF, DOC, or DOCX resume.',
            )
          else
            ..._resumes.map(
              (resume) => Card(
                child: RadioListTile<String>(
                  value: resume.id,
                  groupValue: _selectedResume?.id,
                  onChanged: (_) => setState(() => _selectedResume = resume),
                  title: Text(resume.fileName),
                  subtitle: Text(
                    '${resume.displaySize} - ${_dateFormat.format(resume.uploadedAt)}',
                  ),
                  secondary: const Icon(Icons.description_outlined),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContactsPage(BuildContext context) {
    if (_loading && _contacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_contacts.isEmpty)
            const _EmptyState(
              icon: Icons.people_outline,
              title: 'No contacts yet',
              message: 'Sent emails will appear here.',
            )
          else
            ..._contacts.map(
              (contact) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      contact.lastStatus == 'sent'
                          ? Icons.check
                          : Icons.error_outline,
                    ),
                  ),
                  title: Text(contact.email),
                  subtitle: Text(_contactSubtitle(contact)),
                  trailing: Chip(
                    avatar: const Icon(Icons.mail_outline, size: 16),
                    label: Text(contact.totalSent.toString()),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _contactSubtitle(Contact contact) {
    final date = contact.lastContactedAt ?? contact.lastAttemptedAt;
    final dateText = date == null ? 'No send date' : _dateFormat.format(date);
    final subject = contact.lastSubject;

    if (subject == null || subject.isEmpty) {
      return '${contact.lastStatus} - $dateText';
    }

    return '${contact.lastStatus} - $dateText - $subject';
  }

  ResumeRecord? _resumeById(String? id) {
    for (final resume in _resumes) {
      if (resume.id == id) {
        return resume;
      }
    }

    return null;
  }
}

class _RecipientSummary extends StatelessWidget {
  const _RecipientSummary({required this.parsed});

  final ParsedEmails parsed;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _StatusChip(
        icon: Icons.check_circle_outline,
        label: '${parsed.valid.length} valid',
      ),
      if (parsed.duplicates.isNotEmpty)
        _StatusChip(
          icon: Icons.copy_all_outlined,
          label: '${parsed.duplicates.length} duplicate',
        ),
      if (parsed.invalid.isNotEmpty)
        _StatusChip(
          icon: Icons.error_outline,
          label: '${parsed.invalid.length} invalid',
          isError: true,
        ),
    ];

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    this.isError = false,
  });

  final IconData icon;
  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: isError ? colorScheme.error : colorScheme.primary,
      ),
      label: Text(label),
      side: BorderSide(
        color: isError ? colorScheme.error : colorScheme.outlineVariant,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: metrics
          .map(
            (metric) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: metric == metrics.last ? 0 : 8),
                child: _MetricTile(metric: metric),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(metric.value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(icon, size: 48, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
