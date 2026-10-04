import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class _DownloadEntry {
  const _DownloadEntry(this.signature, this.future);
  final String signature;
  final Future<dynamic> future;
}

/// Session-only disk metadata cache. File bytes remain in account/class folders.
class DownloadIndex with WidgetsBindingObserver {
  DownloadIndex._() {
    WidgetsBinding.instance.addObserver(this);
    _uid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_uid != user?.uid) { _uid = user?.uid; invalidate(); }
    });
  }
  static final instance = DownloadIndex._();
  final revision = ValueNotifier<int>(0);
  final _entries = <String, _DownloadEntry>{};
  String? _uid;

  Future<T> read<T>(String uid, String key, String signature, Future<T> Function() load) {
    final scoped = '$uid/$key';
    final entry = _entries[scoped];
    if (entry != null && entry.signature == signature) return entry.future as Future<T>;
    // Bound the metadata cache; disk contents are unaffected by eviction.
    if (_entries.length >= 1000) _entries.remove(_entries.keys.first);
    final future = load();
    _entries[scoped] = _DownloadEntry(signature, future);
    future.then<void>((_) {}, onError: (Object error, StackTrace stack) {
      if (identical(_entries[scoped]?.future, future)) _entries.remove(scoped);
    });
    return future;
  }

  void invalidate({String? uid, String? classId, String? materialId}) {
    if (uid == null) { _entries.clear(); }
    else { _entries.removeWhere((key, _) => key.startsWith(
      classId == null ? '$uid/' : materialId == null ? '$uid/$classId/'
        : '$uid/$classId/$materialId/')); }
    revision.value++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) invalidate();
  }
}
