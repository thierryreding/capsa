/// Synchronisation with the server (SPEC 6). Local data is the source of truth; the
/// server collects events from all devices. Every step is idempotent, so an interrupted
/// sync is simply repeated next time. A port of web/src/lib/store/{sync,profiles}.ts.
library;

import 'package:sembast/sembast.dart';

import '../api/client.dart';
import 'db.dart';
import 'settings.dart';

const batch = 500;
const _sinceKey = 'sync.since';
const _settingsKey = 'settings';
const _lastSyncKey = 'sync.last';

/// Upload events not yet on the server.
Future<({int pushed, int rejected})> pushEvents(ApiClient api, UserStore store) async {
  var pushed = 0;
  var rejected = 0;
  for (;;) {
    final pending = await store.pendingEvents(batch);
    if (pending.isEmpty) break;
    final result = await api.uploadEvents([for (final e in pending) e.toUpload()]);
    await store.db.transaction((txn) async {
      for (final e in pending) {
        // Rejected events are not retried (e.g. the profile was withdrawn).
        await store.events.record(e.id).update(txn, {
          'synced': 1,
          'rejected': result.rejected[e.id],
        });
      }
    });
    pushed += result.accepted;
    rejected += result.rejected.length;
    if (pending.length < batch) break;
  }
  return (pushed: pushed, rejected: rejected);
}

/// Fetch events this device has not seen yet (from all devices, including its own).
Future<int> pullEvents(ApiClient api, UserStore store) async {
  var since = await store.getMeta<int>(_sinceKey) ?? 0;
  var pulled = 0;
  for (;;) {
    final page = await api.downloadEvents(since, batch);
    final events = [for (final e in page.events) LocalEvent.fromServer(e)];
    await store.db.transaction((txn) async {
      final known = await store.events.records([for (final e in events) e.id]).get(txn);
      pulled += known.where((k) => k == null).length;
      // Server copies win: they carry received_at and server_seq.
      await store.events.records([for (final e in events) e.id]).put(txn, [
        for (final e in events) e.toRecord(),
      ]);
      await store.setMeta(_sinceKey, page.nextSince, txn);
    });
    since = page.nextSince;
    if (!page.more) break;
  }
  return pulled;
}

Future<Map<String, LocalSetting>> localSettings(UserStore store, [DatabaseClient? client]) async {
  final raw = await store.getMeta<Map>(_settingsKey, client) ?? const {};
  return {
    for (final e in raw.entries) e.key as String: LocalSetting.fromJson((e.value as Map).cast()),
  };
}

Future<void> _saveSettings(UserStore store, Map<String, LocalSetting> s, DatabaseClient client) =>
    store.setMeta(_settingsKey, {for (final e in s.entries) e.key: e.value.toJson()}, client);

/// Change a setting locally; it is sent with the next sync.
Future<void> setSetting(UserStore store, String key, Object? value, [int? now]) =>
    store.db.transaction((txn) async {
      final all = await localSettings(store, txn);
      all[key] = LocalSetting(
        value: value,
        updatedAt: now ?? DateTime.now().millisecondsSinceEpoch,
        dirty: true,
      );
      await _saveSettings(store, all, txn);
    });

int _ms(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;
String _iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

/// A client error other than "not signed in": retrying the same request cannot help.
bool _isRefused(int? status) =>
    status != null && status >= 400 && status < 500 && status != 401 && status != 429;

Future<int> syncSettings(ApiClient api, UserStore store) async {
  final remote = [
    for (final s in await api.settings()) (key: s.key, value: s.value, updatedAt: _ms(s.updatedAt)),
  ];
  final local = await localSettings(store);
  final merged = mergeSettings(local, remote);
  final settings = merged.settings;
  for (final key in merged.push) {
    final s = settings[key]!;
    try {
      final winner = await api.putSetting(key, s.value, _iso(s.updatedAt));
      settings[key] = LocalSetting(
        value: winner.value,
        updatedAt: _ms(winner.updatedAt),
        dirty: false,
      );
    } on ApiException catch (e) {
      if (!_isRefused(e.status)) rethrow;
      // The server refuses this value (e.g. an invalid display name from an older app
      // version): take the server's value, or drop ours, instead of retrying forever.
      final theirs = remote.where((x) => x.key == key).firstOrNull;
      if (theirs != null) {
        settings[key] = LocalSetting(
          value: theirs.value,
          updatedAt: theirs.updatedAt,
          dirty: false,
        );
      } else {
        settings.remove(key);
      }
    }
  }
  // Keep changes made while this sync was running.
  await store.db.transaction((txn) async {
    final current = await localSettings(store, txn);
    for (final MapEntry(:key, value: s) in current.entries) {
      // Changed during the sync = newer than what this sync started from.
      if (s.dirty && s.updatedAt > (local[key]?.updatedAt ?? -1)) settings[key] = s;
    }
    await _saveSettings(store, settings, txn);
  });
  return merged.push.length;
}

typedef SyncResult = ({int pushed, int pulled, int rejected, int settingsPushed});

/// Full sync: upload, download, settings. Throws ApiException on network or server errors.
Future<SyncResult> syncAll(ApiClient api, UserStore store, [int? now]) async {
  final (:pushed, :rejected) = await pushEvents(api, store);
  final pulled = await pullEvents(api, store);
  final settingsPushed = await syncSettings(api, store);
  await store.setMeta(_lastSyncKey, now ?? DateTime.now().millisecondsSinceEpoch);
  return (pushed: pushed, pulled: pulled, rejected: rejected, settingsPushed: settingsPushed);
}

Future<int?> lastSync(UserStore store) => store.getMeta<int>(_lastSyncKey);

/// Fetch the profile list; download profiles whose ETag changed; delete local copies
/// of profiles that are no longer released (their content must not stay on the device).
Future<({List<String> updated, List<String> removed})> refreshProfiles(
  ApiClient api,
  UserStore store, [
  int? now,
]) async {
  final summaries = await api.profiles();
  final local = {for (final p in await store.localProfiles()) p.id: p};
  final updated = <String>[];
  for (final s in summaries) {
    final have = local[s.id];
    if (have?.etag == s.etag) continue;
    final fetched = await api.profile(s.id, etag: have?.etag);
    if (fetched == null) continue;
    await store.profiles.record(s.id).put(store.db, {
      'etag': fetched.etag.isEmpty ? s.etag : fetched.etag,
      'doc': fetched.doc,
      'fetchedAt': now ?? DateTime.now().millisecondsSinceEpoch,
    });
    updated.add(s.id);
  }
  final released = {for (final s in summaries) s.id};
  final removed = [
    for (final id in local.keys)
      if (!released.contains(id)) id,
  ];
  if (removed.isNotEmpty) await store.profiles.records(removed).delete(store.db);
  return (updated: updated, removed: removed);
}
