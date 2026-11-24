/// UI strings. German first; all strings live here so more languages can be added
/// (SPEC 13: UI language). Profile content is never translated. Same keys and texts as
/// web/src/lib/i18n.ts (without the PWA's install and update hints).
library;

import 'package:intl/intl.dart';

const _de = <String, String>{
  'app.title': 'Capsa',
  'app.offline': 'Offline – dein Fortschritt wird auf diesem Gerät gespeichert.',
  'login.title': 'Anmelden',
  'login.username': 'Benutzername',
  'login.password': 'Passwort',
  'login.submit': 'Anmelden',
  'login.failed': 'Benutzername oder Passwort ist falsch.',
  'login.rateLimited': 'Zu viele Versuche. Bitte warte {minutes} Minuten.',
  'login.offline': 'Keine Verbindung zum Server. Für die erste Anmeldung brauchst du Internet.',
  'login.expired': 'Bitte melde dich erneut an.',
  'home.hello': 'Hallo {name}!',
  'home.logout': 'Abmelden',
  'name.edit': 'Namen ändern',
  'name.label': 'Wie sollen wir dich nennen?',
  'name.hint': 'Leer lassen, um deinen Benutzernamen zu verwenden.',
  'name.save': 'Speichern',
  'name.cancel': 'Abbrechen',
  'name.invalid': 'Der Name darf höchstens 64 Zeichen lang sein und keine Steuerzeichen enthalten.',
  'home.noProfiles': 'Dir wurden noch keine Vokabeln freigegeben. Frag deine Eltern.',
  'home.profile': 'Buch',
  'home.units': 'Lektionen',
  'home.allUnits': 'Alle',
  'home.noUnits': 'Keine',
  'home.mode': 'Abfrage',
  'home.mode.typed': 'Eintippen',
  'home.mode.flashcard': 'Karteikarte',
  'home.mode.choice': 'Multiple Choice',
  'home.mode.parent': 'Abfragen lassen',
  'quiz.parentHint':
      'Abfragen lassen: Lies die Vokabel vor. Die Lösung siehst nur du; entscheide dann.',
  'quiz.parentRight': 'Richtig',
  'quiz.parentWrong': 'Falsch',
  'quiz.options': 'Antwortmöglichkeiten',
  'home.direction': 'Richtung',
  'home.direction.mixed': 'Gemischt',
  'home.selection': 'Auswahl',
  'home.selection.mixed': 'Fällige und Fehler',
  'home.selection.due': 'Nur fällige',
  'home.selection.mistakes': 'Nur Fehler',
  'home.selection.all': 'Alles',
  'home.language': 'Sprache',
  'home.start': 'Los geht’s ({count} Karten)',
  'home.nothing': 'Gerade ist nichts zu lernen. Wähle mehr Lektionen oder „Alles“.',
  'progress.new': '{count} neu',
  'progress.due': '{count} fällig',
  'progress.mistakes': '{count} Fehler',
  'progress.boxes': 'Karten in den Fächern 1 bis 5',
  'quiz.of': 'Karte {n} von {total}',
  'quiz.answer': 'Deine Antwort',
  'quiz.check': 'Prüfen',
  'quiz.reveal': 'Aufdecken',
  'quiz.knew': 'Gewusst',
  'quiz.didntKnow': 'Nicht gewusst',
  'quiz.correct': 'Richtig!',
  'quiz.almost': 'Fast richtig – ein Tippfehler?',
  'quiz.wrong': 'Leider falsch.',
  'quiz.solution': 'Lösung',
  'quiz.countAsRight': 'Zählt als richtig',
  'quiz.countAsWrong': 'Zählt als falsch',
  'quiz.next': 'Weiter',
  'quiz.quit': 'Beenden',
  'quiz.again': 'Kommt gleich nochmal.',
  'info.open': 'Mehr Informationen',
  'info.close': 'Schließen',
  'info.notes': 'Hinweise',
  'info.examples': 'Beispiele',
  'info.loanwords': 'Fremdwörter',
  'info.refs': 'Im Buch',
  'summary.title': 'Geschafft!',
  'summary.result': '{firstTry} von {cards} Karten auf Anhieb richtig.',
  'summary.home': 'Zur Übersicht',
  'summary.more': 'Noch eine Runde',
  'admin.link': 'Verwaltung',
  'admin.title': 'Verwaltung',
  'admin.back': 'Zurück',
  'admin.offline': 'Die Verwaltung braucht eine Verbindung zum Server.',
  'admin.loading': 'Lade …',
  'admin.users': 'Konten',
  'admin.new': 'Neues Konto',
  'admin.username': 'Benutzername',
  'admin.password': 'Passwort',
  'admin.passwordHint': 'Mindestens 8 Zeichen.',
  'admin.displayName': 'Name zur Begrüßung',
  'admin.displayNameHint': 'Leer lassen für den Benutzernamen.',
  'admin.role': 'Rolle',
  'admin.role.learner': 'Lernende:r',
  'admin.role.admin': 'Eltern (Verwaltung)',
  'admin.profiles': 'Freigegebene Bücher',
  'admin.allProfiles': 'Eltern sehen alle Bücher.',
  'admin.create': 'Konto anlegen',
  'admin.created': 'Konto {name} angelegt.',
  'admin.save': 'Speichern',
  'admin.saved': 'Gespeichert.',
  'admin.cancel': 'Abbrechen',
  'admin.edit': 'Bearbeiten',
  'admin.newPassword': 'Neues Passwort',
  'admin.resetPassword': 'Passwort setzen',
  'admin.passwordReset': 'Passwort geändert; {name} ist überall abgemeldet.',
  'admin.disable': 'Sperren',
  'admin.enable': 'Entsperren',
  'admin.disabled': 'gesperrt',
  'admin.you': 'du',
  'admin.noProfiles': 'keine Bücher',
  'admin.error.offline': 'Keine Verbindung zum Server.',
  'admin.error.taken': 'Dieser Benutzername ist schon vergeben.',
  'admin.error.username': 'Benutzername: 1 bis 64 Buchstaben, Ziffern, „.“, „_“ oder „-“.',
  'admin.error.password': 'Das Passwort muss mindestens 8 Zeichen haben.',
  'admin.error.name':
      'Der Name darf höchstens 64 Zeichen lang sein und keine Steuerzeichen enthalten.',
  'admin.error.self': 'Du kannst dein eigenes Konto nicht sperren.',
  'admin.error.profiles': 'Ein ausgewähltes Buch gibt es nicht (mehr).',
  'admin.error.forbidden': 'Dafür brauchst du ein Elternkonto.',
  'admin.error.generic': 'Das hat nicht geklappt. Bitte versuche es noch einmal.',
  'test.plan': 'Test planen',
  'test.date': 'Wann ist der Test?',
  'test.unitsFromSelection': 'Lektionen: {units} (die oben ausgewählten)',
  'test.save': 'Test planen',
  'test.cancel': 'Abbrechen',
  'test.change': 'Ändern',
  'test.remove': 'Test entfernen',
  'test.title': 'Test {when}',
  'test.today': 'heute',
  'test.tomorrow': 'morgen',
  'test.inDays': 'in {days} Tagen',
  'test.units': 'Lektionen {units}',
  'test.secure': '{secure} von {cards} Karten sicher',
  'test.secureTitle': 'Sicher: zweimal hintereinander richtig',
  'test.goalToday': 'Heute noch {left} richtige Antworten.',
  'test.doneToday': 'Für heute geschafft ({done} richtige Antworten)!',
  'test.ready': 'Alles sicher – gut vorbereitet!',
  'test.practise': 'Für den Test üben',
  'test.over': 'Der Test am {date} ist vorbei.',
  'test.error.date': 'Bitte wähle heute oder einen Tag in der Zukunft.',
  'test.error.units': 'Wähle oben mindestens eine Lektion aus.',
  'stats.link': 'Statistik',
  'stats.title': 'Statistik',
  'stats.total': '{count} Antworten insgesamt',
  'stats.last': 'zuletzt {when}',
  'stats.daysTitle': 'Die letzten 14 Tage',
  'stats.right': 'Richtig',
  'stats.wrong': 'Falsch',
  'stats.pickDay': 'Tippe auf einen Tag für die Zahlen.',
  'stats.day': '{day}: {right} richtig, {wrong} falsch',
  'stats.table': 'Als Tabelle',
  'stats.dayColumn': 'Tag',
  'stats.unitsTitle': 'Lektionen',
  'stats.secure': '{secure} von {cards} Karten sicher',
  'stats.accuracy': '{percent} % richtig in den letzten 30 Tagen',
  'stats.hardestTitle': 'Diese Wörter waren am schwersten',
  'stats.noMistakes': 'Noch keine Fehler – weiter so!',
  'stats.wrongTimes': '{wrong}× falsch, {right}× richtig',
  'stats.lastRight': 'zuletzt richtig',
  'stats.progress': 'Fortschritt',
  'stats.loading': 'Lade …',
  'sync.running': 'Synchronisiere …',
  'sync.pending': '{count} Antworten noch nicht übertragen',
  'sync.pendingOne': '1 Antwort noch nicht übertragen',
  'sync.last': 'Zuletzt synchronisiert {when}',
  'sync.never': 'Noch nicht synchronisiert',
  'sync.now': 'Jetzt synchronisieren',
  'direction.src_to_tr': '{src} → {tr}',
  'direction.tr_to_src': '{tr} → {src}',
  'server.label': 'Server',
  'server.hint': 'Adresse von Capsa, z. B. https://capsa.example.org',
  'server.invalid': 'Bitte gib die Adresse des Servers an (mit https://).',
};

