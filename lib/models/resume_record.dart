class ResumeRecord {
  const ResumeRecord({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required this.uploadedAt,
    required this.isActive,
  });

  final String id;
  final String fileName;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final DateTime uploadedAt;
  final bool isActive;

  factory ResumeRecord.fromJson(Map<String, dynamic> json) {
    return ResumeRecord(
      id: json['id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? 'resume',
      storagePath: json['storage_path']?.toString() ?? '',
      contentType:
          json['content_type']?.toString() ?? 'application/octet-stream',
      sizeBytes: _toInt(json['size_bytes']),
      uploadedAt:
          DateTime.tryParse(json['uploaded_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      isActive: json['is_active'] == true,
    );
  }

  String get displaySize {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    if (sizeBytes >= 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }

    return '$sizeBytes B';
  }
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
