/// Local storage (sembast). The local store is the source of truth for progress
/// (SPEC 3); the server is the sync target. Same layout as the PWA's IndexedDB:
///
/// - One database per account (`capsa-<user id>`), so several children can share a
///   device without mixing progress.
/// - One device-wide database (`capsa-device`) for the device id, the last signed-in
///   account (to start offline), the server address and, outside the browser, the
///   session cookie.
library;

import 'package:sembast/sembast.dart';

import '../api/client.dart';
import '../learning/leitner.dart';
import '../learning/match.dart';
import '../learning/profile.dart';
import '../learning/uuid.dart';
import 'db_factory.dart';

/// How an answer was given (the API's `mode`).
enum Mode { typed, flashcard, choice, parent }

/// Opens databases by name; tests pass an in-memory factory.
typedef DatabaseOpener = Future<Database> Function(String name);

final _meta = StoreRef<String, Object?>('meta');

class DeviceStore {
  DeviceStore(this.db);

  static Future<DeviceStore> open([DatabaseOpener opener = openPlatformDatabase]) async =>
      DeviceStore(await opener('capsa-device'));

  final Database db;

  /// Stable random id of this installation.
  Future<String> deviceId() => db.transaction((txn) async {
    final found = await _meta.record('device_id').get(txn) as String?;
    if (found != null) return found;
    final id = uuidv7().replaceAll('-', '');
    await _meta.record('device_id').put(txn, id);
    return id;
  });

  /// The last signed-in account, so the app can start without a network.
  Future<Me?> lastUser() async {
    final j = await _meta.record('last_user').get(db) as Map?;
    return j == null ? null : Me.fromJson(j.cast());
  }

  Future<void> setLastUser(Me? me) async {
    if (me == null) {
      await _meta.record('last_user').delete(db);
    } else {
      await _meta.record('last_user').put(db, me.toJson());
    }
  }

  Future<String?> serverUrl() async => await _meta.record('server_url').get(db) as String?;
  Future<void> setServerUrl(String url) => _meta.record('server_url').put(db, url);

  /// The session cookie (Android and iOS; the browser keeps its own).
  Future<String?> cookie() async => await _meta.record('cookie').get(db) as String?;
  Future<void> setCookie(String? value) async {
    if (value == null) {
      await _meta.record('cookie').delete(db);
    } else {
      await _meta.record('cookie').put(db, value);
    }
  }
}

class StoredProfile {
  StoredProfile({
    required this.id,
    required this.etag,
    required this.json,
    required this.fetchedAt,
  });

  factory StoredProfile.fromRecord(String id, Map<String, Object?> r) => StoredProfile(
    id: id,
    etag: r['etag'] as String,
    json: (r['doc'] as Map).cast(),
    fetchedAt: (r['fetchedAt'] as num).toInt(),
  );

  final String id;
  final String etag;
  final Map<String, Object?> json;
  final int fetchedAt;

  late final ProfileDocument doc = ProfileDocument.fromJson(json);
}

class LocalEvent extends AnswerEvent {
  const LocalEvent({
    required super.id,
    required super.profileId,
    required super.entryId,
    required super.direction,
    required super.correct,
    required super.ts,
    super.receivedAt,
    required this.deviceId,
    required this.mode,
    this.responseMs,
    this.serverSeq,
    this.synced = false,
    this.rejected,
  });

  factory LocalEvent.fromRecord(Map<String, Object?> r) => LocalEvent(
    id: r['id'] as String,
    deviceId: r['device_id'] as String,
    profileId: r['profile_id'] as String,
    entryId: r['entry_id'] as String,
    direction: Direction.fromWire(r['direction'] as String),
    mode: Mode.values.byName(r['mode'] as String),
    correct: r['correct'] as bool,
    responseMs: (r['response_ms'] as num?)?.toInt(),
    ts: (r['ts'] as num).toInt(),
    receivedAt: (r['received_at'] as num?)?.toInt(),
    serverSeq: (r['server_seq'] as num?)?.toInt(),
    synced: (r['synced'] as int) == 1,
    rejected: r['rejected'] as String?,
  );

