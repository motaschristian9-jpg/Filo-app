import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../materials/supabase_file_storage.dart';

class QuizRepository {
  QuizRepository(this.classId);
  final String classId;
  Future<List<Map<String, dynamic>>> generate(String source, int count, List<String> materialIds,
      Map<String, int> counts) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Sign in again.');
    final token = await user.getIdToken();
    final client = http.Client();
    try {
      final response = await client.post(Uri.parse('$supabaseUrl/functions/v1/quiz-generate'),
        headers: {'apikey': supabasePublishableKey, 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'},
        body: jsonEncode({'classId': classId, 'source': source, 'count': count, 'materialIds': materialIds, 'counts': counts}),
      ).timeout(const Duration(seconds: 120));
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) throw Exception('Account changed.');
      if (response.statusCode != 200) {
        String? reason;
        try { reason = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String?; }
        catch (_) {}
        final specific = switch (reason) {
          'ai_key_rejected' => 'Gemini rejected the API key. Check its validity and API restrictions.',
          'ai_model_unavailable' => 'The configured Gemini model is unavailable. Check GEMINI_QUIZ_MODEL.',
          'ai_request_rejected' => 'Gemini rejected the file or request format. Try a smaller PDF or text file.',
          'ai_output_incomplete' => 'AI output was too long. Try fewer questions.',
          'ai_output_blocked' => 'Gemini could not produce questions from this lesson. Try another file.',
          'ai_provider_limit' => 'Gemini quota reached. Check the provider quota or try later.',
          'ai_not_configured' => 'Add GEMINI_API_KEY in the private Supabase secrets.',
          _ => null,
        };
        throw QuizGenerationException(specific ?? switch (response.statusCode) {
        400 => 'Select supported lesson files and try again.',
        413 => 'Selected files exceed the 8 MB limit.',
        404 => 'A selected material is no longer available.',
        503 => 'AI is unavailable. Check the private AI setup or try again later.',
        429 => 'AI limit reached. Try again later or add questions manually.',
        422 => 'Could not create enough questions. Add more lesson content.',
          401 => 'Your session expired. Sign in again.',
          403 => 'You no longer have access to this class.',
          409 => 'This class is archived.',
          502 => 'Gemini is unavailable. Please try again later.',
          504 => 'AI generation timed out on the server. Try fewer questions or a smaller file.',
          _ => 'AI request failed (HTTP ${response.statusCode}). Please report this code.',
      });
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['questions'] as List).map((q) => Map<String, dynamic>.from(q as Map)).toList();
    } finally { client.close(); }
  }
  CollectionReference<Map<String, dynamic>> get collection => FirebaseFirestore.instance
    .collection('classes').doc(classId).collection('assessmentDrafts');
  Stream<QuerySnapshot<Map<String, dynamic>>> watch() => collection
    .orderBy('createdAt', descending: true).snapshots();
  Future<void> publish(String id) async {
    final db = FirebaseFirestore.instance;
    final course = db.collection('classes').doc(classId);
    final published = course.collection('assessments').doc(id);
    await db.runTransaction((tx) async {
      final courseData = await tx.get(course);
      final draft = await tx.get(collection.doc(id));
      final existing = await tx.get(published);
      if (existing.exists) return;
      if (!draft.exists || courseData.data()?['archived'] == true) throw StateError('Unavailable');
      final data = draft.data()!;
      final questions = (data['questions'] as List).map((raw) {
        final q = Map<String, dynamic>.from(raw as Map);
        final type = q['type'] ?? 'multiple_choice';
        return {'type': type, 'prompt': q['prompt'], 'points': q['points'] ?? 1,
          if (q['options'] != null) 'options': q['options'],
          if (type == 'enumeration') 'entryCount': (q['expectedAnswers'] as List).length,
          if (type == 'essay') 'rubric': q['rubric'],
        };
      }).toList();
      tx.set(published, {'title': data['title'], 'kind': data['kind'],
        'minutes': data['minutes'], 'questions': questions,
        'publishedAt': FieldValue.serverTimestamp()});
      tx.update(collection.doc(id), {'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp()});
    }).timeout(const Duration(seconds: 20));
  }
  Future<void> save(String id, Map<String, dynamic> data) async {
    final course = FirebaseFirestore.instance.collection('classes').doc(classId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snapshot = await tx.get(course);
      if (!snapshot.exists || snapshot.data()?['archived'] == true) {
        throw StateError('Class unavailable');
      }
      final previous = await tx.get(collection.doc(id));
      if (previous.data()?['publishedAt'] != null) return;
      tx.set(collection.doc(id), {...data,
        'createdAt': previous.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp()});
    }).timeout(const Duration(seconds: 20));
  }
}

class QuizGenerationException implements Exception {
  const QuizGenerationException(this.message);
  final String message;
}
