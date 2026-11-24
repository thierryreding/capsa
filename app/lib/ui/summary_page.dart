import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../i18n.dart';
import 'common.dart';

class SummaryPage extends StatelessWidget {
  const SummaryPage({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final result = app.session?.summary ?? (cards: 0, firstTry: 0, answers: 0);
    final more = app.plannedCards(app.sessionKind).isNotEmpty;
    return CapsaPage(
      app: app,
      title: Text(t('app.title')),
      footer: SyncStatus(app: app),
      children: [
        CapsaCard(
          children: [
            Text(t('summary.title'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(t('summary.result', {'firstTry': result.firstTry, 'cards': result.cards})),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (more)
                  FilledButton(
                    onPressed: () => app.beginSession(app.sessionKind),
                    child: Text(t('summary.more')),
                  ),
                OutlinedButton(onPressed: app.goHome, child: Text(t('summary.home'))),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
