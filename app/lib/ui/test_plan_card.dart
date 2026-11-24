import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../learning/plan.dart';
import 'common.dart';
import 'theme.dart';

/// Planning towards a test date (F8): set it, see progress and today's goal.
class TestPlanCard extends StatelessWidget {
  const TestPlanCard({super.key, required this.app});

  final AppState app;

  String _unitNames(Iterable<String> ids) {
    final wanted = ids.toSet();
    return [
      for (final u in app.index?.doc.units ?? const [])
        if (wanted.contains(u.id)) u.number,
    ].join(', ');
  }

  String _when(int days) => switch (days) {
    0 => t('test.today'),
    1 => t('test.tomorrow'),
    _ => t('test.inDays', {'days': days}),
  };

  Future<void> _edit(BuildContext context) async {
    final config = app.config;
    final today = localDate(app.now(), config.utcOffsetMinutes);
    final messenger = ScaffoldMessenger.of(context);
    if (app.units.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(t('test.error.units'))));
      return;
    }
    final first = DateTime.parse(today);
    final current = app.testPlan?.date;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('de'),
      helpText:
          '${t('test.date')}\n${t('test.unitsFromSelection', {'units': _unitNames(app.units)})}',
      confirmText: t('test.save'),
      cancelText: t('test.cancel'),
      firstDate: first,
      lastDate: first.add(const Duration(days: 366)),
      initialDate: current != null && current.compareTo(today) >= 0
          ? DateTime.parse(current)
          : first,
    );
    if (picked == null) return;
    final date = picked.toIso8601String().substring(0, 10);
    await app.setTestPlan(TestPlan(date: date, units: app.units.toList()));
  }

  @override
  Widget build(BuildContext context) {
    final plan = app.testPlan;
    final doc = app.index?.doc;
    if (plan == null || doc == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.event),
            label: Text(t('test.plan')),
          ),
        ),
      );
    }
    final status = planStatus(
      plan,
      profileId: doc.profile.id,
      entries: app.askableEntries(),
      directions: app.directions,
      states: app.states,
      events: app.events,
      now: app.now(),
      config: app.config,
    );
    final colors = CapsaColors.of(context);
    final remove = TextButton(
      onPressed: () => app.setTestPlan(null),
      child: Text(t('test.remove')),
    );

    if (status.daysLeft < 0) {
      return CapsaCard(
        children: [
          Text(t('test.over', {'date': weekdayDate(plan.date)})),
          Align(alignment: Alignment.centerLeft, child: remove),
        ],
      );
    }
    final ok = TextStyle(color: colors.ok, fontWeight: FontWeight.w600);
    return CapsaCard(
      children: [
        Text(
          t('test.title', {'when': _when(status.daysLeft)}),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Hint('${weekdayDate(plan.date)} · ${t('test.units', {'units': _unitNames(plan.units)})}'),
        const SizedBox(height: 8),
        Tooltip(
          message: t('test.secureTitle'),
          child: SegmentBar([
            (status.secure, colors.boxes.last),
            (status.cards - status.secure, colors.fresh),
          ]),
        ),
        const SizedBox(height: 2),
        Hint(t('test.secure', {'secure': status.secure, 'cards': status.cards})),
        const SizedBox(height: 8),
        if (status.needed == 0)
          Text(t('test.ready'), style: ok)
        else if (status.doneToday >= status.goalToday)
          Text(t('test.doneToday', {'done': status.doneToday}), style: ok)
        else
          Text(t('test.goalToday', {'left': status.goalToday - status.doneToday})),
        if (status.needed > 0) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => app.beginSession(SessionKind.test),
            child: Text(t('test.practise')),
          ),
        ],
        Row(
          children: [
            TextButton(onPressed: () => _edit(context), child: Text(t('test.change'))),
            remove,
          ],
        ),
      ],
    );
  }
}
