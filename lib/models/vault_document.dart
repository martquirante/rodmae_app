import '../core/utils.dart';

final class VaultDocument {
  final String name;
  final String sizeLabel;
  final DateTime uploadedAt;
  final String status;
  final String? signedUrl;

  const VaultDocument({
    required this.name,
    required this.sizeLabel,
    required this.uploadedAt,
    required this.status,
    this.signedUrl,
  });

  factory VaultDocument.fromMap(Map<String, dynamic> row) {
    return VaultDocument(
      name: '${row['file_name'] ?? row['name'] ?? 'Secure document'}',
      sizeLabel: '${row['file_size'] ?? row['size_label'] ?? 'Protected'}',
      uploadedAt: Formatters.asDate(row['uploaded_at'] ?? row['created_at']),
      status: '${row['status'] ?? 'verified'}',
      signedUrl: row['file_url']?.toString(),
    );
  }
}
