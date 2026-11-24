import 'package:capsa/account.dart';
import 'package:capsa/api/client.dart';
import 'package:capsa/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('greetingName prefers the display name', () {
    expect(greetingName(const Me(id: 'u', username: 'lena', role: 'learner')), 'lena');
    expect(
      greetingName(const Me(id: 'u', username: 'lena', role: 'learner', displayName: ' ')),
      'lena',
    );
    expect(
      greetingName(const Me(id: 'u', username: 'lena', role: 'learner', displayName: 'Lena')),
      'Lena',
    );
  });

  test('displayNameInput mirrors the server rules', () {
    expect(displayNameInput('  Lena '), 'Lena');
    expect(displayNameInput('   '), isNull);
    expect(() => displayNameInput('x' * 65), throwsFormatException);
    expect(() => displayNameInput('a\u0007b'), throwsFormatException);
    expect(displayNameInput('😀' * 64), '😀' * 64); // code points, not UTF-16 units
  });

  test('new accounts and passwords', () {
    expect(checkNewUser('lena', 'geheim123'), isNull);
    expect(checkNewUser('lena maier', 'geheim123'), t('admin.error.username'));
    expect(checkNewUser('lena', 'kurz'), t('admin.error.password'));
    expect(checkNewUser('Jörg_2', 'geheim123'), isNull);
  });

  test('error messages for admin requests', () {
    expect(errorMessage(const ApiException(null)), t('admin.error.offline'));
    expect(errorMessage(const ApiException(409, 'username taken')), t('admin.error.taken'));
    expect(errorMessage(const ApiException(403)), t('admin.error.forbidden'));
    expect(errorMessage(const ApiException(500)), t('admin.error.generic'));
  });

  test('server addresses', () {
    expect(normalizeServerUrl('capsa.example.org'), 'https://capsa.example.org');
    expect(normalizeServerUrl('https://capsa.example.org/'), 'https://capsa.example.org');
    expect(normalizeServerUrl('http://10.0.2.2:8000'), 'http://10.0.2.2:8000');
    expect(normalizeServerUrl(''), isNull);
    expect(normalizeServerUrl('ftp://x'), isNull);
  });

  test('relative times in German', () {
    const now = 1800000000000;
    expect(relativeTime(now - 10000, now), 'gerade eben');
    expect(relativeTime(now - 60000, now), 'vor 1 Minute');
    expect(relativeTime(now - 5 * 60000, now), 'vor 5 Minuten');
    expect(relativeTime(now - 3600000, now), 'vor 1 Stunde');
    expect(relativeTime(now - 86400000, now), 'gestern');
    expect(relativeTime(now - 3 * 86400000, now), 'vor 3 Tagen');
  });

  test('every key used in t() exists', () {
    expect(t('quiz.of', {'n': 2, 'total': 10}), 'Karte 2 von 10');
  });
}
