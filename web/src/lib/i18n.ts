/**
 * UI strings. German first; all strings live here so more languages can be added
 * (SPEC 13: UI language). Profile content is never translated.
 */

const de = {
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
  'install.iosHint': 'Tipp: Installiere Capsa, dann funktioniert es auch ohne Internet.',
  'install.iosSteps': 'Tippe dazu in Safari auf „Teilen“ und dann auf „Zum Home-Bildschirm“.',
  'install.iosWarning':
    'Achtung: Capsa ist nicht installiert und war seit über 5 Tagen nicht mehr verbunden. Safari kann dann deinen Fortschritt löschen.',
  'install.promptHint': 'Installiere Capsa, dann funktioniert es auch ohne Internet.',
  'install.button': 'Installieren',
  'install.later': 'Später',
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
  'admin.error.name': 'Der Name darf höchstens 64 Zeichen lang sein und keine Steuerzeichen enthalten.',
  'admin.error.self': 'Du kannst dein eigenes Konto nicht sperren.',
  'admin.error.profiles': 'Ein ausgewähltes Buch gibt es nicht (mehr).',
  'admin.error.forbidden': 'Dafür brauchst du ein Elternkonto.',
  'admin.error.generic': 'Das hat nicht geklappt. Bitte versuche es noch einmal.',
  'update.available': 'Eine neue Version von Capsa ist da.',
  'update.apply': 'Aktualisieren',
  'sync.running': 'Synchronisiere …',
  'sync.pending': '{count} Antworten noch nicht übertragen',
  'sync.pendingOne': '1 Antwort noch nicht übertragen',
  'sync.last': 'Zuletzt synchronisiert {when}',
  'sync.never': 'Noch nicht synchronisiert',
  'sync.now': 'Jetzt synchronisieren',
  'direction.src_to_tr': '{src} → {tr}',
  'direction.tr_to_src': '{tr} → {src}',
} as const;

export type MessageKey = keyof typeof de;

const LANG_NAMES: Record<string, string> = {
  la: 'Latein',
  de: 'Deutsch',
  fr: 'Französisch',
  en: 'Englisch',
  es: 'Spanisch',
  it: 'Italienisch',
  el: 'Griechisch',
  grc: 'Altgriechisch',
};

export function t(key: MessageKey, params: Record<string, string | number> = {}): string {
  return de[key].replace(/\{(\w+)\}/g, (_, name: string) => String(params[name] ?? `{${name}}`));
}

export function langName(code: string): string {
  return LANG_NAMES[code] ?? code;
}

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ['day', 86_400_000],
  ['hour', 3_600_000],
  ['minute', 60_000],
];

/** "vor 5 Minuten", "gestern"; under a minute: "gerade eben". */
export function relativeTime(ms: number, now: number = Date.now()): string {
  const diff = ms - now;
  const format = new Intl.RelativeTimeFormat('de', { numeric: 'auto' });
  for (const [unit, size] of UNITS) {
    if (Math.abs(diff) >= size) return format.format(Math.round(diff / size), unit);
  }
  return 'gerade eben';
}
