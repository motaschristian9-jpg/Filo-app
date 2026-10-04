/// Recognizes individual Drive files without fetching or copying their contents.
class DriveLink {
  const DriveLink(this.original, this.id, this.documentType);
  final Uri original;
  final String id;
  final String? documentType;

  static DriveLink? parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https') return null;
    final parts = uri.pathSegments;
    String? id, type;
    if (uri.host == 'drive.google.com') {
      if (parts.length >= 3 && parts[0] == 'file' && parts[1] == 'd') {
        id = parts[2];
      } else if (uri.path == '/open' || uri.path == '/uc') {
        id = uri.queryParameters['id'];
      }
    } else if (uri.host == 'docs.google.com' && parts.length >= 3 &&
        const ['document', 'spreadsheets', 'presentation'].contains(parts[0]) &&
        parts[1] == 'd') {
      type = parts[0];
      id = parts[2];
    }
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) return null;
    return DriveLink(uri, id, type);
  }

  Map<String, String> get _accessParameters => {
    if (original.queryParameters['resourcekey'] case final String key)
      'resourcekey': key,
  };

  Uri get preview => Uri.https(
    documentType == null ? 'drive.google.com' : 'docs.google.com',
    documentType == null ? '/file/d/$id/preview' : '/$documentType/d/$id/preview',
    _accessParameters,
  );

  // Google-native documents export as PDF; uploaded files retain their format.
  Uri get download => documentType == null
    ? Uri.https('drive.google.com', '/uc', {
        'export': 'download', 'id': id, ..._accessParameters,
      })
    : Uri.https('docs.google.com', '/$documentType/d/$id/export', {
        'format': 'pdf', ..._accessParameters,
      });
}
