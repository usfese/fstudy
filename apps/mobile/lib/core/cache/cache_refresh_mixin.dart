import 'package:flutter/material.dart';

import 'cached_api.dart';

/// Repaints a page when a repository has newer cached data.
///
/// Pages keep their previous data while the replacement future runs, so a
/// background refresh never replaces content with a spinner.
mixin CacheRefreshMixin<W extends StatefulWidget> on State<W> {
  Object? get cacheSource;

  void reloadFromCache();

  Listenable? _listenable;

  @override
  void initState() {
    super.initState();
    final source = cacheSource;
    if (source is CacheChangeSource) {
      _listenable = source.cacheChanges;
      _listenable?.addListener(_onCacheChanged);
    }
  }

  void _onCacheChanged() {
    if (mounted) reloadFromCache();
  }

  @override
  void dispose() {
    _listenable?.removeListener(_onCacheChanged);
    super.dispose();
  }
}
