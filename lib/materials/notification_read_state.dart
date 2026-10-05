import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read markers are private to this account on this device.
class NotificationReadState extends ChangeNotifier {
  NotificationReadState(String uid) : _key = 'filo.notificationReads.v1.$uid' {
    load();
  }
  final String _key;
  final _preferences = SharedPreferencesAsync();
  final _read = <String>{};
  bool ready = false, loadFailed = false, _disposed = false;
  Future<void> _writes = Future.value();
  bool isRead(String key) => _read.contains(key);

  Future<void> load() async {
    try {
      final saved = await _preferences.getStringList(_key) ?? <String>[];
      if (_disposed) return;
      _read.addAll(saved);
      ready = true;
      loadFailed = false;
    } catch (_) {
      if (_disposed) return;
      loadFailed = true;
    }
    notifyListeners();
  }

  Future<bool> markRead(String key) async {
    if (!ready) await load();
    if (_disposed || !ready) return false;
    if (!_read.add(key)) return true;
    notifyListeners();
    var saved = true;
    _writes = _writes.then((_) async {
      try {
        await _preferences.setStringList(_key, _read.toList());
      } catch (_) {
        saved = false;
        _read.remove(key);
        if (!_disposed) notifyListeners();
      }
    });
    await _writes;
    return saved;
  }

  @override
  void dispose() { _disposed = true; super.dispose(); }
}
