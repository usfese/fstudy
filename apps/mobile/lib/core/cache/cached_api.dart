import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client_cache.dart';

const _defaultCacheTtl = Duration(seconds: 30);

/// Implemented by repositories that can announce refreshed cached data.
abstract interface class CacheChangeSource {
  Listenable? get cacheChanges;
}

String cacheKeyFor(String path, [Map<String, Object?>? query]) {
  if (query == null || query.isEmpty) return 'GET $path';
  final keys = query.keys.toList()..sort();
  final pairs = <String>[];
  for (final key in keys) {
    final value = query[key];
    if (value == null) continue;
    pairs.add(
      '${Uri.encodeQueryComponent(key)}='
      '${Uri.encodeQueryComponent('$value')}',
    );
  }
  if (pairs.isEmpty) return 'GET $path';
  return 'GET $path?${pairs.join('&')}';
}

/// Stale-while-revalidate reads for Dio repositories.
///
/// A cache hit is returned immediately. If the entry is older than [ttl], a
/// background request refreshes the cache and notifies [cacheChanges], which
/// lets mounted pages repaint with the newer cloud state.
mixin CachedApi implements CacheChangeSource {
  ClientCache? get cache;

  final Map<String, _InflightRequest> _inflight = {};

  @override
  Listenable? get cacheChanges => cache?.changes;

  Future<Map<String, dynamic>> cachedGet(
    String path,
    Future<Map<String, dynamic>> Function() fetch, {
    Map<String, Object?>? query,
    Duration ttl = _defaultCacheTtl,
  }) async {
    final current = cache;
    if (current == null) return fetch();

    final key = cacheKeyFor(path, query);
    final version = current.versionOf(key);
    final entry = await current.read(key);
    if (entry == null) {
      return _fetchAndStore(current, key, version, fetch);
    }

    if (!current.isFresh(key, ttl)) {
      unawaited(
        _refresh(current, key, version, fetch).catchError((Object _) {}),
      );
    }
    return entry.data;
  }

  Future<void> storeCached(
    String path,
    Map<String, dynamic> data, {
    Map<String, Object?>? query,
    bool notify = true,
  }) async {
    final current = cache;
    if (current == null) return;
    final key = cacheKeyFor(path, query);
    current.bumpVersion(key);
    await current.write(key, data, notify: notify);
  }

  Future<void> invalidateCache(String path) async {
    await cache?.invalidatePath(path);
  }

  Future<void> invalidateCacheKey(String key) async {
    await cache?.invalidateKey(key);
  }

  Future<Map<String, dynamic>> _fetchAndStore(
    ClientCache current,
    String key,
    int version,
    Future<Map<String, dynamic>> Function() fetch,
  ) {
    final pending = _inflight[key];
    if (pending != null && pending.version == version) {
      return pending.future;
    }

    final future = Future.sync(fetch).then((data) async {
      await current.writeIfVersion(key, data, version);
      return data;
    });
    final request = _InflightRequest(version, future);
    _inflight[key] = request;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_inflight[key], request)) _inflight.remove(key);
        },
        onError: (Object _) {
          if (identical(_inflight[key], request)) _inflight.remove(key);
        },
      ),
    );
    return future;
  }

  Future<void> _refresh(
    ClientCache current,
    String key,
    int version,
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    try {
      await _fetchAndStore(current, key, version, fetch);
    } catch (_) {
      // A failed revalidation keeps the cached value on screen.
    }
  }
}

class _InflightRequest {
  const _InflightRequest(this.version, this.future);

  final int version;
  final Future<Map<String, dynamic>> future;
}
