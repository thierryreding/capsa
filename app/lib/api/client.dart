/// Client for the Capsa API (SPEC 5, schemas/openapi.json).
///
/// The PWA lets the browser keep the session cookie. This client does the same on the
/// web (the app is served from the API's origin), and on Android and iOS it keeps the
/// cookie itself: it reads `capsa_session` from the login response and sends it back
/// with every request.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../learning/stats.dart';

/// Sent on every state-changing request; the server refuses them without it.
const csrfHeader = 'X-Capsa-CSRF';
const sessionCookie = 'capsa_session';

/// A failed request. `status` is null when the server could not be reached at all;
/// 401 means the session has ended.
class ApiException implements Exception {
  const ApiException(this.status, [this.detail, this.retryAfterSeconds]);

  final int? status;
  final String? detail;
  final int? retryAfterSeconds;

  bool get offline => status == null;

  @override
  String toString() => 'ApiException($status, $detail)';
}

typedef Json = Map<String, Object?>;

class Me {
  const Me({required this.id, required this.username, required this.role, this.displayName});

  factory Me.fromJson(Json j) => Me(
    id: j['id'] as String,
    username: j['username'] as String,
    role: j['role'] as String,
    displayName: j['display_name'] as String?,
  );

  final String id;
  final String username;
  final String role;
  final String? displayName;

  bool get isAdmin => role == 'admin';

  Me withDisplayName(String? name) => Me(id: id, username: username, role: role, displayName: name);

  Json toJson() => {'id': id, 'username': username, 'role': role, 'display_name': displayName};
}

class ProfileSummary {
  const ProfileSummary({required this.id, required this.title, required this.etag});

  factory ProfileSummary.fromJson(Json j) =>
      ProfileSummary(id: j['id'] as String, title: j['title'] as String, etag: j['etag'] as String);

  final String id;
  final String title;
  final String etag;
}

class UserInfo {
  const UserInfo({
    required this.id,
    required this.username,
    required this.role,
    required this.disabled,
    required this.profiles,
    this.displayName,
  });

  factory UserInfo.fromJson(Json j) => UserInfo(
    id: j['id'] as String,
    username: j['username'] as String,
    role: j['role'] as String,
    disabled: j['disabled'] as bool,
    displayName: j['display_name'] as String?,
    profiles: [for (final p in j['profiles'] as List) p as String],
  );

  final String id;
  final String username;
  final String role;
  final bool disabled;
  final String? displayName;
  final List<String> profiles;

  String get name => displayName ?? username;
}

/// One remote setting (SPEC 6: last write wins by `updated_at`).
typedef RemoteSettingJson = ({String key, Object? value, String updatedAt});

