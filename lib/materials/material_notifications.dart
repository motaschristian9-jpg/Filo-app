import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class MaterialNotifications {
  MaterialNotifications(this.uid, this.onMessage);
  final String uid;
  final void Function(RemoteMessage, bool opened) onMessage;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _messages, _opened;
  String? _token;
  bool _active = true, _suspended = false;
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  DocumentReference<Map<String, dynamic>> _device(String token) => FirebaseFirestore.instance
      .collection('users').doc(uid).collection('devices').doc(base64Url.encode(utf8.encode(token)));

  Future<void> start() async {
    if (!supported || !_active) return;
    _suspended = false;
    _messages ??= FirebaseMessaging.onMessage.listen((message) => _deliver(message, false));
    _opened ??= FirebaseMessaging.onMessageOpenedApp.listen((message) => _deliver(message, true));
    _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_save(token).catchError((Object _) {}));
    });
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (!_active || _suspended) return;
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      throw StateError('Notifications are disabled');
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _save(token);
    if (!_active || _suspended) return;
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _deliver(initial, true);
  }

  void _deliver(RemoteMessage message, bool opened) {
    if (_active && !_suspended && message.data['uid'] == uid && FirebaseAuth.instance.currentUser?.uid == uid) {
      onMessage(message, opened);
    }
  }

  Future<void> _save(String token) async {
    if (!_active || _suspended || FirebaseAuth.instance.currentUser?.uid != uid) return;
    final previous = _token;
    await _device(token).set({'token': token, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 15));
    _token = token;
    if (previous != null && previous != token) await _device(previous).delete();
  }

  Future<void> unregister() async {
    if (!supported) return;
    _suspended = true;
    await _refresh?.cancel();
    _refresh = null;
    // Try both cleanup paths independently. Notification/network failures must
    // not prevent authentication sign-out. Offline Firestore deletes are queued.
    final token = _token;
    _token = null;
    await Future.wait([
      FirebaseMessaging.instance.deleteToken()
          .timeout(const Duration(seconds: 5)).catchError((Object _) {}),
      if (token != null) _device(token).delete()
          .timeout(const Duration(seconds: 5)).catchError((Object _) {}),
    ]);
  }

  void dispose() {
    _active = false;
    _refresh?.cancel(); _messages?.cancel(); _opened?.cancel();
  }
}
