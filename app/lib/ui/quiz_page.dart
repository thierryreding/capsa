import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../learning/cards.dart';
import '../learning/choice.dart';
import '../learning/match.dart';
import '../learning/profile.dart';
import '../store/db.dart';
import 'common.dart';
import 'theme.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.app});

  final AppState app;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final _typed = TextEditingController();
  final _inputFocus = FocusNode();
  final _nextFocus = FocusNode();
  bool _infoOpen = false;

  Verdict? _verdict;
  bool _revealed = false;
  int _shownAt = 0;
  int? _responseMs;
  List<Choice> _options = [];
  int? _chosen;

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    // Like the PWA's window keydown listener: works wherever the focus is.
    HardwareKeyboard.instance.addHandler(_onKey);
    _resetCard();
  }

  @override
  void dispose() {
    _typed.dispose();
    _inputFocus.dispose();
    _nextFocus.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Fresh state for the card on top of the queue: when the quiz opens and right after
  /// an answer has been stored, i.e. exactly when the card changes.
  void _resetCard() {
    _typed.clear();
    _verdict = null;
    _shownAt = app.now();
    _responseMs = null;
    _chosen = null;
    // Parent mode: the parent sees the solution at once and judges the spoken answer.
    _revealed = app.prefs.mode == Mode.parent;
    // Options are drawn once per card, so they stay put while answering.
    final index = app.index, card = app.session?.current;
    _options = app.prefs.mode == Mode.choice && index != null && card != null
        ? choicesFor(index, card.entryId, card.direction, app.lang)
        : [];
    if (app.prefs.mode == Mode.typed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
  }

  void _focusNext() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _nextFocus.requestFocus();
  });

  void _check(Entry entry, ProfileDocument doc) {
    final card = app.session?.current;
    if (card == null || _verdict != null) return;
    setState(() {
      _responseMs = app.now() - _shownAt;
      _verdict = checkAnswer(
        MatchEntry.of(entry),
        _typed.text,
        matchContext(doc, card.direction, app.lang),
      ).verdict;
    });
    if (_verdict != Verdict.almost) _focusNext();
  }

  void _choose(int i) {
    if (_chosen != null || i >= _options.length) return;
    setState(() {
      _responseMs = app.now() - _shownAt;
      _chosen = i;
      _verdict = _options[i].correct ? Verdict.correct : Verdict.wrong;
    });
    _focusNext();
  }

  void _reveal() => setState(() {
    _responseMs = app.now() - _shownAt;
    _revealed = true;
  });

  Future<void> _done(bool correct) async {
    _responseMs ??= app.now() - _shownAt;
    final before = app.session;
    await app.answer(correct, _responseMs);
    // Only if the answer was taken (a double tap is ignored) and the quiz goes on.
    if (mounted && app.session != before && app.session?.isFinished == false) {
      setState(_resetCard);
    }
  }

  /// Number keys 1-4 pick an option (hardware keyboards, the web).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || app.prefs.mode != Mode.choice || _chosen != null || _infoOpen) {
      return false;
    }
    final n = int.tryParse(event.character ?? '');
    if (n == null || n < 1 || n > _options.length) return false;
    _choose(n - 1);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final session = app.session, card = session?.current, index = app.index;
    final entry = card == null ? null : index?.entries[card.entryId];
    if (session == null || card == null || entry == null || index == null) {
      return const Scaffold();
    }
    final doc = index.doc;
    final colors = CapsaColors.of(context);
    final text = Theme.of(context).textTheme;
    final position = session.results.length + 1;
    final total = session.results.length + session.queue.length;
    final repeated = session.results.any((r) => r.card == card);
    final mode = app.prefs.mode;
    final answered = _verdict != null || _revealed;
    final shownLang = card.direction == Direction.srcToTr ? doc.profile.sourceLang : app.lang;
    final typedLang = card.direction == Direction.srcToTr ? app.lang : doc.profile.sourceLang;

    final word = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: prompt(entry, card.direction, app.lang),
                  locale: Locale(shownLang),
                  style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (card.direction == Direction.srcToTr && entry.info != null && answered)
                  TextSpan(
                    text: '  ${entry.info}',
                    style: TextStyle(color: colors.muted),
                  ),
              ],
            ),
          ),
        ),
        if (hasExtras(entry) || entry.info != null)
          IconButton.outlined(
            tooltip: t('info.open'),
            onPressed: () => _showInfo(context, entry, doc.profile.sourceLang),
            icon: const Icon(Icons.info_outline),
          ),
      ],
    );

    final List<Widget> answer = switch (mode) {
      Mode.typed => [
        TextField(
          controller: _typed,
          focusNode: _inputFocus,
          readOnly: _verdict != null,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          decoration: InputDecoration(hintText: t('quiz.answer'), labelText: t('quiz.answer')),
          style: TextStyle(fontSize: 20, locale: Locale(typedLang)),
          onSubmitted: (_) => _check(entry, doc),
        ),
        if (_verdict == null) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _check(entry, doc), child: Text(t('quiz.check'))),
        ],
      ],
      Mode.choice => [
        Semantics(
          label: t('quiz.options'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OptionButton(
                    number: i + 1,
                    text: _options[i].text,
                    locale: Locale(typedLang),
                    state: _chosen == null
                        ? null
                        : _options[i].correct
                        ? true
                        : (_chosen == i ? false : null),
                    onPressed: _chosen == null ? () => _choose(i) : null,
                  ),
                ),
            ],
          ),
        ),
      ],
      _ when !_revealed => [FilledButton(onPressed: _reveal, child: Text(t('quiz.reveal')))],
      _ => [],
    };

    Widget? result;
    if (answered) {
      final (bg, fg) = switch (_verdict) {
        Verdict.correct => (colors.okBg, colors.ok),
        Verdict.almost => (colors.almostBg, colors.almost),
        Verdict.wrong => (colors.badBg, colors.bad),
        null => (Theme.of(context).colorScheme.surfaceContainerHighest, null),
      };
      result = Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_verdict != null)
                Text(
                  t(switch (_verdict!) {
                    Verdict.correct => 'quiz.correct',
                    Verdict.almost => 'quiz.almost',
                    Verdict.wrong => 'quiz.wrong',
                  }),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                ),
              // In multiple choice the right option is already marked.
              if (mode != Mode.choice)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: solution(entry, card.direction, app.lang),
                        locale: Locale(typedLang),
                        style: text.titleLarge,
                      ),
                      if (card.direction == Direction.trToSrc && entry.info != null)
                        TextSpan(
                          text: '  ${entry.info}',
                          style: TextStyle(color: colors.muted),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final List<Widget> actions = switch (_verdict) {
      Verdict.almost => [
        FilledButton(onPressed: () => _done(true), child: Text(t('quiz.countAsRight'))),
        OutlinedButton(onPressed: () => _done(false), child: Text(t('quiz.countAsWrong'))),
      ],
      final Verdict v => [
        FilledButton(
          focusNode: _nextFocus,
          onPressed: () => _done(v == Verdict.correct),
          child: Text(t('quiz.next')),
        ),
      ],
      null when !_revealed => [],
      null when mode == Mode.parent => [
        FilledButton(onPressed: () => _done(true), child: Text(t('quiz.parentRight'))),
        OutlinedButton(onPressed: () => _done(false), child: Text(t('quiz.parentWrong'))),
      ],
      null => [
        FilledButton(onPressed: () => _done(true), child: Text(t('quiz.knew'))),
        OutlinedButton(onPressed: () => _done(false), child: Text(t('quiz.didntKnow'))),
      ],
    };

    return CapsaPage(
      app: app,
      title: Text(t('quiz.of', {'n': position, 'total': total})),
      actions: [TextButton(onPressed: app.quitSession, child: Text(t('quiz.quit')))],
      children: [
        LinearProgressIndicator(value: session.results.length / total),
        const SizedBox(height: 12),
        CapsaCard(
          children: [
            word,
            if (repeated) Hint(t('quiz.again')),
            if (mode == Mode.parent) Hint(t('quiz.parentHint')),
            const SizedBox(height: 16),
            ...answer,
            if (result != null) ...[const SizedBox(height: 12), result],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _showInfo(BuildContext context, Entry entry, String sourceLang) async {
    _infoOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => InfoSheet(entry: entry, sourceLang: sourceLang),
    );
    _infoOpen = false;
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.number,
    required this.text,
    required this.locale,
    required this.state,
    required this.onPressed,
  });

  final int number;
  final String text;
  final Locale locale;

  /// null: not marked; true: the right option; false: chosen and wrong.
  final bool? state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = CapsaColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, border) = switch (state) {
      true => (colors.okBg, colors.ok, colors.ok),
      false => (colors.badBg, colors.bad, colors.bad),
      null => (scheme.surfaceContainerLow, scheme.onSurface, colors.border),
    };
    return OutlinedButton(
      onPressed: onPressed ?? () {},
      style: OutlinedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        side: BorderSide(color: border, width: state == null ? 1 : 2),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('$number', style: TextStyle(color: colors.muted, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, locale: locale, style: const TextStyle(fontSize: 17)),
          ),
          if (state == true) Icon(Icons.check, color: fg),
          if (state == false) Icon(Icons.close, color: fg),
        ],
      ),
    );
  }
}

