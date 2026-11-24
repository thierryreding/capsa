import 'package:capsa/learning/leitner.dart';
import 'package:capsa/learning/session.dart' show Progress;
import 'package:capsa/learning/stats.dart';
import 'package:capsa/ui/common.dart';
import 'package:capsa/ui/stats_view.dart';
import 'package:capsa/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'support.dart';

Widget frame(Widget child) => MaterialApp(
  theme: capsaTheme(Brightness.light),
  home: Scaffold(body: ListView(children: [child])),
);

/// Sizes of the coloured bar segments in the tree (or below `within`).
List<Size> segments(WidgetTester tester, Color color, {Finder? within}) => [
  for (final e
      in (within == null
              ? find.byType(ColoredBox)
              : find.descendant(of: within, matching: find.byType(ColoredBox)))
          .evaluate())
    if ((e.widget as ColoredBox).color == color) (e.renderObject! as RenderBox).size,
];

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  testWidgets('unit progress segments are visible, sized by count', (tester) async {
    await tester.pumpWidget(
      frame(
        CheckboxListTile(
          value: true,
          onChanged: (_) {},
          title: const Text('1. Am Hafen'),
          subtitle: UnitProgress(
            Progress(total: 10, fresh: 6, due: 0, mistakes: 1, boxes: [1, 3, 0, 0, 0]),
          ),
        ),
      ),
    );
    final c = CapsaColors.light;
    final fresh = segments(tester, c.fresh).single;
    final box2 = segments(tester, c.boxes[1]).single;
    expect(fresh.height, 8);
    expect(box2.height, 8);
    expect(fresh.width / box2.width, closeTo(2, 0.05));
    expect(find.text('1 Fehler · 6 neu'), findsOneWidget);
  });

  testWidgets('the 14-day chart draws bars for days with answers', (tester) async {
    final vectors = loadJson('vectors/stats.json') as Map;
    final stats = learningStats(
      loadProfile(demoProfile),
      [for (final e in vectors['events'] as List) AnswerEvent.fromJson((e as Map).cast())],
      vectors['now'] as int,
      const LeitnerConfig(utcOffsetMinutes: 60),
    );
    await tester.pumpWidget(frame(StatsView(stats: stats, now: vectors['now'] as int)));
    // The day bars are the tappable days; the legend and the unit bars use the same blue.
    final right = segments(tester, CapsaColors.light.right, within: find.byType(InkWell));
    expect(right, hasLength(4)); // four days with right answers
    expect(right.every((s) => s.width > 0 && s.height > 0), isTrue);
    expect(
      find.textContaining('ventus – der Wind', findRichText: true),
      findsOneWidget,
    ); // among the hardest words
  });
}
