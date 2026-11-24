import 'dart:convert';

import 'package:capsa/api/client.dart';
import 'package:capsa/learning/leitner.dart';
import 'package:capsa/learning/match.dart';
import 'package:capsa/store/db.dart';
import 'package:capsa/store/settings.dart';
import 'package:capsa/store/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';

import '../support.dart';

/// In-memory stand-in for the API, following the server's rules (idempotent upload,
/// server_seq paging, last-write-wins settings, ETags). Same as the PWA's sync tests.
class FakeServer {
  final events = <Map<String, Object?>>[];
  final settings = <String, ({Object? value, String updatedAt})>{};
  final released = {'demo-latin'};
  final requests = <String>[];
  var failNext = 0;
  var now = 1800000000000;
  final profileJson = loadProfileJson(demoProfile);
  var etag = '"r1"';

  ApiClient client() => ApiClient(baseUrl: 'https://capsa.test', httpClient: MockClient(_handle));

  Future<http.Response> _handle(http.Request req) async {
    final url = req.url;
    requests.add('${req.method} ${url.path}${url.hasQuery ? '?${url.query}' : ''}');
    if (failNext > 0) {
      failNext--;
      return http.Response('{"detail":"boom"}', 500);
    }
    if (req.method != 'GET' && req.headers[csrfHeader] != '1') {
      return http.Response('{"detail":"missing csrf"}', 403);
    }
    final body = req.method == 'GET' ? null : jsonDecode(req.body);
    final (status, result) = handle(req.method, url, body, req.headers);
    return http.Response.bytes(
      result == null ? [] : utf8.encode(jsonEncode(result)),
      status,
      headers: {'content-type': 'application/json', if (status != 304) 'etag': etag},
    );
  }

  (int, Object?) handle(String method, Uri url, dynamic body, Map<String, String> headers) {
    final path = url.path;
    if (path == '/api/v1/profiles') {
      return (
        200,
        [
          for (final id in released)
            {
              'id': id,
              'title': 'Demo',
              'source_lang': 'la',
              'required_translation_lang': 'de',
              'translation_langs': ['de'],
              'revision': 1,
              'etag': etag,
            },
        ],
      );
    }
    if (path.startsWith('/api/v1/profiles/')) {
      if (headers['if-none-match'] == etag) return (304, null);
      return (200, profileJson);
    }
    if (path == '/api/v1/sync/events' && method == 'POST') {
      var accepted = 0;
      var duplicates = 0;
      final rejected = <Map<String, String>>[];
      for (final e in (body['events'] as List).cast<Map<String, Object?>>()) {
        if (events.any((x) => x['id'] == e['id'])) {
          duplicates++;
        } else if (!released.contains(e['profile_id'])) {
          rejected.add({'id': e['id'] as String, 'reason': 'unknown_profile'});
        } else {
          events.add({
            ...e,
            'server_seq': events.length + 1,
            'received_at': DateTime.fromMillisecondsSinceEpoch(now, isUtc: true).toIso8601String(),
          });
          accepted++;
        }
      }
      return (200, {'accepted': accepted, 'duplicates': duplicates, 'rejected': rejected});
    }
    if (path == '/api/v1/sync/events') {
      final since = int.parse(url.queryParameters['since'] ?? '0');
      final limit = int.parse(url.queryParameters['limit'] ?? '500');
      final rest = events.where((e) => (e['server_seq'] as int) > since).toList();
      final page = rest.take(limit).toList();
      return (
        200,
        {
          'events': page,
          'next_since': page.isNotEmpty ? page.last['server_seq'] : since,
          'more': rest.length > limit,
        },
      );
    }
    if (path == '/api/v1/settings') {
      return (
        200,
        [
          for (final e in settings.entries)
            {'key': e.key, 'value': e.value.value, 'updated_at': e.value.updatedAt},
        ],
      );
    }
    final key = path.split('/').last;
    if (key == 'display_name' && body['value'] is String && (body['value'] as String).length > 64) {
      return (400, {'detail': 'display name: at most 64 characters'});
    }
    final current = settings[key];
    final updatedAt = body['updated_at'] as String;
    if (current == null || DateTime.parse(updatedAt).isAfter(DateTime.parse(current.updatedAt))) {
      settings[key] = (value: body['value'], updatedAt: updatedAt);
    }
    return (
      200,
      {'key': key, 'value': settings[key]!.value, 'updated_at': settings[key]!.updatedAt},
    );
  }
}

var _n = 0;
Future<UserStore> device() async =>
    UserStore(await newDatabaseFactoryMemory().openDatabase('sync-${_n++}'));

Answer answer(String entryId, [bool correct = true]) => Answer(
  profileId: 'demo-latin',
  entryId: entryId,
  direction: Direction.srcToTr,
  mode: Mode.typed,
  correct: correct,
  responseMs: 1000,
);

