// The app end to end against the fake server: sign in, learn, offline start.
// Like the PWA's Playwright tests, but as Flutter widget tests.
import 'package:capsa/api/client.dart';
import 'package:capsa/app_state.dart';
import 'package:capsa/learning/cards.dart';
import 'package:capsa/main.dart';
import 'package:capsa/store/db.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sembast/sembast_memory.dart' show newDatabaseFactoryMemory;

import 'fake_server.dart';

class Harness {
  Harness(this.server);

  final FakeServer server;
  final factory = newDatabaseFactoryMemory();
  var now = DateTime.utc(2027, 1, 15, 9).millisecondsSinceEpoch;

  /// A fresh app process on the same device (same databases).
  Future<AppState> launch() async {
    final device = await DeviceStore.open((name) => factory.openDatabase(name));
    return AppState(
      device: device,
      sameOrigin: false,
      opener: (name) => factory.openDatabase(name),
      clock: () => now,
      apiFactory: (baseUrl, cookie, onCookie) => ApiClient(
        baseUrl: baseUrl,
        cookie: cookie,
        onCookie: onCookie,
        httpClient: server.httpClient(),
      ),
    );
  }
}

Future<void> start(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(CapsaApp(app: app));
  await tester.runAsync(app.start);
  await tester.pumpAndSettle();
}

/// Let real async work (the in-memory database, the fake server) finish, then settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Scroll a widget into view, then tap it.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

