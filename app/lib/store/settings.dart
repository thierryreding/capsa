/// Synced settings, last write wins by `updatedAt` (SPEC 6). The merge is a pure function;
/// on equal timestamps the server's value stays, as the server decides it too.
/// A port of web/src/lib/store/settings.ts.
library;

class LocalSetting {
  const LocalSetting({required this.value, required this.updatedAt, required this.dirty});

  factory LocalSetting.fromJson(Map<String, Object?> j) => LocalSetting(
    value: j['value'],
    updatedAt: (j['updatedAt'] as num).toInt(),
    dirty: j['dirty'] as bool,
  );

  /// Any JSON value.
  final Object? value;

  /// Time of the change (ms since epoch).
  final int updatedAt;

  /// Changed locally and not yet confirmed by the server.
  final bool dirty;

  Map<String, Object?> toJson() => {'value': value, 'updatedAt': updatedAt, 'dirty': dirty};

  @override
  bool operator ==(Object other) =>
      other is LocalSetting &&
      _jsonEquals(other.value, value) &&
      other.updatedAt == updatedAt &&
      other.dirty == dirty;

  @override
  int get hashCode => Object.hash(updatedAt, dirty);

  @override
  String toString() => 'LocalSetting${toJson()}';
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    return a.length == b.length &&
        [for (var i = 0; i < a.length; i++) i].every((i) => _jsonEquals(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _jsonEquals(a[k], b[k]));
  }
  return a == b;
}

typedef RemoteSetting = ({String key, Object? value, int updatedAt});

/// The merged settings, and the keys whose local value has to be sent to the server.
({Map<String, LocalSetting> settings, List<String> push}) mergeSettings(
  Map<String, LocalSetting> local,
  List<RemoteSetting> remote,
) {
  final settings = {...local};
  for (final r in remote) {
    final mine = local[r.key];
    if (mine == null || r.updatedAt >= mine.updatedAt) {
      settings[r.key] = LocalSetting(value: r.value, updatedAt: r.updatedAt, dirty: false);
    }
  }
  // Whatever is still dirty is newer than the server's value (or unknown to it).
  final push = [
    for (final e in settings.entries)
      if (e.value.dirty) e.key,
  ];
  return (settings: settings, push: push);
}
