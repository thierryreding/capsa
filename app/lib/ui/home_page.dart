import 'package:material_ui/material_ui.dart';

import '../account.dart';
import '../app_state.dart';
import '../i18n.dart';
import '../learning/match.dart';
import '../learning/session.dart';
import '../store/db.dart';
import 'common.dart';
import 'test_plan_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final doc = app.index?.doc;
    final me = app.me;
    return CapsaPage(
      app: app,
      title: InkWell(
        onTap: () => _editName(context),
        child: Tooltip(
          message: t('name.edit'),
          child: Text(t('home.hello', {'name': me == null ? '' : greetingName(me)})),
        ),
      ),
      actions: [
        if (me?.isAdmin == true)
          IconButton(
            onPressed: app.openAdmin,
            tooltip: t('admin.link'),
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
        IconButton(
          onPressed: app.logout,
          tooltip: t('home.logout'),
          icon: const Icon(Icons.logout),
        ),
      ],
      footer: SyncStatus(app: app),
      children: [
        if (doc == null)
          CapsaCard(children: [Text(t('home.noProfiles'))])
        else ...[
          TestPlanCard(app: app),
          _Choices(app: app),
        ],
      ],
    );
  }

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(text: app.me?.displayName ?? '');
    String? error;
    final result = await showDialog<(String?,)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void save() {
            try {
              Navigator.pop(context, (displayNameInput(controller.text),));
            } on FormatException {
              setState(() => error = t('name.invalid'));
            }
          }

          return AlertDialog(
            title: Text(t('name.edit')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: displayNameMax,
                  autofillHints: const [AutofillHints.nickname],
                  decoration: InputDecoration(
                    labelText: t('name.label'),
                    helperText: t('name.hint'),
                    errorText: error,
                    errorMaxLines: 3,
                  ),
                  onSubmitted: (_) => save(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(t('name.cancel'))),
              FilledButton(onPressed: save, child: Text(t('name.save'))),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (result != null) await app.setDisplayName(result.$1);
  }
}

/// A labelled group of single-choice chips, like the PWA's radio "chips".
class _ChipGroup<T> extends StatelessWidget {
  const _ChipGroup({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final void Function(T) onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(labelOf(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Choices extends StatelessWidget {
  const _Choices({required this.app});

  final AppState app;

  static const _modes = [Mode.typed, Mode.choice, Mode.flashcard, Mode.parent];
  // 'test' is started from the test card, not chosen here.
  static const _selections = [Selection.mixed, Selection.due, Selection.mistakes, Selection.all];
  static const _directions = [Direction.srcToTr, Direction.trToSrc, null];

  void _toggleUnit(String id, bool on) {
    final all = [for (final u in app.index!.doc.units) u.id];
    final current = {...(app.prefs.units ?? all)};
    if (on) {
      current.add(id);
    } else {
      current.remove(id);
    }
    final units = all.where(current.contains).toList();
    app.setPrefs(app.prefs.copyWith(units: units.length == all.length ? null : units));
  }

  @override
  Widget build(BuildContext context) {
    final index = app.index!;
    final doc = index.doc;
    final src = langName(doc.profile.sourceLang);
    final tr = langName(app.lang);
    final progress = progressByUnit(
      app.states,
      profileId: doc.profile.id,
      entries: app.askableEntries(),
      units: {for (final u in doc.units) u.id},
      directions: app.directions,
      now: app.now(),
      config: app.config,
    );
    final planned = app.plannedCards().length;
    final selected = app.units;
    final textTheme = Theme.of(context).textTheme;

    return CapsaCard(
      children: [
        if (app.profiles.length > 1)
          DropdownMenu<String>(
            label: Text(t('home.profile')),
            initialSelection: app.profileId,
            expandedInsets: EdgeInsets.zero,
            onSelected: (id) => id == null ? null : app.selectProfile(id),
            dropdownMenuEntries: [
              for (final p in app.profiles)
                DropdownMenuEntry(value: p.id, label: p.doc.profile.title),
            ],
          )
        else
          Text(doc.profile.title, style: textTheme.titleLarge),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text(t('home.units'), style: textTheme.titleSmall)),
            TextButton(
              onPressed: () => app.setPrefs(app.prefs.copyWith(units: null)),
              child: Text(t('home.allUnits')),
            ),
            TextButton(
              onPressed: () => app.setPrefs(app.prefs.copyWith(units: <String>[])),
              child: Text(t('home.noUnits')),
            ),
          ],
        ),
        for (final unit in doc.units)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: selected.contains(unit.id),
            onChanged: (on) => _toggleUnit(unit.id, on ?? false),
            title: Text('${unit.number}. ${unit.title}'),
            subtitle: UnitProgress(progress[unit.id]),
          ),
        _ChipGroup(
          label: t('home.mode'),
          values: _modes,
          selected: app.prefs.mode,
          labelOf: (m) => t('home.mode.${m.name}'),
          onSelected: (mode) => app.setPrefs(app.prefs.copyWith(mode: mode)),
        ),
        _ChipGroup<Direction?>(
          label: t('home.direction'),
          values: _directions,
          selected: app.prefs.direction,
          labelOf: (d) => d == null
              ? t('home.direction.mixed')
              : t('direction.${d.wire}', {'src': src, 'tr': tr}),
          onSelected: (d) => app.setPrefs(app.prefs.copyWith(direction: d)),
        ),
        if (doc.profile.translationLangs.length > 1)
          _ChipGroup(
            label: t('home.language'),
            values: doc.profile.translationLangs,
            selected: app.lang,
            labelOf: langName,
            onSelected: (lang) => app.setPrefs(app.prefs.copyWith(lang: lang)),
          ),
        _ChipGroup(
          label: t('home.selection'),
          values: _selections,
          selected: app.prefs.selection,
          labelOf: (s) => t('home.selection.${s.name}'),
          onSelected: (s) => app.setPrefs(app.prefs.copyWith(selection: s)),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: app.openStats,
            icon: const Icon(Icons.bar_chart),
            label: Text(t('stats.link')),
          ),
        ),
        const SizedBox(height: 8),
        if (planned > 0)
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: app.beginSession,
            child: Text(t('home.start', {'count': planned}), style: const TextStyle(fontSize: 18)),
          )
        else
          Hint(t('home.nothing')),
      ],
    );
  }
}