/// Extra information behind the info icon (F2).
class InfoSheet extends StatelessWidget {
  const InfoSheet({super.key, required this.entry, required this.sourceLang});

  final Entry entry;
  final String sourceLang;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = CapsaColors.of(context).muted;
    Widget heading(String key) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(t(key), style: text.titleSmall),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: entry.lemma, style: text.headlineSmall),
                  if (entry.info != null)
                    TextSpan(
                      text: '  ${entry.info}',
                      style: TextStyle(color: muted),
                    ),
                ],
              ),
            ),
            if (entry.notes.isNotEmpty) ...[
              heading('info.notes'),
              for (final note in entry.notes)
                _Bullet(
                  Text.rich(
                    TextSpan(
                      children: [
                        if (note.marker != null)
                          TextSpan(
                            text: '${note.marker} ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        TextSpan(text: note.text),
                        if (note.refs.isNotEmpty)
                          TextSpan(
                            text: ' (${note.refs.join(', ')})',
                            style: TextStyle(color: muted),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
            if (entry.examples.isNotEmpty) ...[
              heading('info.examples'),
              for (final example in entry.examples)
                _Bullet(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        example[sourceLang] ?? '',
                        style: const TextStyle(fontStyle: FontStyle.italic),
                      ),
                      for (final MapEntry(:key, :value) in example.entries)
                        if (key != sourceLang) Text(value, style: TextStyle(color: muted)),
                    ],
                  ),
                ),
            ],
            if (entry.loanwords.isNotEmpty) ...[
              heading('info.loanwords'),
              for (final MapEntry(:key, :value) in entry.loanwords.entries)
                _Bullet(Text('${langName(key)}: ${value.join(', ')}')),
            ],
            if (entry.refs.isNotEmpty) ...[heading('info.refs'), Text(entry.refs.join(', '))],
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: child),
      ],
    ),
  );
}
