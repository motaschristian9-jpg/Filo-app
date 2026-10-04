import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'material_cache.dart';
import 'material_repository.dart';

enum FileSyncState { pending, downloading, ready, failed }

// One queue for all enrolled classes, independent of the currently open screen.
// Firestore persists announcements/link metadata on Android and iOS; file bytes
// live separately in application support storage, scoped to the signed-in UID.
class MaterialSync extends ChangeNotifier {
  MaterialSync(this.uid) : cache = MaterialCache(uid);
  final String uid;
  final MaterialCache cache;
  final repository = MaterialRepository();
  final Map<String, List<ClassMaterial>> materials = {};
  final Map<String, FileSyncState> states = {};
  final Set<String> errors = {};
  final Map<String, StreamSubscription<List<ClassMaterial>>> _streams = {};
  final Set<String> _classes = {};
  bool _disposed = false, _running = false, _again = false;
  final Map<String, List<ClassMaterial>> _cleanup = {};

  bool hasClass(String id) => _classes.contains(id);

  void setClasses(Iterable<String> ids) {
    if (_disposed) return;
    final next = ids.toSet();
    for (final id in _classes.difference(next)) {
      _streams.remove(id)?.cancel();
      materials.remove(id);
      errors.remove(id);
      _cleanup.remove(id);
      states.removeWhere((key, _) => key.startsWith('$id/'));
      unawaited(cache.removeClass(id).catchError((Object _) {}));
    }
    _classes
      ..clear()
      ..addAll(next);
    for (final id in next) {
      _streams.putIfAbsent(id, () => repository.watch(id, onServerItems: (items) {
        if (!_disposed && _classes.contains(id)) _cleanup[id] = items;
      }).listen((items) {
        if (_disposed || !_classes.contains(id)) return;
        materials[id] = items;
        final keys = items.where((item) => item.hasFile).map((item) => item.cacheKey).toSet();
        states.removeWhere((key, _) => key.startsWith('$id/') && !keys.contains(key));
        errors.remove(id);
        notifyListeners();
        unawaited(_drain());
      }, onError: (Object error) {
        if (_disposed) return;
        errors.add(id);
        if (error is FirebaseException && error.code == 'permission-denied') {
          materials.remove(id);
          states.removeWhere((key, _) => key.startsWith('$id/'));
          unawaited(cache.removeClass(id).catchError((Object _) {}));
        }
        notifyListeners();
      }));
    }
    notifyListeners();
  }

  void retry() {
    if (_disposed) return;
    states.removeWhere((_, state) => state == FileSyncState.failed);
    // A permission/network error may have ended a listener. Recreate it.
    for (final id in errors.toList()) {
      _streams.remove(id)?.cancel();
    }
    setClasses(_classes.toList());
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_disposed || !cache.supported) return;
    if (_running) { _again = true; return; }
    _running = true;
    try {
      do {
        _again = false;
        for (final entry in _cleanup.entries.toList()) {
          _cleanup.remove(entry.key);
          bool active() => !_disposed && _classes.contains(entry.key) &&
            !errors.contains(entry.key) && identical(materials[entry.key], entry.value);
          try { await cache.reconcileClass(entry.key, entry.value, active); }
          catch (_) { /* Cleanup never blocks lesson downloads. */ }
        }
        final files = materials.values.expand((items) => items)
            .where((item) => item.hasFile).toList();
        var next = 0;
        Future<void> worker() async {
          while (next < files.length && !_disposed) {
          final item = files[next++];
          bool active() => !_disposed && _classes.contains(item.classId) &&
              !errors.contains(item.classId) &&
              (materials[item.classId]?.any((current) => current.id == item.id &&
                current.storagePath == item.storagePath && current.size == item.size) ?? false);
          if (!active() || states[item.cacheKey] == FileSyncState.failed) continue;
          try {
            if (await cache.contains(item)) {
              if (active()) states[item.cacheKey] = FileSyncState.ready;
            } else {
              if (!active()) continue;
              states[item.cacheKey] = FileSyncState.downloading;
              notifyListeners();
              await cache.download(item, active);
              if (active()) states[item.cacheKey] = FileSyncState.ready;
            }
          } catch (_) {
            if (active()) states[item.cacheKey] = FileSyncState.failed;
          }
          if (!_disposed) notifyListeners();
          }
        }
        // At most two background downloads/byte buffers across all classes.
        await Future.wait([worker(), worker()]);
      } while (_again && !_disposed);
    } finally { _running = false; }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _streams.values) { subscription.cancel(); }
    super.dispose();
  }
}