const _langNames = {
  'la': 'Latein',
  'de': 'Deutsch',
  'fr': 'Französisch',
  'en': 'Englisch',
  'es': 'Spanisch',
  'it': 'Italienisch',
  'el': 'Griechisch',
  'grc': 'Altgriechisch',
};

String t(String key, [Map<String, Object> params = const {}]) {
  final text = _de[key];
  assert(text != null, 'missing UI string $key');
  return (text ?? key).replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (m) => params[m[1]]?.toString() ?? '{${m[1]}}',
  );
}

String langName(String code) => _langNames[code] ?? code;

/// "vor 5 Minuten", "gestern"; under a minute: "gerade eben" (as Intl.RelativeTimeFormat
/// with numeric: 'auto' says it in the PWA).
String relativeTime(int ms, [int? now]) {
  final diff = ms - (now ?? DateTime.now().millisecondsSinceEpoch);
  const units = [
    (86400000, 'Tag', 'Tagen'),
    (3600000, 'Stunde', 'Stunden'),
    (60000, 'Minute', 'Minuten'),
  ];
  const namedDays = {-2: 'vorgestern', -1: 'gestern', 1: 'morgen', 2: 'übermorgen'};
  for (final (size, one, many) in units) {
    if (diff.abs() < size) continue;
    final n = (diff / size).round();
    if (size == 86400000 && namedDays[n] != null) return namedDays[n]!;
    // Dative after "vor" and "in": "vor 3 Tagen", "in 1 Stunde".
    final unit = n.abs() == 1 ? one : many;
    return n < 0 ? 'vor ${-n} $unit' : 'in $n $unit';
  }
  return 'gerade eben';
}

DateTime _noon(String iso) => DateTime.parse('${iso}T12:00:00');

/// "Mittwoch, 20. Januar"
String weekdayDate(String iso) => DateFormat('EEEE, d. MMMM', 'de').format(_noon(iso));

/// "M" (narrow weekday) or "Mi., 20.1."
String dayLabel(String iso, {bool short = false}) =>
    DateFormat(short ? 'EEEEE' : 'EEE, d.M.', 'de').format(_noon(iso));