/// The profile document, if it changed since `etag`.
typedef ProfileFetch = ({Json doc, String etag})?;

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? httpClient, this.cookie, this.onCookie})
    : _http = httpClient ?? http.Client();

  /// The server's origin, e.g. https://capsa.example.org; empty on the web, where the
  /// app is served from the same origin as the API.
  final String baseUrl;
  final http.Client _http;

  /// The session cookie value (native only; on the web the browser keeps it).
  String? cookie;

  /// Called when the server set or cleared the session cookie, so it can be stored.
  final void Function(String? cookie)? onCookie;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query);

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers.addAll(headers);
    if (method != 'GET') request.headers[csrfHeader] = '1';
    if (cookie != null) request.headers['Cookie'] = '$sessionCookie=$cookie';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on Exception {
      throw const ApiException(null);
    }
    _takeCookie(response);
    return response;
  }

  void _takeCookie(http.Response r) {
    final header = r.headers['set-cookie'];
    if (header == null) return;
    final match = RegExp('(?:^|[ ,])$sessionCookie=([^;]*)(;[^,]*)?').firstMatch(header);
    if (match == null) return;
    final value = match[1]!.replaceAll('"', '');
    final attributes = (match[2] ?? '').toLowerCase();
    final cleared = value.isEmpty || attributes.contains('max-age=0');
    cookie = cleared ? null : value;
    onCookie?.call(cookie);
  }

  Never _fail(http.Response r) {
    String? detail;
    try {
      final d = (jsonDecode(r.body) as Map)['detail'];
      detail = d is String ? d : null;
    } on Object {
      // not JSON
    }
    throw ApiException(r.statusCode, detail, int.tryParse(r.headers['retry-after'] ?? ''));
  }

  Future<Object?> _json(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final r = await _send(method, path, body: body, query: query);
    if (r.statusCode >= 400) _fail(r);
    return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  // --- account ---------------------------------------------------------------

  Future<Me> login(String username, String password) async => Me.fromJson(
    await _json('POST', '/auth/login', body: {'username': username, 'password': password}) as Json,
  );

  Future<void> logout() async {
    await _json('POST', '/auth/logout');
    cookie = null;
    onCookie?.call(null);
  }

  Future<Me> me() async => Me.fromJson(await _json('GET', '/me') as Json);

  // --- profiles --------------------------------------------------------------

  Future<List<ProfileSummary>> profiles() async => [
    for (final p in await _json('GET', '/profiles') as List) ProfileSummary.fromJson(p as Json),
  ];

  /// The full profile, or null if it is unchanged since `etag` (304).
  Future<ProfileFetch> profile(String id, {String? etag}) async {
    final r = await _send(
      'GET',
      '/profiles/${Uri.encodeComponent(id)}',
      headers: {'If-None-Match': ?etag},
    );
    if (r.statusCode == 304) return null;
    if (r.statusCode >= 400) _fail(r);
    return (
      doc: (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>(),
      etag: r.headers['etag'] ?? etag ?? '',
    );
  }

  // --- sync --------------------------------------------------------------------

  Future<({int accepted, Map<String, String> rejected})> uploadEvents(List<Json> events) async {
    final r = await _json('POST', '/sync/events', body: {'events': events}) as Json;
    return (
      accepted: (r['accepted'] as num).toInt(),
      rejected: {
        for (final x in r['rejected'] as List) (x as Map)['id'] as String: x['reason'] as String,
      },
    );
  }

  Future<({List<Json> events, int nextSince, bool more})> downloadEvents(
    int since,
    int limit,
  ) async {
    final r =
        await _json('GET', '/sync/events', query: {'since': '$since', 'limit': '$limit'}) as Json;
    return (
      events: [for (final e in r['events'] as List) (e as Map).cast<String, Object?>()],
      nextSince: (r['next_since'] as num).toInt(),
      more: r['more'] as bool,
    );
  }

  Future<List<RemoteSettingJson>> settings() async => [
    for (final s in await _json('GET', '/settings') as List)
      (key: (s as Map)['key'] as String, value: s['value'], updatedAt: s['updated_at'] as String),
  ];

  /// Store a setting if it is newer; the server answers with the winning value.
  Future<RemoteSettingJson> putSetting(String key, Object? value, String updatedAt) async {
    final s = await _json(
      'PUT',
      '/settings/${Uri.encodeComponent(key)}',
      body: {'value': value, 'updated_at': updatedAt},
    ) as Json;
    return (key: s['key'] as String, value: s['value'], updatedAt: s['updated_at'] as String);
  }

  // --- admin -------------------------------------------------------------------

  Future<List<UserInfo>> users() async => [
    for (final u in await _json('GET', '/admin/users') as List) UserInfo.fromJson(u as Json),
  ];

  Future<UserInfo> createUser(Json body) async =>
      UserInfo.fromJson(await _json('POST', '/admin/users', body: body) as Json);

  Future<UserInfo> updateUser(String id, Json body) async =>
      UserInfo.fromJson(await _json('PATCH', '/admin/users/$id', body: body) as Json);

  Future<LearningStats> userProgress(String userId, String profileId, int utcOffset) async =>
      LearningStats.fromJson(
        await _json(
          'GET',
          '/admin/users/$userId/progress/${Uri.encodeComponent(profileId)}',
          query: {'utc_offset': '$utcOffset'},
        ) as Json,
      );
}
