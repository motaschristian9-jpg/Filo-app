import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentClass {
  const StudentClass(this.id, this.name, this.archived);
  final String id, name;
  final bool archived;
}

class StudentClasses {
  StudentClasses(this.uid);
  final String uid;

  Future<void> leave(String classId) async {
    final ref = FirebaseFirestore.instance.collection('classes').doc(classId)
        .collection('enrollments').doc(uid);
    // Transactions require a connection; an offline tap cannot queue a surprise
    // membership deletion for later. Rules restrict deletion to this student.
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final enrollment = await transaction.get(ref);
      if (enrollment.exists) transaction.delete(ref);
    }).timeout(const Duration(seconds: 20));
  }

  // Query the authoritative enrollments. No mirrored user index or server
  // trigger is needed. Firestore's native cache retains offline discovery.
  Stream<({List<StudentClass> classes, bool offline})> watch() {
    late StreamController<({List<StudentClass> classes, bool offline})> output;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? memberships;
    final listeners = <String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>>{};
    final values = <String, StudentClass>{};
    var offline = true;
    var closed = false;
    void emit() {
      if (closed) return;
      final items = values.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      output.add((classes: items, offline: offline));
    }
    output = StreamController(onListen: () {
      memberships = FirebaseFirestore.instance.collectionGroup('enrollments')
          .where('studentId', isEqualTo: uid)
          .snapshots(includeMetadataChanges: true).listen((snapshot) {
        if (closed) return;
        offline = snapshot.metadata.isFromCache;
        // An empty initial cache is not proof that membership was revoked.
        if (offline && snapshot.docs.isEmpty && values.isNotEmpty) { emit(); return; }
        final refs = <String, DocumentReference<Map<String, dynamic>>>{};
        for (final doc in snapshot.docs) {
          final course = doc.reference.parent.parent;
          if (course == null || course.parent.path != 'classes' || doc.id != uid) continue;
          refs[course.id] = course;
        }
        for (final id in listeners.keys.toList()) {
          if (refs.containsKey(id)) continue;
          listeners.remove(id)?.cancel();
          values.remove(id);
        }
        for (final entry in refs.entries) {
          if (listeners.containsKey(entry.key)) continue;
          values[entry.key] = StudentClass(entry.key, 'Class', false);
          listeners[entry.key] = entry.value.snapshots().listen((doc) {
            if (closed || !listeners.containsKey(entry.key)) return;
            final data = doc.data();
            if (data != null) {
              values[entry.key] = StudentClass(entry.key,
                data['name'] as String? ?? data['title'] as String? ?? 'Class',
                data['archived'] == true);
            } else if (!doc.metadata.isFromCache) {
              values.remove(entry.key);
            }
            emit();
          }, onError: (Object error) {
            if (closed) return;
            if (error is FirebaseException && error.code == 'permission-denied') {
              values.remove(entry.key);
              emit();
            } else { output.addError(error); }
          });
        }
        emit();
      }, onError: (Object error) { if (!closed) output.addError(error); });
    }, onCancel: () async {
      closed = true;
      await memberships?.cancel();
      for (final listener in listeners.values) { await listener.cancel(); }
    });
    return output.stream;
  }
}
