import 'models.dart';

/// Task 13: short-lived cache for frequently revisited public reads (profiles,
/// post detail, first feed pages), so pushing the same screen again does not
/// refetch within [ttl].
///
/// - Allowlist only: never `users/me`, auth, verification, notifications or
///   chat; never cursor pages.
/// - Bounded: [maxEntries] (least recently used dropped) and [ttl].
/// - Partitioned by account: [DioRepository] clears it whenever the session
///   changes (sign-in, refresh, sign-out).
/// - Never hides the user's own changes: any successful write clears it, and
///   pull-to-refresh bypasses it. Changes made by others show after at most [ttl].
class ResponseCache {
  ResponseCache({
    this.ttl = const Duration(seconds: 30),
    this.maxEntries = 40,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _now;
  final _entries = <String, ({DateTime at, Json value})>{};

  static final _allowed = [
    RegExp(r'^posts$'),
    RegExp(r'^posts/[a-f0-9]{24}$'),
    RegExp(r'^users/(?!me$)[A-Za-z0-9_]+$'),
  ];

  static bool cacheable(String path, Json? query) =>
      !(query?.containsKey('cursor') ?? false) &&
      _allowed.any((pattern) => pattern.hasMatch(path));

  static String keyFor(String path, Json? query) {
    final entries = (query ?? const {}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$path?${entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  int get length => _entries.length;

  Json? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.at) > ttl) return null;
    _entries[key] = entry; // most recently used
    return entry.value;
  }

  void put(String key, Json value) {
    _entries.remove(key);
    _entries[key] = (at: _now(), value: value);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}
