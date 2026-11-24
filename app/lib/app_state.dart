/// Application state and actions. A port of web/src/lib/app.svelte.ts.
///
/// Offline-first: the app starts from the last signed-in account and local data, and
/// talks to the server in the background.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'learning/cards.dart';
import 'learning/leitner.dart';
import 'learning/match.dart';
import 'learning/plan.dart';
import 'learning/session.dart';
import 'store/db.dart';
import 'store/sync.dart';

/// Setting key of the display name (validated by the server).
const displayNameKey = 'display_name';

enum AppView { loading, login, home, quiz, summary, admin, stats }

enum SessionKind { normal, test }

/// The learner's choices in the overview; the synced setting `prefs.<profile id>`.
class Prefs {
  const Prefs({
    this.units,
    this.mode = Mode.typed,
    this.direction = Direction.srcToTr,
    this.selection = Selection.mixed,
    this.lang,
  });

  factory Prefs.fromJson(Object? j) {
    if (j is! Map) return const Prefs();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.where((v) => v.name == name).firstOrNull ?? fallback;
    final direction = j['direction'];
    return Prefs(
      units: (j['units'] as List?)?.cast<String>(),
      mode: pick(Mode.values, j['mode'], Mode.typed),
      direction: direction == 'mixed'
          ? null
          : Direction.values.where((d) => d.wire == direction).firstOrNull ?? Direction.srcToTr,
      selection: pick(Selection.values, j['selection'], Selection.mixed),
      lang: j['lang'] as String?,
    );
  }

  /// null: all units.
  final List<String>? units;
  final Mode mode;

  /// null: mixed, both directions.
  final Direction? direction;
  final Selection selection;

  /// null: the profile's required translation language.
  final String? lang;

  static const _keep = Object();

  Prefs copyWith({
    Object? units = _keep,
    Mode? mode,
    Object? direction = _keep,
    Selection? selection,
    Object? lang = _keep,
  }) => Prefs(
    units: identical(units, _keep) ? this.units : units as List<String>?,
    mode: mode ?? this.mode,
    direction: identical(direction, _keep) ? this.direction : direction as Direction?,
    selection: selection ?? this.selection,
    lang: identical(lang, _keep) ? this.lang : lang as String?,
  );

  /// The same JSON as the PWA writes, so both clients share the setting.
  Map<String, Object?> toJson() => {
    'units': units,
    'mode': mode.name,
    'direction': direction?.wire ?? 'mixed',
    'selection': selection.name,
    'lang': lang,
  };
}

typedef ApiFactory = ApiClient Function(
  String baseUrl,
  String? cookie,
  void Function(String?) onCookie,
);

