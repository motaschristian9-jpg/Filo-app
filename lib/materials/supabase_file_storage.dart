import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

// Client configuration only. Server credentials belong in Edge Function secrets.
const supabaseUrl = 'https://pvcereixbqctjrxsalhd.supabase.co';
const supabasePublishableKey = 'sb_publishable_4DE8_HbaN6HmKXrkQKPTPg_DXyIRLQ4';
const _maxFileBytes = 25 * 1024 * 1024;

class MaterialStorageException implements Exception {
  const MaterialStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseFileStorage {
  Future<Map<String, dynamic>> _authorize(String action, String classId,
      String materialId, {String? studentId, int? attachmentIndex}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const MaterialStorageException('Sign in to access materials.');
    final token = await user.getIdToken();
    final client = http.Client();
    try {
      final response = await client.post(Uri.parse('$supabaseUrl/functions/v1/material-files'),
        headers: {'apikey': supabasePublishableKey,
          'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, 'classId': classId, 'materialId': materialId,
          if (studentId != null) 'studentId': studentId,
          if (attachmentIndex != null) 'attachmentIndex': attachmentIndex}),
      ).timeout(const Duration(seconds: 30));
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw const MaterialStorageException('Your account changed. Reopen this class.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MaterialStorageException(switch (response.statusCode) {
          401 => 'Your session expired. Sign in again.',
          403 => 'You do not have access to this class or upload.',
          404 => 'File storage setup or this material is not available yet.',
          409 => 'This material has already been posted. Reopen the class.',
          429 => 'Storage is busy. Please retry later.',
          503 => 'File storage is not ready. Complete the Supabase setup.',
          _ => 'File service unavailable (${response.statusCode}). Please retry.',
        });
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on TimeoutException {
      throw const MaterialStorageException('File access timed out. Check your connection and retry.');
    } on http.ClientException {
      throw const MaterialStorageException('Could not reach file storage. Check your connection.');
    } finally { client.close(); }
  }

  Uri _signedUri(dynamic value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null || uri.scheme != 'https' || uri.host != Uri.parse(supabaseUrl).host ||
        uri.userInfo.isNotEmpty || uri.port != 443 || !uri.path.startsWith('/storage/v1/')) {
      throw const MaterialStorageException('Invalid file service response.');
    }
    return uri;
  }

  Future<String> upload(String classId, String materialId, Uint8List bytes, {bool submission = false}) async {
    if (bytes.isEmpty || bytes.length > _maxFileBytes) {
      throw const MaterialStorageException('Choose a file up to 25 MB.');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final grant = await _authorize(submission ? 'submission-upload' : 'upload', classId, materialId);
    final path = grant['path'];
    if (path is! String || !path.startsWith(submission
        ? 'class-submissions/$classId/$materialId/$uid/' : 'class-materials/$classId/$materialId/')) {
      throw const MaterialStorageException('Invalid upload destination.');
    }
    final client = http.Client();
    try {
      final response = await client.put(_signedUri(grant['signedUrl']),
        headers: {'apikey': supabasePublishableKey,
          'Content-Type': 'application/octet-stream', 'x-upsert': 'false'}, body: bytes,
      ).timeout(const Duration(minutes: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MaterialStorageException(response.statusCode == 413
          ? 'Choose a file up to 25 MB.'
          : 'Upload failed (${response.statusCode}). Please retry.');
      }
      return path;
    } on TimeoutException {
      throw const MaterialStorageException('Upload timed out. Check your connection and retry.');
    } on http.ClientException {
      throw const MaterialStorageException('Upload interrupted. Check your connection and retry.');
    } finally { client.close(); }
  }

  Future<Uri> downloadUrl(String classId, String materialId) async =>
      _signedUri((await _authorize('download', classId, materialId))['signedUrl']);
  Future<Uri> submissionUrl(String classId, String materialId, String studentId, {int attachmentIndex = 0}) async =>
    _signedUri((await _authorize('submission-download', classId, materialId,
      studentId: studentId, attachmentIndex: attachmentIndex))['signedUrl']);

  Future<Uint8List> download(String classId, String materialId) async {
    final uri = await downloadUrl(classId, materialId);
    final client = http.Client();
    try {
      return await (() async {
        final response = await client.send(http.Request('GET', uri));
        if (response.statusCode != 200) {
          throw const MaterialStorageException('Could not download this file. Retry to renew access.');
        }
        if ((response.contentLength ?? 0) > _maxFileBytes) {
          throw const MaterialStorageException('File exceeds the download limit.');
        }
        final buffer = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (buffer.length + chunk.length > _maxFileBytes) {
            throw const MaterialStorageException('File exceeds the download limit.');
          }
          buffer.add(chunk);
        }
        return buffer.takeBytes();
      })().timeout(const Duration(minutes: 2));
    } finally { client.close(); }
  }
}