/// Choose [option] in the overview's dropdown labelled [label].
Future<void> pick(WidgetTester tester, String label, String option) async {
  final menu = find.byWidgetPredicate(
    (w) => w is DropdownMenu && w.label is Text && (w.label! as Text).data == label,
  );
  await tapOn(tester, menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await settle(tester);
}

Future<void> signIn(WidgetTester tester, {String password = 'geheim123'}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Server'), 'capsa.test');
  await tester.enterText(find.widgetWithText(TextField, 'Benutzername'), 'lena');
  await tester.enterText(find.widgetWithText(TextField, 'Passwort'), password);
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await settle(tester);
}

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  testWidgets('wrong password, then sign in and see the overview', (tester) async {
    final h = Harness(FakeServer());
    final app = await h.launch();
    await start(tester, app);
    expect(find.text('Anmelden'), findsWidgets);

    await signIn(tester, password: 'falsch');
    expect(find.text('Benutzername oder Passwort ist falsch.'), findsOneWidget);

    await signIn(tester);
    expect(find.text('Hallo Lena!'), findsOneWidget);
    expect(find.text('Demo: Latein am Meer'), findsOneWidget);
    expect(find.text('1. Am Hafen'), findsOneWidget);
    expect(find.text('Los geht’s (10 Karten)'), findsOneWidget);
    expect(h.server.requests, contains('GET /api/v1/profiles/demo-latin'));
  });

  testWidgets('a typed session: right, wrong, repeated, summary, synced', (tester) async {
    final h = Harness(FakeServer());
    final app = await h.launch();
    await start(tester, app);
    await signIn(tester);

    await tapOn(tester, find.text('Los geht’s (10 Karten)'));
    await settle(tester);
    expect(find.text('Karte 1 von 10'), findsOneWidget);

    // First card right: type its solution.
    final index = app.index!;
    String solutionNow() {
      final card = app.session!.current!;
      return solution(index.entries[card.entryId]!, card.direction, app.lang);
    }

    // Screen readers hear the field by its own name, not the whole card.
    final semantics = tester.ensureSemantics();
    final card = app.session!.current!;
    final shown = prompt(index.entries[card.entryId]!, card.direction, app.lang);
    final field = tester.getSemantics(find.bySemanticsLabel(RegExp('Deine Antwort')));
    expect(field.label, isNot(contains(shown)));
    semantics.dispose();

    await tester.enterText(find.byType(TextField), solutionNow().split(', ').first);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Prüfen'));
    await settle(tester);
    expect(find.text('Richtig!'), findsOneWidget);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Weiter'));
    await settle(tester);
    expect(find.text('Karte 2 von 10'), findsOneWidget);

    // Second card wrong: it comes back, so the session grows by one.
    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('Leider falsch.'), findsOneWidget);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Weiter'));
    await settle(tester);
    expect(find.text('Karte 3 von 11'), findsOneWidget);

    await tapOn(tester, find.text('Beenden'));
    await settle(tester);
    expect(find.text('Geschafft!'), findsOneWidget);
    expect(find.text('1 von 2 Karten auf Anhieb richtig.'), findsOneWidget);

    // The session end synced both answers.
    expect(h.server.events, hasLength(2));
    expect(h.server.events.first['mode'], 'typed');
    expect(app.unsynced, 0);

    await tapOn(tester, find.text('Zur Übersicht'));
    await settle(tester);
    expect(find.textContaining('1 Fehler'), findsOneWidget);
  });

  testWidgets('starts offline from local data after a sign-in', (tester) async {
    final h = Harness(FakeServer());
    final first = await h.launch();
    await start(tester, first);
    await signIn(tester);
    expect(find.text('Hallo Lena!'), findsOneWidget);

    // A new app process, without a network.
    h.server.offline = true;
    final second = await h.launch();
    await start(tester, second);
    await settle(tester);
    expect(find.text('Hallo Lena!'), findsOneWidget);
    expect(find.text('Los geht’s (10 Karten)'), findsOneWidget);
    expect(
      find.text('Offline – dein Fortschritt wird auf diesem Gerät gespeichert.'),
      findsOneWidget,
    );

    // Learning works offline; answers wait on the device.
    await tapOn(tester, find.text('Los geht’s (10 Karten)'));
    await settle(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Prüfen'));
    await settle(tester);
    await tapOn(tester, find.widgetWithText(FilledButton, 'Weiter'));
    await settle(tester);
    expect(second.unsynced, 1);
    expect(h.server.events, isEmpty);

    // Back online: the next sync uploads them.
    h.server.offline = false;
    await tester.runAsync(second.refresh);
    expect(h.server.events, hasLength(1));
    expect(second.online, isTrue);
  });

  testWidgets('flashcards: every card, the last one too, shows its solution first', (tester) async {
    final h = Harness(FakeServer());
    final app = await h.launch();
    await start(tester, app);
    await signIn(tester);
    await pick(tester, 'Abfrage', 'Karteikarte');
    await tapOn(tester, find.text('Los geht’s (10 Karten)'));
    await settle(tester);

    // The first card wasn't known, so it comes back as an eleventh, last card.
    for (var n = 1; n <= 11; n++) {
      expect(find.text('Karte $n von 11'), n == 1 ? findsNothing : findsOneWidget);
      final card = app.session!.current!;
      final right = solution(app.index!.entries[card.entryId]!, card.direction, app.lang);
      await tapOn(tester, find.widgetWithText(FilledButton, 'Aufdecken'));
      await settle(tester);
      expect(find.textContaining('Karte $n von'), findsOneWidget, reason: 'card $n revealed');
      expect(find.text(right), findsOneWidget);
      final button = n == 1
          ? find.widgetWithText(OutlinedButton, 'Nicht gewusst')
          : find.widgetWithText(FilledButton, 'Gewusst');
      await tapOn(tester, button);
      await settle(tester);
    }
    expect(find.text('Geschafft!'), findsOneWidget);
  });

  testWidgets('multiple choice marks the right option', (tester) async {
    final h = Harness(FakeServer());
    final app = await h.launch();
    await start(tester, app);
    await signIn(tester);
    await pick(tester, 'Abfrage', 'Multiple Choice');
    await tapOn(tester, find.text('Los geht’s (10 Karten)'));
    await settle(tester);

    // Number keys pick an option wherever the focus is (as in the PWA).
    final card = app.session!.current!;
    final right = solution(app.index!.entries[card.entryId]!, card.direction, app.lang);
    final options = tester
        .widgetList<Text>(
          find.descendant(of: find.byType(OutlinedButton), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .where((t) => t != null && int.tryParse(t) == null)
        .toList();
    final key = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ][options.indexOf(right)];
    await tester.sendKeyEvent(key);
    await settle(tester);
    expect(find.text('Richtig!'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // The changed mode is the synced setting prefs.<profile>, sent a moment later,
    // in the same JSON shape as the PWA's.
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(h.server.settings['prefs.demo-latin']?.value, {
      'units': null,
      'mode': 'choice',
      'direction': 'src_to_tr',
      'selection': 'mixed',
      'lang': null,
    });
  });
}
