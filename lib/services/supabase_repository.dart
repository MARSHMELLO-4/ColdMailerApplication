import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contact.dart';
import '../models/resume_record.dart';
import '../models/send_email_result.dart';
import 'app_config.dart';

class SupabaseRepository {
  const SupabaseRepository({
    required SupabaseClient client,
    required AppConfig config,
  }) : _client = client,
       _config = config;

  final SupabaseClient _client;
  final AppConfig _config;

  Future<int> fetchContactCount({String? searchQuery}) async {
    try {
      var query = _client.from('contacts').count(CountOption.exact);

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final sanitized = searchQuery.trim();
        query = query.ilike('email', '%$sanitized%');
      }

      return await query;
    } catch (_) {
      final response = await _client.from('contacts').select('id');
      return (response as List).length;
    }
  }

  Future<List<Contact>> fetchContacts({
    int? limit,
    int? offset,
    String? searchQuery,
  }) async {
    var query = _client.from('contacts').select();

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final sanitized = searchQuery.trim();
      query = query.ilike('email', '%$sanitized%');
    }

    final orderedQuery = query.order('last_attempted_at', ascending: false);

    dynamic response;
    if (offset != null && limit != null) {
      response = await orderedQuery.range(offset, offset + limit - 1);
    } else if (limit != null) {
      response = await orderedQuery.limit(limit);
    } else {
      response = await orderedQuery;
    }

    final list = response as List;
    return list
        .map<Contact>(
          (row) => Contact.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  Future<List<ResumeRecord>> fetchResumes() async {
    final response = await _client
        .from('resumes')
        .select()
        .order('uploaded_at', ascending: false);

    return response
        .map<ResumeRecord>(
          (row) => ResumeRecord.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<ResumeRecord> uploadResume(PlatformFile file) async {
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read the selected file.');
    }

    final safeName = _safeFileName(file.name);
    final storagePath = 'resumes/${_timestamp()}_$safeName';
    final contentType = _contentTypeFor(safeName);

    await _client.storage
        .from(_config.resumeBucket)
        .uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(contentType: contentType),
    );

    final row = await _client
        .from('resumes')
        .insert({
      'file_name': safeName,
      'storage_path': storagePath,
      'content_type': contentType,
      'size_bytes': bytes.length,
    })
        .select()
        .single();

    return ResumeRecord.fromJson(Map<String, dynamic>.from(row));
  }

  Future<SendEmailResult> sendColdEmails({
    required List<String> recipients,
    required String subject,
    required String body,
    ResumeRecord? resume,
  }) async {
    final response = await _client.functions.invoke(
      _config.sendEmailFunction,
      body: {
        'recipients': recipients,
        'subject': subject,
        'body': body,
        'resumePath': resume?.storagePath,
        'resumeFileName': resume?.fileName,
        'resumeContentType': resume?.contentType,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw Exception(_functionErrorMessage(response.data));
    }

    return SendEmailResult.fromFunctionData(response.data);
  }

  String _functionErrorMessage(Object? data) {
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }

    return 'Email function failed.';
  }

  String _safeFileName(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    final baseName = path.basenameWithoutExtension(fileName);
    final safeBase = baseName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return '${safeBase.isEmpty ? 'resume' : safeBase}$extension';
  }

  String _timestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
  }

  String _contentTypeFor(String fileName) {
    switch (path.extension(fileName).toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }
}