  /// A copy from the server (`StoredEvent`); it carries received_at and server_seq.
  factory LocalEvent.fromServer(Map<String, Object?> e) => LocalEvent(
    id: e['id'] as String,
    deviceId: e['device_id'] as String,
    profileId: e['profile_id'] as String,
    entryId: e['entry_id'] as String,
    direction: Direction.fromWire(e['direction'] as String),
    mode: Mode.values.byName(e['mode'] as String),
    correct: e['correct'] as bool,
    responseMs: (e['response_ms'] as num?)?.toInt(),
    ts: DateTime.parse(e['ts'] as String).millisecondsSinceEpoch,
    receivedAt: DateTime.parse(e['received_at'] as String).millisecondsSinceEpoch,
    serverSeq: (e['server_seq'] as num).toInt(),
    synced: true,
  );

  final String deviceId;
  final Mode mode;
  final int? responseMs;
  final int? serverSeq;

  /// On the server (or refused by it); such events are not uploaded again.
  final bool synced;

  /// Why the server refused the event, if it did.
  final String? rejected;

  Map<String, Object?> toRecord() => {
    'id': id,
    'device_id': deviceId,
    'profile_id': profileId,
    'entry_id': entryId,
    'direction': direction.wire,
    'mode': mode.name,
    'correct': correct,
    'response_ms': responseMs,
    'ts': ts,
    'received_at': receivedAt,
    'server_seq': serverSeq,
    // A number, so it can be filtered on like the PWA's Dexie index.
    'synced': synced ? 1 : 0,
    'rejected': rejected,
  };

  /// The upload shape (`Event`).
  Map<String, Object?> toUpload() => {
    'id': id,
    'device_id': deviceId,
    'profile_id': profileId,
    'entry_id': entryId,
    'direction': direction.wire,
    'mode': mode.name,
    'correct': correct,
    'response_ms': responseMs,
    'ts': DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toIso8601String(),
  };
}

class Answer {
  const Answer({
    required this.profileId,
    required this.entryId,
    required this.direction,
    required this.mode,
    required this.correct,
    this.responseMs,
  });

  final String profileId;
  final String entryId;
  final Direction direction;
  final Mode mode;
  final bool correct;
  final int? responseMs;
}

/// The data of one account on this device.
class UserStore {
  UserStore(this.db);

  static Future<UserStore> open(
    String userId, [
    DatabaseOpener opener = openPlatformDatabase,
  ]) async => UserStore(await opener('capsa-$userId'));

  final Database db;
  final profiles = StoreRef<String, Map<String, Object?>>('profiles');
  final events = StoreRef<String, Map<String, Object?>>('events');

  Future<void> close() => db.close();

  Future<T?> getMeta<T>(String key, [DatabaseClient? client]) async =>
      await _meta.record(key).get(client ?? db) as T?;

  Future<void> setMeta(String key, Object? value, [DatabaseClient? client]) =>
      _meta.record(key).put(client ?? db, value);

  Future<LocalEvent> recordAnswer(Answer answer, String device, [int? now]) async {
    final ts = now ?? DateTime.now().millisecondsSinceEpoch;
    final event = LocalEvent(
      id: uuidv7(ts),
      deviceId: device,
      profileId: answer.profileId,
      entryId: answer.entryId,
      direction: answer.direction,
      mode: answer.mode,
      correct: answer.correct,
      responseMs: answer.responseMs,
      ts: ts,
    );
    await events.record(event.id).add(db, event.toRecord());
    return event;
  }

  Future<List<LocalEvent>> allEvents() async => [
    for (final r in await events.find(db)) LocalEvent.fromRecord(r.value),
  ];

  Future<List<LocalEvent>> eventsForProfile(String profileId) async => [
    for (final r in await events.find(
      db,
      finder: Finder(filter: Filter.equals('profile_id', profileId)),
    ))
      LocalEvent.fromRecord(r.value),
  ];

  Future<List<LocalEvent>> pendingEvents(int limit) async => [
    for (final r in await events.find(
      db,
      finder: Finder(filter: Filter.equals('synced', 0), limit: limit),
    ))
      LocalEvent.fromRecord(r.value),
  ];

  Future<int> unsyncedCount() => events.count(db, filter: Filter.equals('synced', 0));

  Future<List<StoredProfile>> localProfiles() async {
    final list = [
      for (final r in await profiles.find(db)) StoredProfile.fromRecord(r.key, r.value),
    ];
    return list..sort((a, b) => a.doc.profile.title.compareTo(b.doc.profile.title));
  }
}
