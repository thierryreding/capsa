import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../learning/session.dart' show Progress;
import '../learning/stats.dart';
import 'common.dart';
import 'theme.dart';

/// The learner's own statistics, computed on the device so they work offline.
class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final index = app.index;
    return CapsaPage(
      app: app,
      title: Text(t('stats.title')),
      leading: BackButton(onPressed: app.goHome),
      children: [
        if (index != null)
          CapsaCard(
            children: [
              Text(index.doc.profile.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              StatsView(
                stats: learningStats(index.doc, app.events, app.now(), app.config),
                now: app.now(),
              ),
            ],
          ),
      ],
    );
  }
}

/// Learning statistics (F9), from the device (learner) or the server (parents).
class StatsView extends StatefulWidget {
  const StatsView({super.key, required this.stats, required this.now});

  final LearningStats stats;
  final int now;

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  int? _focused;

  String _describe(DayCount d) =>
      t('stats.day', {'day': dayLabel(d.date), 'right': d.correct, 'wrong': d.wrong});

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    final colors = CapsaColors.of(context);
    final text = Theme.of(context).textTheme;
    final max = s.days.fold(1, (m, d) => d.correct + d.wrong > m ? d.correct + d.wrong : m);
    Widget heading(String key) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(t(key), style: text.titleMedium),
    );
    Widget swatch(Color c, String key) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: c),
        const SizedBox(width: 4),
        Text(t(key)),
        const SizedBox(width: 16),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hint(
          [
            t('stats.total', {'count': s.totalAnswers}),
            if (s.lastAnswerAt != null)
              t('stats.last', {'when': relativeTime(s.lastAnswerAt!, widget.now)}),
          ].join(' · '),
        ),
        heading('stats.daysTitle'),
        ExcludeSemantics(
          child: Row(
            children: [swatch(colors.right, 'stats.right'), swatch(colors.wrong, 'stats.wrong')],
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          liveRegion: true,
          child: Hint(_focused == null ? t('stats.pickDay') : _describe(s.days[_focused!])),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < s.days.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    label: _describe(s.days[i]),
                    child: InkWell(
                      onTap: () => setState(() => _focused = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        color: _focused == i ? colors.border.withValues(alpha: 0.5) : null,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _Stack(day: s.days[i], max: max, height: 116),
                            const SizedBox(height: 4),
                            ExcludeSemantics(
                              child: Text(
                                dayLabel(s.days[i].date, short: true),
                                style: TextStyle(fontSize: 11, color: colors.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t('stats.table')),
          children: [
            Table(
              children: [
                TableRow(
                  children: [
                    for (final k in ['stats.dayColumn', 'stats.right', 'stats.wrong'])
                      Text(t(k), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                for (final d in s.days)
                  TableRow(
                    children: [Text(dayLabel(d.date)), Text('${d.correct}'), Text('${d.wrong}')],
                  ),
              ],
            ),
          ],
        ),
        heading('stats.unitsTitle'),
        for (final u in s.units)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${u.number}. ${u.title}'),
                UnitProgress(
                  Progress(
                    total: u.cards,
                    fresh: u.fresh,
                    due: 0,
                    mistakes: u.mistakes,
                    boxes: u.boxes,
                  ),
                ),
                Hint(
                  [
                    t('stats.secure', {'secure': u.secure, 'cards': u.cards}),
                    if (u.answersRecent > 0)
                      t('stats.accuracy', {
                        'percent': (100 * u.correctRecent / u.answersRecent).round(),
                      }),
                  ].join(' · '),
                ),
              ],
            ),
          ),
        heading('stats.hardestTitle'),
        if (s.hardest.isEmpty)
          Hint(t('stats.noMistakes'))
        else
          for (final (i, w) in s.hardest.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 28, child: Text('${i + 1}.')),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: w.lemma,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: ' – ${w.meaning}'),
                            ],
                          ),
                        ),
                        Hint(
                          [
                            t('stats.wrongTimes', {'wrong': w.wrong, 'right': w.correct}),
                            if (w.lastCorrect) t('stats.lastRight'),
                          ].join(' · '),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// One day's bar: wrong answers on top of right ones.
class _Stack extends StatelessWidget {
  const _Stack({required this.day, required this.max, required this.height});

  final DayCount day;
  final int max;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = CapsaColors.of(context);
    final total = day.correct + day.wrong;
    final h = height * total / max;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      child: SizedBox(
        height: h < 1 && total > 0 ? 1 : h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (day.wrong > 0)
              Expanded(
                flex: day.wrong,
                child: ColoredBox(color: colors.wrong),
              ),
            if (day.correct > 0)
              Expanded(
                flex: day.correct,
                child: ColoredBox(color: colors.right),
              ),
          ],
        ),
      ),
    );
  }
}