class AppState extends ChangeNotifier {
  AppState({
    required this._device,
    required this._apiFactory,
    required this.sameOrigin,
    this._opener,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final DeviceStore _device;
  final ApiFactory _apiFactory;
  final DatabaseOpener? _opener;
  final int Function() _clock;

  /// Web: the app is served with the API, so there is no server address to ask for.
  final bool sameOrigin;

  ApiClient? _api;
  ApiClient get api => _api!;

  /// The server address used last (native only).
  String? serverUrl;

  AppView view = AppView.loading;
  Me? me;
  bool online = true;
  String? notice;

  List<StoredProfile> profiles = [];
  String? profileId;
  Prefs prefs = const Prefs();
  Map<String, CardState> states = {};

  /// Answer events of the selected profile (for today's progress towards a test).
  List<AnswerEvent> events = [];

  /// The test planned for the selected profile, if any (synced setting `test.<profile>`).
  TestPlan? testPlan;

  /// Kind of the running or last session, so "one more round" continues it.
  SessionKind sessionKind = SessionKind.normal;
  Session? session;

  bool syncing = false;
  int? lastSyncAt;
  int unsynced = 0;

  UserStore? _store;
  bool _answering = false;
  String _deviceId = '';
  Map<String, Prefs> _allPrefs = {};
  Map<String, TestPlan?> _allPlans = {};
  Future<void>? _refreshing;
  Timer? _prefsTimer;
  ProfileIndex? _index;

  int now() => _clock();

  LeitnerConfig get config => LeitnerConfig.local(DateTime.fromMillisecondsSinceEpoch(now()));

  ProfileIndex? get index {
    final p = profiles.where((x) => x.id == profileId).firstOrNull;
    if (p == null) return _index = null;
    if (_index?.doc != p.doc) _index = ProfileIndex(p.doc);
    return _index;
  }

  String get lang => prefs.lang ?? index?.doc.profile.requiredTranslationLang ?? 'de';

  /// Units to learn: the chosen ones, or all.
  Set<String> get units =>
      (prefs.units ?? index?.doc.units.map((u) => u.id).toList() ?? const []).toSet();

  List<Direction> get directions => prefs.direction == null ? Direction.values : [prefs.direction!];

  void _update() => notifyListeners();

  ApiClient _makeApi(String baseUrl, String? cookie) => _apiFactory(baseUrl, cookie, (c) {
    // Outside the browser the session cookie is ours to keep.
    if (!sameOrigin) unawaited(_device.setCookie(c));
  });

  Future<void> start() async {
    _deviceId = await _device.deviceId();
    serverUrl = await _device.serverUrl();
    if (sameOrigin || serverUrl != null) {
      _api = _makeApi(sameOrigin ? '' : serverUrl!, sameOrigin ? null : await _device.cookie());
    }
    final known = await _device.lastUser();
    if (known == null || _api == null) {
      view = AppView.login;
      _update();
      return;
    }
    await _enter(known);
    view = AppView.home; // from local data at once; the server is asked in the background
    _update();
    unawaited(_checkSession());
  }

  /// Sign in. Returns null on success, otherwise 'failed', 'offline' or `rateLimited:<minutes>`.
  Future<String?> login(String username, String password, {String? server}) async {
    if (!sameOrigin) {
      if (server == null) return 'failed';
      if (server != serverUrl || _api == null) {
        serverUrl = server;
        _api = _makeApi(server, null);
      }
    } else {
      _api ??= _makeApi('', null);
    }
    try {
      final me = await api.login(username, password);
      if (!sameOrigin) await _device.setServerUrl(serverUrl!);
      online = true;
      notice = null;
      await _device.setLastUser(me);
      await _enter(me);
      await refresh(); // first sign-in: show home once the profiles are loaded
      view = AppView.home;
      _update();
      return null;
    } on ApiException catch (e) {
      if (e.status == 429) return 'rateLimited:${((e.retryAfterSeconds ?? 60) / 60).ceil()}';
      return e.offline ? 'offline' : 'failed';
    }
  }

  /// Change the own display name: a synced setting, so it also works offline.
  Future<void> setDisplayName(String? name) async {
    final store = _store, current = me;
    if (store == null || current == null) return;
    await setSetting(store, displayNameKey, name, now());
    me = current.withDisplayName(name);
    await _device.setLastUser(me); // so the name also shows on an offline start
    _update();
    unawaited(refresh());
  }

  /// Take account settings (the display name) from the merged local settings.
  Future<void> _applyAccountSettings(UserStore store) async {
    final setting = (await localSettings(store))[displayNameKey];
    final current = me;
    if (setting == null || current == null) return;
    final name = setting.value as String?;
    if (name == current.displayName) return;
    me = current.withDisplayName(name);
    await _device.setLastUser(me);
  }

  Future<void> logout() async {
    // Upload pending answers first; otherwise they would wait on this device until
    // the same account signs in here again.
    await refresh();
    try {
      await api.logout();
    } on ApiException {
      // offline: the session expires on its own
    }
    await _device.setLastUser(null);
    await _device.setCookie(null);
    await _store?.close();
    _store = null;
    me = null;
    profiles = [];
    profileId = null;
    view = AppView.login;
    _update();
  }

  /// Talk to the server: profile updates, then events and settings (SPEC 6, 9).
  /// Keeps working with local data when offline. Only one refresh runs at a time.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final store = _store;
    if (store == null) return;
    syncing = true;
    _update();
    try {
      await refreshProfiles(api, store, now());
      await syncAll(api, store, now());
      online = true;
    } on ApiException catch (e) {
      online = false;
      if (e.status == 401) await _expired();
    } finally {
      syncing = false;
    }
    if (_store != store) return _update(); // signed out meanwhile
    _allPrefs = await _loadPrefs(store);
    _allPlans = await _loadPlans(store);
    await _applyAccountSettings(store);
    await _loadProfiles();
    await _loadSyncStatus(store);
    _update();
  }

  Future<void> selectProfile(String id) async {
    profileId = id;
    prefs = _allPrefs[id] ?? const Prefs();
    testPlan = _allPlans[id];
    final store = _store;
    if (store != null) await store.setMeta('profile', id);
    events = store == null ? [] : await store.eventsForProfile(id);
    states = computeStates(events, config);
    _update();
  }

  /// Change learning choices; they are synced as the setting `prefs.<profile>`.
  Future<void> setPrefs(Prefs next) async {
    prefs = next;
    _update();
    final id = profileId, store = _store;
    if (id == null || store == null) return;
    _allPrefs[id] = next;
    await setSetting(store, 'prefs.$id', next.toJson(), now());
    _syncSoon();
  }

  /// Plan a test (or remove it with null); a synced setting per profile.
  Future<void> setTestPlan(TestPlan? plan) async {
    testPlan = plan;
    _update();
    final id = profileId, store = _store;
    if (id == null || store == null) return;
    _allPlans[id] = plan;
    await setSetting(store, 'test.$id', plan?.toJson(), now());
    _syncSoon();
  }

  /// Several quick changes, one sync.
  void _syncSoon() {
    _prefsTimer?.cancel();
    _prefsTimer = Timer(const Duration(seconds: 2), () => unawaited(refresh()));
  }

  /// Entries that can be asked in the current translation language.
  List<EntryRef> askableEntries() {
    final i = index;
    if (i == null) return [];
    return [
      for (final r in i.refs)
        if (askable(i.entries[r.id]!, lang)) r,
    ];
  }

  /// The cards a session would get now; 'test' practises the planned test's units.
  List<Card> plannedCards([SessionKind kind = SessionKind.normal]) {
    final i = index, plan = testPlan;
    if (i == null || (kind == SessionKind.test && plan == null)) return [];
    return selectCards(
      states,
      profileId: i.doc.profile.id,
      entries: askableEntries(),
      units: kind == SessionKind.test ? plan!.units.toSet() : units,
      directions: directions,
      selection: kind == SessionKind.test ? Selection.test : prefs.selection,
      now: now(),
      config: config,
    );
  }

  void beginSession([SessionKind kind = SessionKind.normal]) {
    final cards = plannedCards(kind);
    if (cards.isEmpty) return;
    sessionKind = kind;
    session = Session.start(cards);
    view = AppView.quiz;
    _update();
  }

  /// Store the answer as an event, update the box, advance the session.
  /// Ignored while the previous answer is still being stored (e.g. a double tap).
  Future<void> answer(bool correct, int? responseMs) async {
    final s = session, card = s?.current, store = _store, id = profileId;
    if (s == null || card == null || store == null || id == null || _answering) return;
    _answering = true;
    try {
      final event = await store.recordAnswer(
        Answer(
          profileId: id,
          entryId: card.entryId,
          direction: card.direction,
          mode: prefs.mode,
          correct: correct,
          responseMs: responseMs,
        ),
        _deviceId,
        now(),
      );
      final key = cardKey(id, card.entryId, card.direction);
      states = {...states, key: applyAnswer(states[key], correct, event.ts, config)};
      events = [...events, event];
      unsynced++;
      session = s.answer(correct);
      if (session!.isFinished) {
        view = AppView.summary;
        unawaited(refresh());
      }
      _update();
    } finally {
      _answering = false;
    }
  }

  void quitSession() {
    final answered = session != null && session!.results.isNotEmpty;
    view = answered ? AppView.summary : AppView.home;
    if (answered) unawaited(refresh());
    _update();
  }

  void openStats() {
    if (index == null) return;
    view = AppView.stats;
    _update();
  }

  void openAdmin() {
    if (me?.isAdmin != true) return;
    view = AppView.admin;
    _update();
  }

  void goHome() {
    session = null;
    view = AppView.home;
    _update();
  }

  Future<void> _enter(Me account) async {
    me = account;
    await _store?.close();
    final store = _opener == null
        ? await UserStore.open(account.id)
        : await UserStore.open(account.id, _opener);
    _store = store;
    await _applyAccountSettings(store);
    _allPrefs = await _loadPrefs(store);
    _allPlans = await _loadPlans(store);
    await _loadProfiles();
    await _loadSyncStatus(store);
  }

  Future<Map<String, TestPlan?>> _loadPlans(UserStore store) async => {
    for (final e in (await localSettings(store)).entries)
      if (e.key.startsWith('test.')) e.key.substring(5): TestPlan.fromJson(e.value.value),
  };

  Future<Map<String, Prefs>> _loadPrefs(UserStore store) async => {
    for (final e in (await localSettings(store)).entries)
      if (e.key.startsWith('prefs.')) e.key.substring(6): Prefs.fromJson(e.value.value),
  };

  Future<void> _loadSyncStatus(UserStore store) async {
    unsynced = await store.unsyncedCount();
    lastSyncAt = await lastSync(store);
  }

  Future<void> _expired() async {
    notice = 'expired';
    await _device.setLastUser(null);
    await _device.setCookie(null);
    view = AppView.login;
  }

  Future<void> _loadProfiles() async {
    final store = _store;
    if (store == null) return;
    profiles = await store.localProfiles();
    final wanted = profileId ?? await store.getMeta<String>('profile');
    final id = profiles.where((p) => p.id == wanted).firstOrNull?.id ?? profiles.firstOrNull?.id;
    if (id != null) {
      await selectProfile(id);
    } else {
      profileId = null;
    }
  }

  /// Background check: is the session still valid? Then refresh profiles.
  Future<void> _checkSession() async {
    try {
      final fresh = await api.me();
      me = fresh;
      await _device.setLastUser(fresh);
      await refresh();
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _expired();
      } else {
        online = false;
      }
      _update();
    }
  }

  @override
  void dispose() {
    _prefsTimer?.cancel();
    super.dispose();
  }
}
