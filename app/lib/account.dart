/// Account helpers for the UI. Pure functions; a port of web/src/lib/{account,admin}.ts.
library;

import 'api/client.dart';
import 'i18n.dart';

/// The display name if set, otherwise the username.
String greetingName(Me me) {
  final name = me.displayName?.trim() ?? '';
  return name.isNotEmpty ? name : me.username;
}

const displayNameMax = 64;
final _control = RegExp('[\u0000-\u001f\u007f-\u009f]');

/// Mirrors the server's rules: trimmed, at most 64 characters, no control characters.
/// Returns the value to send (null clears the name); throws FormatException if invalid.
String? displayNameInput(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return null;
  if (name.runes.length > displayNameMax || _control.hasMatch(name)) {
    throw const FormatException('invalid display name');
  }
  return name;
}

const passwordMin = 8;
final _username = RegExp(r'^[\p{L}\p{N}_.-]{1,64}$', unicode: true);

/// Checks before sending; the server checks again. Null when fine, else a message.
String? checkNewUser(String username, String password) {
  if (!_username.hasMatch(username)) return t('admin.error.username');
  return checkPassword(password);
}

String? checkPassword(String password) =>
    password.runes.length < passwordMin ? t('admin.error.password') : null;

/// German message for a failed admin request (the server's texts are English).
String errorMessage(ApiException e) {
  if (e.offline) return t('admin.error.offline');
  final text = e.detail ?? '';
  const known = [
    ('taken', 'admin.error.taken'),
    ('username', 'admin.error.username'),
    ('password', 'admin.error.password'),
    ('display name', 'admin.error.name'),
    ('own account', 'admin.error.self'),
    ('unknown profiles', 'admin.error.profiles'),
  ];
  for (final (needle, key) in known) {
    if (text.contains(needle)) return t(key);
  }
  if (e.status == 401) return t('login.expired');
  if (e.status == 403) return t('admin.error.forbidden');
  return t('admin.error.generic');
}

/// The server address as typed: https:// is added when missing, a trailing slash dropped.
/// Null if it is not a usable address.
String? normalizeServerUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (!s.contains('://')) s = 'https://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) {
    return null;
  }
  return uri.origin;
}
