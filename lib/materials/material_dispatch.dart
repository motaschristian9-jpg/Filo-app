import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'supabase_file_storage.dart';

// Reserve a durable notification job before publishing. If the app closes just
// after Firestore commits, the server still delivers the published material.
class MaterialDispatch {
  Future<void> prepare(String classId, String materialId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const MaterialStorageException('Sign in to post.');
    final token = await user.getIdToken();
    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('$supabaseUrl/functions/v1/material-dispatch'),
        headers: {'apikey': supabasePublishableKey,
          'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'classId': classId, 'materialId': materialId}),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw MaterialStorageException(switch (response.statusCode) {
          401 => 'Your session expired. Sign in again.',
          403 => 'You cannot post to this class.',
          404 || 503 => 'Material delivery is not set up yet.',
          _ => 'Could not prepare delivery. Please retry.',
        });
      }
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw const MaterialStorageException('Your account changed. Reopen this class.');
      }
    } finally { client.close(); }
  }

  // Best-effort immediate wake-up. The durable scheduled worker is the fallback.
  Future<void> wake(String classId, String materialId) => prepare(classId, materialId);
}
