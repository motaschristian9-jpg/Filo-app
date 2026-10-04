import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthorProfileState {
  const AuthorProfileState({this.data, this.loading = false});
  final Map<String, dynamic>? data;
  final bool loading;
}

class _AuthorValue extends ValueNotifier<AuthorProfileState> {
  _AuthorValue() : super(const AuthorProfileState(loading: true));
  bool get observed => hasListeners;
}

class _AuthorEntry {
  final value = _AuthorValue();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? subscription;
}

/// One live Firestore subscription per author, shared by all open post screens.
class AuthorCache {
  AuthorCache._() {
    _uid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (_uid == user?.uid) return;
      _uid = user?.uid;
      for (final entry in _entries.values) {
        entry.subscription?.cancel();
        entry.value.value = const AuthorProfileState();
      }
      _entries.clear();
    });
  }
  static final instance = AuthorCache._();
  String? _uid;
  final _entries = <String, _AuthorEntry>{};
  final _empty = ValueNotifier<AuthorProfileState>(const AuthorProfileState());

  ValueListenable<AuthorProfileState> watch(String viewerUid, String? authorId) {
    if (viewerUid != FirebaseAuth.instance.currentUser?.uid || authorId == null || authorId.isEmpty) return _empty;
    final key = '$viewerUid/$authorId';
    if (_entries[key] case final _AuthorEntry cached) return cached.value;
    if (_entries.length >= 64) {
      final idle = _entries.entries.where((e) => !e.value.value.observed).toList();
      if (idle.isNotEmpty) {
        final removed = _entries.remove(idle.first.key)!;
        removed.subscription?.cancel(); removed.value.dispose();
      }
    }
    final entry = _AuthorEntry();
    _entries[key] = entry;
    entry.subscription = FirebaseFirestore.instance.collection('users').doc(authorId).snapshots().listen((snapshot) {
      if (identical(_entries[key], entry)) entry.value.value = AuthorProfileState(data: snapshot.data());
    }, onError: (Object error) {
      if (identical(_entries[key], entry)) entry.value.value = AuthorProfileState(data: entry.value.value.data);
    });
    return entry.value;
  }
}
