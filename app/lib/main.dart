import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'api/client.dart';
import 'app_state.dart';
import 'store/db.dart';
import 'ui/admin_page.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/quiz_page.dart';
import 'ui/stats_view.dart';
import 'ui/summary_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  final app = AppState(
    device: await DeviceStore.open(),
    // On the web the app is served from the API's origin and the browser keeps the
    // session cookie; elsewhere the user names the server and the app keeps the cookie.
    sameOrigin: kIsWeb,
    apiFactory: (baseUrl, cookie, onCookie) => ApiClient(
      baseUrl: kIsWeb ? Uri.base.origin : baseUrl,
      httpClient: http.Client(),
      cookie: cookie,
      onCookie: onCookie,
    ),
  );
  runApp(CapsaApp(app: app));
  unawaited(app.start());
}

class CapsaApp extends StatefulWidget {
  const CapsaApp({super.key, required this.app});

  final AppState app;

  @override
  State<CapsaApp> createState() => _CapsaAppState();
}

class _CapsaAppState extends State<CapsaApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Sync when the app returns to the foreground (SPEC 9; the PWA's visibilitychange).
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (widget.app.me != null) unawaited(widget.app.refresh());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Capsa',
    debugShowCheckedModeBanner: false,
    theme: capsaTheme(Brightness.light),
    darkTheme: capsaTheme(Brightness.dark),
    locale: const Locale('de'),
    supportedLocales: const [Locale('de')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) => _Root(app: widget.app),
    ),
  );
}

class _Root extends StatelessWidget {
  const _Root({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final page = switch (app.view) {
      AppView.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AppView.login => LoginPage(app: app),
      AppView.home => HomePage(app: app),
      AppView.quiz => QuizPage(app: app),
      AppView.summary => SummaryPage(app: app),
      AppView.admin => AdminPage(app: app),
      AppView.stats => StatsPage(app: app),
    };
    // Android's back button: leave a quiz or a sub-page instead of closing the app.
    final back = switch (app.view) {
      AppView.quiz => app.quitSession,
      AppView.summary || AppView.admin || AppView.stats => app.goHome,
      _ => null,
    };
    return PopScope(
      canPop: back == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: KeyedSubtree(key: ValueKey(app.view), child: page),
    );
  }
}
