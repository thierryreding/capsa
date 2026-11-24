import 'dart:convert';

import 'package:capsa/api/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support.dart';

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
  var loggedIn = false;
  var offline = false;
  final password = 'geheim123';
  Map<String, Object?> me = {
    'id': 'u-lena',
    'username': 'lena',
    'role': 'learner',
    'display_name': 'Lena',
  };
  final users = <Map<String, Object?>>[];

  ApiClient client() => ApiClient(baseUrl: 'https://capsa.test', httpClient: httpClient());

  http.Client httpClient() => MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    final url = req.url;
    requests.add('${req.method} ${url.path}${url.hasQuery ? '?${url.query}' : ''}');
    if (offline) throw http.ClientException('offline');
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
    if (path == '/api/v1/auth/login') {
      if (body['password'] != password) return (401, {'detail': 'invalid credentials'});
      loggedIn = true;
      return (200, me);
    }
    if (path == '/api/v1/auth/logout') {
      loggedIn = false;
      return (204, null);
    }
    if (path == '/api/v1/me') return loggedIn ? (200, me) : (401, {'detail': 'not signed in'});
    if (path == '/api/v1/admin/users' && method == 'GET') return (200, users);
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
