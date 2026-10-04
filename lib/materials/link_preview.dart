import 'drive_link.dart';

/// Provider detection is local; ordinary HTTPS links still work normally.
class LinkPreview {
  const LinkPreview(this.uri, this.label, this.action);
  final Uri uri;
  final String label, action;

  static LinkPreview? parse(String value) {
    final drive = DriveLink.parse(value);
    if (drive != null) return LinkPreview(drive.preview, 'Google Drive', 'Tap to preview');
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https') return null;
    String? id;
    final parts = uri.pathSegments;
    if (uri.host == 'youtu.be' && parts.isNotEmpty) {
      id = parts.first;
    } else if (const ['youtube.com', 'www.youtube.com', 'm.youtube.com'].contains(uri.host)) {
      if (uri.path == '/watch') id = uri.queryParameters['v'];
      if (parts.length >= 2 && const ['shorts', 'embed', 'live'].contains(parts.first)) {
        id = parts[1];
      }
    }
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return null;
    return LinkPreview(uri, 'YouTube', 'Tap to watch');
  }
}
