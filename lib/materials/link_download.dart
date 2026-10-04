import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'drive_link.dart';
import 'material_cache.dart';
import 'material_repository.dart';

/// Downloads a public, downloadable Drive resource into Filo's managed folder.
/// Does not upload bytes to Filo or attach Firebase credentials to Drive requests.
Future<bool> downloadDriveToDevice(DriveLink drive, ClassMaterial material, MaterialCache cache,
    bool Function() active) async {
  final client = http.Client();
  const maxBytes = 25 * 1024 * 1024;
  try {
    final response = await client.send(http.Request('GET', drive.download))
      .timeout(const Duration(seconds: 30));
    final mime = (response.headers['content-type'] ?? 'application/octet-stream')
      .split(';').first.trim().toLowerCase();
    if (response.statusCode != 200 || mime == 'text/html' ||
        mime == 'application/xhtml+xml') {
      throw StateError('This file needs Drive access or download permission.');
    }
    if ((response.contentLength ?? 0) > maxBytes) {
      throw StateError('Choose a file up to 25 MB.');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
      if (!active()) return false;
      if (buffer.length + chunk.length > maxBytes) {
        throw StateError('Choose a file up to 25 MB.');
      }
      buffer.add(chunk);
    }
    if (buffer.isEmpty || !active()) return false;
    final disposition = response.headers['content-disposition'] ?? '';
    var name = RegExp(r'''filename="([^"]+)"''').firstMatch(disposition)?.group(1)
      ?? RegExp(r'filename=([^;]+)').firstMatch(disposition)?.group(1)
      ?? material.title;
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    if (name.isEmpty) name = 'material';
    if (!name.contains('.')) {
      name += switch (mime) {
        'application/pdf' => '.pdf',
        'image/jpeg' => '.jpg',
        'image/png' => '.png',
        'image/webp' => '.webp',
        'text/plain' => '.txt',
        _ => '',
      };
    }
    await cache.saveLink(material, name, buffer.takeBytes(), active);
    return active() && await cache.containsLink(material);
  } finally { client.close(); }
}
