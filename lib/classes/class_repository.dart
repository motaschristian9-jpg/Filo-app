import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class FiloClass {
  const FiloClass({required this.id, required this.instructorId, required this.name,
    this.subject = '', this.section = '', this.description = '', this.color = 0,
    this.archived = false, this.createdAt});
  final String id, instructorId, name, subject, section, description;
  final int color;
  final bool archived;
  final DateTime? createdAt;
  // Use the document ID as the unique, case-sensitive code. No collisions or
  // public class-code lookup collection is introduced by the instructor UI.
  String get code => id;
  factory FiloClass.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FiloClass(
      id: doc.id, instructorId: data['instructorId'] as String? ?? '',
      name: data['name'] as String? ?? data['title'] as String? ?? 'Untitled class',
      subject: data['subject'] as String? ?? '', section: data['section'] as String? ?? '',
      description: data['description'] as String? ?? '',
      color: data['color'] is num ? (data['color'] as num).toInt() : 0,
      archived: data['archived'] == true,
      createdAt: data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate() : null,
    );
  }
}

class ClassDraft {
  const ClassDraft({required this.name, required this.subject, required this.section,
    required this.description, required this.color});
  final String name, subject, section, description;
  final int color;
  Map<String, dynamic> toMap() => {
    'name': name.trim(), 'subject': subject.trim(), 'section': section.trim(),
    'description': description.trim(), 'color': color,
  };
}

class ClassMember {
  const ClassMember(this.id, this.name);
  final String id, name;
}

class ClassRepository {
  ClassRepository({required this.instructorId, FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;
  final String instructorId;
  final FirebaseFirestore _firestore;
  CollectionReference<Map<String, dynamic>> get _classes => _firestore.collection('classes');

  Stream<List<FiloClass>> watchClasses() => _classes
      .where('instructorId', isEqualTo: instructorId).snapshots()
      .map((snapshot) {
        final classes = snapshot.docs.map(FiloClass.fromDocument).toList();
        classes.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
        return classes;
      });
  Stream<FiloClass?> watchClass(String id) => _classes.doc(id).snapshots()
      .map((doc) => doc.exists ? FiloClass.fromDocument(doc) : null);
  String newClassId() => _classes.doc().id;

  Future<void> create(String id, ClassDraft draft) async {
    // An ID is reserved by the form so retrying never creates a second class.
    await _classes.doc(id).set({
      ...draft.toMap(), 'instructorId': instructorId, 'archived': false,
      'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
  }
  Future<void> update(String id, ClassDraft draft) => _classes.doc(id).update({
    ...draft.toMap(), 'updatedAt': FieldValue.serverTimestamp(),
  }).timeout(const Duration(seconds: 20));
  Future<void> setArchived(String id, bool archived) => _classes.doc(id).update({
    'archived': archived, 'updatedAt': FieldValue.serverTimestamp(),
  }).timeout(const Duration(seconds: 20));
  Stream<List<ClassMember>> watchMembers(String id) => _classes.doc(id)
      .collection('enrollments').snapshots().asyncMap((snapshot) async {
        final members = await Future.wait(snapshot.docs.map((enrollment) async {
          final profile = await _firestore.collection('users').doc(enrollment.id).get();
          final data = profile.data();
          return ClassMember(enrollment.id, data?['name'] as String?
              ?? data?['displayName'] as String? ?? 'Student');
        }));
        members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return members;
      });
}

String classError(Object error) {
  if (error is TimeoutException) return 'Save is taking longer than expected. It may finish when you reconnect.';
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => 'You do not have access to this class.',
      'unavailable' => 'No connection. Please try again.',
      'not-found' => 'This class is no longer available.',
      _ => 'Could not save that change. Please try again.',
    };
  }
  return 'Something went wrong. Please try again.';
}
