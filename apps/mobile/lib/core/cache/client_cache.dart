import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence boundary for the client cache.
///
/// Tests inject an in-memory implementation; production uses secure storage.
abstract interface class CacheStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCacheStorage implements CacheStorage {
  const SecureCacheStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class _CacheNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class CacheEntry {
  const CacheEntry({required this.data, required this.storedAt});

  final Map<String, dynamic> data;
  final DateTime storedAt;
}

/// One cache blob per signed-in account.
///
/// Entries are raw API response bodies. Keeping them on disk lets every page
/// paint the last known state before the network answers.
class ClientCache {
  ClientCache({
    required this.userId,
    CacheStorage? storage,
    DateTime Function()? now,
  }) : _storage = storage ?? const SecureCacheStorage(),
       _now = now ?? DateTime.now;

  static const _version = 1;

  final String userId;
  final CacheStorage _storage;
  final DateTime Function() _now;
  final Map<String, CacheEntry> _entries = {};
  final Map<String, int> _versions = {};
  final _CacheNotifier _changes = _CacheNotifier();

  Future<void>? _loading;
  Future<void> _writeQueue = Future.value();
  int _generation = 0;
  bool _cleared = false;

  String get storageKey => 'fstudy_cache_v${_version}_$userId';

  Listenable get changes => _changes;

  /// Loads persisted data without blocking the first frame.
  Future<void> warmUp() => _ensureLoaded();

  Future<CacheEntry?> read(String key) async {
    await _ensureLoaded();
    return _entries[key];
  }

  int versionOf(String key) => _versions.putIfAbsent(key, () => 0);

  void bumpVersion(String key) {
    if (_cleared) return;
    _versions[key] = versionOf(key) + 1;
  }

  bool isFresh(String key, Duration ttl) {
    final entry = _entries[key];
    if (entry == null) return false;
    return _now().difference(entry.storedAt) < ttl;
  }

  Future<void> write(
    String key,
    Map<String, dynamic> data, {
    bool notify = true,
  }) async {
    if (_cleared) return;
    await _ensureLoaded();
    _writeNow(key, data, notify: notify);
  }

  /// Writes only if no invalidation or newer write happened since [version].
  Future<void> writeIfVersion(
    String key,
    Map<String, dynamic> data,
    int version, {
    bool notify = true,
  }) async {
    if (_cleared) return;
    await _ensureLoaded();
    if (version != versionOf(key)) return;
    _writeNow(key, data, notify: notify);
  }

  void _writeNow(
    String key,
    Map<String, dynamic> data, {
    required bool notify,
  }) {
    if (_cleared) return;
    final previous = _entries[key];
    final changed = previous == null || !_sameJson(previous.data, data);
    _entries[key] = CacheEntry(data: data, storedAt: _now());
    _schedulePersist();
    if (notify && changed) _changes.notify();
  }

  Future<void> invalidatePath(String path) async {
    if (_cleared) return;
    await _ensureLoaded();
    final prefix = 'GET $path';
    bool matches(String key) =>
        key == prefix ||
        key.startsWith('$prefix?') ||
        key.startsWith('$prefix/');
    final keys = <String>{
      ..._entries.keys,
      ..._versions.keys,
    }.where(matches).toList();
    if (keys.isEmpty) return;
    for (final key in keys) {
      _versions[key] = versionOf(key) + 1;
      _entries.remove(key);
    }
    _schedulePersist();
  }

  Future<void> invalidateKey(String key) async {
    if (_cleared) return;
    await _ensureLoaded();
    final removed = _entries.remove(key) != null;
    if (!removed && !_versions.containsKey(key)) return;
    _versions[key] = versionOf(key) + 1;
    if (removed) _schedulePersist();
  }

  Future<void> clear() async {
    _cleared = true;
    _generation++;
    _entries.clear();
    _versions.clear();
    try {
      final loading = _loading;
      if (loading != null) await loading;
      await _writeQueue;
      await _storage.delete(storageKey);
    } catch (_) {
      // Cache clearing is best effort; in-memory data is already gone.
    }
  }

  void dispose() {
    _changes.dispose();
  }

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _storage.read(storageKey);
      if (raw == null || _cleared) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final entries = decoded['entries'];
      if (entries is! Map) return;
      for (final item in entries.entries) {
        final value = item.value;
        if (value is! Map) continue;
        final storedAt = value['at'];
        final data = value['data'];
        if (storedAt is! int || data is! Map) continue;
        _entries[item.key as String] = CacheEntry(
          data: Map<String, dynamic>.from(data),
          storedAt: DateTime.fromMillisecondsSinceEpoch(storedAt, isUtc: true),
        );
      }
    } catch (_) {
      _entries.clear();
      try {
        await _storage.delete(storageKey);
      } catch (_) {
        // A corrupt cache is equivalent to an empty cache.
      }
    }
  }

  void _schedulePersist() {
    final payload = _encode();
    if (payload == null) return;
    final generation = _generation;
    _writeQueue = _writeQueue
        .then<void>((_) async {
          if (_cleared || generation != _generation) return;
          await _storage.write(storageKey, payload);
        })
        .catchError((Object _) {});
  }

  String? _encode() {
    try {
      return jsonEncode({
        'version': _version,
        'entries': {
          for (final item in _entries.entries)
            item.key: {
              'at': item.value.storedAt.toUtc().millisecondsSinceEpoch,
              'data': item.value.data,
            },
        },
      });
    } catch (_) {
      return null;
    }
  }

  bool _sameJson(Map<String, dynamic> left, Map<String, dynamic> right) {
    try {
      return jsonEncode(left) == jsonEncode(right);
    } catch (_) {
      return false;
    }
  }
}