void main() {
  group('pushEvents', () {
    test('uploads pending events and marks them synced', () async {
      final server = FakeServer();
      final db = await device();
      await db.recordAnswer(answer('u1-nauta'), 'dev-a', 1);
      await db.recordAnswer(answer('u1-ventus', false), 'dev-a', 2);
      expect(await pushEvents(server.client(), db), (pushed: 2, rejected: 0));
      expect(await db.unsyncedCount(), 0);
      expect([for (final e in server.events) e['entry_id']], ['u1-nauta', 'u1-ventus']);
      expect(server.events.first['ts'], '1970-01-01T00:00:00.001Z');
      expect(await pushEvents(server.client(), db), (pushed: 0, rejected: 0));
    });
    test('uploads in batches of 500', () async {
      final server = FakeServer();
      final db = await device();
      for (var i = 0; i < 501; i++) {
        await db.recordAnswer(answer('u1-nauta'), 'dev-a', i);
      }
      expect((await pushEvents(server.client(), db)).pushed, 501);
      expect(server.requests.where((r) => r.startsWith('POST')), hasLength(2));
    });
    test('marks rejected events and does not retry them', () async {
      final server = FakeServer();
      final db = await device();
      await db.recordAnswer(
        const Answer(
          profileId: 'withdrawn',
          entryId: 'x',
          direction: Direction.srcToTr,
          mode: Mode.typed,
          correct: true,
        ),
        'dev-a',
        1,
      );
      expect(await pushEvents(server.client(), db), (pushed: 0, rejected: 1));
      final stored = (await db.allEvents()).single;
      expect((stored.synced, stored.rejected), (true, 'unknown_profile'));
      expect(await pushEvents(server.client(), db), (pushed: 0, rejected: 0));
    });
    test('keeps events pending when the upload fails, and retries safely', () async {
      final server = FakeServer();
      final db = await device();
      await db.recordAnswer(answer('u1-nauta'), 'dev-a', 1);
      server.failNext = 1;
      await expectLater(
        pushEvents(server.client(), db),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
      expect(await db.unsyncedCount(), 1);
      expect((await pushEvents(server.client(), db)).pushed, 1);
    });
  });

  group('pullEvents', () {
    test('pages through new events and remembers where it stopped', () async {
      final server = FakeServer();
      final a = await device();
      for (var i = 0; i < 1203; i++) {
        await a.recordAnswer(answer('u1-nauta'), 'dev-a', i);
      }
      await pushEvents(server.client(), a);
      final b = await device();
      expect(await pullEvents(server.client(), b), 1203);
      expect(server.requests.where((r) => r.startsWith('GET /api/v1/sync')), hasLength(3));
      server.requests.clear();
      expect(await pullEvents(server.client(), b), 0);
      expect(server.requests, ['GET /api/v1/sync/events?since=1203&limit=500']);
    });
    test('gives own events their received_at', () async {
      final server = FakeServer();
      final db = await device();
      final e = await db.recordAnswer(answer('u1-nauta'), 'dev-a', 5);
      await pushEvents(server.client(), db);
      expect(await pullEvents(server.client(), db), 0); // not new, but updated
      final stored = (await db.allEvents()).singleWhere((x) => x.id == e.id);
      expect((stored.receivedAt, stored.serverSeq), (server.now, 1));
    });
  });

  test('two devices converge on the same learning state', () async {
    final server = FakeServer();
    final phone = await device();
    final tablet = await device();
    await phone.recordAnswer(answer('u1-nauta'), 'phone', 1000);
    await tablet.recordAnswer(answer('u1-nauta', false), 'tablet', 2000);
    await tablet.recordAnswer(answer('u1-ventus'), 'tablet', 3000);
    await phone.recordAnswer(answer('u1-ventus'), 'phone', 4000); // offline meanwhile
    await syncAll(server.client(), phone);
    await syncAll(server.client(), tablet);
    await syncAll(server.client(), phone);
    const config = LeitnerConfig(utcOffsetMinutes: 0);
    final phoneStates = computeStates(await phone.allEvents(), config);
    expect(phoneStates, computeStates(await tablet.allEvents(), config));
    expect(phoneStates['demo-latin|u1-nauta|src_to_tr']?.box, 1); // wrong last
    expect(phoneStates['demo-latin|u1-ventus|src_to_tr']?.box, 3); // right twice
  });

  group('settings', () {
    test('merge: newer wins, server wins ties, unknown local values are pushed', () {
      LocalSetting l(int at) => LocalSetting(value: 'local', updatedAt: at, dirty: true);
      final (:settings, :push) = mergeSettings(
        {'a': l(20), 'b': l(10), 'c': l(10), 'd': l(10)},
        [
          (key: 'a', value: 'remote', updatedAt: 10),
          (key: 'b', value: 'remote', updatedAt: 20),
          (key: 'c', value: 'remote', updatedAt: 10),
          (key: 'e', value: 'remote', updatedAt: 5),
        ],
      );
      expect(push..sort(), ['a', 'd']);
      expect(settings['a']!.value, 'local');
      expect(settings['b'], const LocalSetting(value: 'remote', updatedAt: 20, dirty: false));
      expect(settings['c']!.value, 'remote');
      expect(settings['e']!.value, 'remote');
    });
    test('sync between two devices, last write wins', () async {
      final server = FakeServer();
      final phone = await device();
      final tablet = await device();
      await setSetting(phone, 'test-date', '2027-02-01', 1000);
      await syncAll(server.client(), phone);
      await syncAll(server.client(), tablet);
      expect((await localSettings(tablet))['test-date']!.value, '2027-02-01');
      await setSetting(tablet, 'test-date', '2027-03-01', 3000);
      await setSetting(phone, 'test-date', '2027-01-20', 2000); // older, made offline
      await syncAll(server.client(), phone);
      await syncAll(server.client(), tablet);
      await syncAll(server.client(), phone);
      for (final db in [phone, tablet]) {
        expect(
          (await localSettings(db))['test-date'],
          const LocalSetting(value: '2027-03-01', updatedAt: 3000, dirty: false),
        );
      }
    });
    test('structured values survive the round trip', () async {
      final server = FakeServer();
      final db = await device();
      final prefs = {
        'units': ['u1'],
        'mode': 'typed',
        'lang': null,
      };
      await setSetting(db, 'prefs.demo-latin', prefs, 1000);
      await syncAll(server.client(), db);
      final other = await device();
      await syncAll(server.client(), other);
      expect((await localSettings(other))['prefs.demo-latin']!.value, prefs);
    });
  });

  group('refused settings', () {
    test('a value the server refuses is replaced by the server value, not retried', () async {
      final server = FakeServer();
      final db = await device();
      await setSetting(db, 'display_name', 'Lena', 1000);
      await syncAll(server.client(), db);
      await setSetting(db, 'display_name', 'x' * 65, 2000);
      await setSetting(db, 'units', ['u1'], 2000);
      await syncAll(server.client(), db); // does not throw
      final settings = await localSettings(db);
      expect(
        settings['display_name'],
        const LocalSetting(value: 'Lena', updatedAt: 1000, dirty: false),
      );
      expect(settings['units']!.dirty, isFalse); // the other setting still went through
      server.requests.clear();
      await syncAll(server.client(), db);
      expect(server.requests.any((r) => r.startsWith('PUT')), isFalse);
    });
    test('a refused value unknown to the server is dropped', () async {
      final server = FakeServer();
      final db = await device();
      await setSetting(db, 'display_name', 'x' * 65, 1000);
      await syncAll(server.client(), db);
      expect((await localSettings(db))['display_name'], isNull);
    });
  });

  group('refreshProfiles', () {
    test('downloads changed profiles, skips unchanged ones, removes withdrawn ones', () async {
      final server = FakeServer();
      final db = await device();
      expect((await refreshProfiles(server.client(), db)).updated, ['demo-latin']);
      final stored = (await db.localProfiles()).single;
      expect(stored.doc.profile.id, 'demo-latin');
      expect(stored.etag, '"r1"');

      server.requests.clear();
      expect((await refreshProfiles(server.client(), db)).updated, isEmpty);
      expect(server.requests, ['GET /api/v1/profiles']);

      server.released.clear();
      expect((await refreshProfiles(server.client(), db)).removed, ['demo-latin']);
      expect(await db.localProfiles(), isEmpty);
    });
  });

  group('session cookie (native)', () {
    test('is taken from the login response, sent back, and cleared on logout', () async {
      String? stored;
      final seen = <String?>[];
      final api = ApiClient(
        baseUrl: 'https://capsa.test',
        onCookie: (c) => stored = c,
        httpClient: MockClient((req) async {
          seen.add(req.headers['cookie']);
          final me = {'id': 'u', 'username': 'lena', 'role': 'learner', 'display_name': null};
          return switch (req.url.path) {
            '/api/v1/auth/login' => http.Response(
              jsonEncode(me),
              200,
              headers: {
                'set-cookie':
                    'capsa_session=tok123; HttpOnly; Max-Age=7776000; Path=/api; SameSite=strict',
              },
            ),
            '/api/v1/auth/logout' => http.Response(
              '',
              204,
              headers: {'set-cookie': 'capsa_session=""; Max-Age=0; Path=/api'},
            ),
            _ => http.Response(jsonEncode(me), 200),
          };
        }),
      );
      expect((await api.login('lena', 'secret')).username, 'lena');
      expect(stored, 'tok123');
      await api.me();
      expect(seen.last, 'capsa_session=tok123');
      await api.logout();
      expect(stored, isNull);
      expect(api.cookie, isNull);
    });
    test('network failures are offline errors', () async {
      final api = ApiClient(
        baseUrl: 'https://capsa.test',
        httpClient: MockClient((_) => throw http.ClientException('no route')),
      );
      await expectLater(
        api.me(),
        throwsA(isA<ApiException>().having((e) => e.offline, 'offline', true)),
      );
    });
  });
}
