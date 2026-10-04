import 'dart:async';
import 'dart:typed_data';
import 'material_dispatch.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'supabase_file_storage.dart';

const maxMaterialBytes = 25 * 1024 * 1024;

class PostAttachment {
  PostAttachment({required this.id, this.name = '', this.bytes, this.url = ''});
  final String id, name, url;
  final Uint8List? bytes;
}

class ClassMaterial {
  ClassMaterial(this.id, this.classId, this.data);
  final String id, classId;
  final Map<String, dynamic> data;
  String get title => data['title'] as String? ?? 'Material';
  String get kind => data['kind'] as String? ?? 'announcement';
  String get body => data['body'] as String? ?? '';
  String get url => data['url'] as String? ?? '';
  String get fileName => data['fileName'] as String? ?? '';
  String get storagePath => data['storagePath'] as String? ?? '';
  String get parentId => data['parentId'] as String? ?? '';
  List<String> get attachmentIds => (data['attachmentIds'] as List? ?? []).whereType<String>().toList();
  bool get requiresSubmission => data['requiresSubmission'] == true;
  int get maxPoints => (data['maxPoints'] as num?)?.toInt() ?? 100;
  int get revisionMinutes => (data['revisionMinutes'] as num?)?.toInt() ?? 5;
  DateTime? get dueAt => (data['dueAt'] as Timestamp?)?.toDate();
  bool get hasFile => (kind == 'file' || kind == 'announcement') && storagePath.isNotEmpty;
  int get size => (data['size'] as num?)?.toInt() ?? 0;
  DateTime? get createdAt => (data['createdAt'] as Timestamp?)?.toDate();
  String get cacheKey => '$classId/$id';
}

class MaterialRepository {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> collection(String classId) =>
      _db.collection('classes').doc(classId).collection('materials');
  Stream<List<ClassMaterial>> watch(String classId, {int? limit,
      void Function(List<ClassMaterial>)? onServerItems}) {
    Query<Map<String, dynamic>> query = collection(classId).orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);
    return query.snapshots(includeMetadataChanges: onServerItems != null)
      .map((s) {
        final items = s.docs.map((d) => ClassMaterial(d.id, classId, d.data())).toList();
        if (limit == null && !s.metadata.isFromCache && !s.metadata.hasPendingWrites) {
          onServerItems?.call(items);
        }
        return items;
      });
  }

  Future<void> postUnified({required String classId, required String id,
      required String title, required String body, required List<PostAttachment> attachments,
      bool requiresSubmission = false, int maxPoints = 100, int revisionMinutes = 5, DateTime? dueAt}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = collection(classId).doc(id);
    final dispatch = MaterialDispatch();
    await dispatch.prepare(classId, id);
    if ((await ref.get(const GetOptions(source: Source.server))).exists) {
      unawaited(dispatch.wake(classId, id).catchError((Object _) {}));
      return;
    }
    if (attachments.length > 10) throw StateError('Up to 10 attachments per post.');
    final documents = <String, Map<String, dynamic>>{};
    for (final attachment in attachments) {
      final bytes = attachment.bytes;
      final file = bytes != null;
      if (bytes != null && (bytes.isEmpty || bytes.length > maxMaterialBytes)) {
        throw StateError('Choose a file up to 25 MB.');
      }
      final path = bytes != null ? await SupabaseFileStorage().upload(classId, attachment.id, bytes) : '';
      documents[attachment.id] = {
        'title': (file ? attachment.name : title).trim().substring(0,
          (file ? attachment.name : title).trim().length.clamp(0, 120).toInt()),
        'kind': file ? 'file' : 'link', 'body': '', 'authorId': uid, 'classId': classId,
        'url': file ? '' : attachment.url, 'fileName': file ? attachment.name : '',
        'storagePath': path, 'size': bytes?.length ?? 0, 'parentId': id,
        'createdAt': FieldValue.serverTimestamp(),
      };
    }
    await _db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) return;
      tx.set(ref, {'title': title.trim(), 'kind': 'announcement', 'body': body.trim(),
        'authorId': uid, 'classId': classId, 'url': '', 'fileName': '', 'storagePath': '',
        'size': 0, 'attachmentIds': attachments.map((a) => a.id).toList(),
        'requiresSubmission': requiresSubmission, 'maxPoints': maxPoints,
        'revisionMinutes': revisionMinutes,
        if (requiresSubmission && dueAt != null) 'dueAt': Timestamp.fromDate(dueAt),
        'createdAt': FieldValue.serverTimestamp()});
      for (final entry in documents.entries) tx.set(collection(classId).doc(entry.key), entry.value);
    });
    unawaited(dispatch.wake(classId, id).catchError((Object _) {}));
  }

  Future<void> deletePost(ClassMaterial item) async {
    final batch = _db.batch();
    for (final id in item.attachmentIds) batch.delete(collection(item.classId).doc(id));
    batch.delete(collection(item.classId).doc(item.id));
    await batch.commit();
  }

  // The form reserves one ID. A transaction makes retries idempotent even when
  // a previous response was lost. Posting requires a live connection.
  Future<void> post({required String classId, required String id,
    required String title, required String kind, required String body,
    String url = '', String fileName = '', Uint8List? bytes}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = collection(classId).doc(id);
    final dispatch = MaterialDispatch();
    await dispatch.prepare(classId, id);
    final existing = await ref.get(const GetOptions(source: Source.server));
    if (existing.exists) {
      unawaited(dispatch.wake(classId, id).catchError((Object _) {}));
      return;
    }
    var path = '';
    final attachFile = kind == 'file' || (kind == 'announcement' && bytes != null);
    if (attachFile) {
      if (bytes == null || bytes.isEmpty || bytes.length > maxMaterialBytes) {
        throw StateError('Choose a file up to 25 MB.');
      }
      path = await SupabaseFileStorage().upload(classId, id, bytes);
    }
    await _db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) return;
      tx.set(ref, {
        'title': title.trim(), 'kind': kind, 'body': body.trim(),
        'authorId': uid, 'classId': classId,
        'url': kind == 'link' ? url.trim() : '',
        'fileName': attachFile ? fileName : '',
        'storagePath': attachFile ? path : '',
        'size': attachFile ? bytes!.length : 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    unawaited(dispatch.wake(classId, id).catchError((Object _) {}));
  }
}
