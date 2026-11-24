import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../learning/session.dart' show Progress;
import '../version.dart';
import 'theme.dart';

/// A page as in the PWA: a bar on top, content at most 40rem wide, and an optional
/// footer. Content scrolls; the offline notice sits above it.
class CapsaPage extends StatelessWidget {
  const CapsaPage({
    super.key,
    required this.app,
    required this.title,
    required this.children,
    this.actions = const [],
    this.footer,
    this.leading,
  });

  final AppState app;
  final Widget title;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? footer;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = CapsaColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: actions,
        leading: leading,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (!app.online && app.me != null)
              Material(
                color: colors.almostBg,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 18, color: colors.almost),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t('app.offline'))),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ?footer,
          ],
        ),
      ),
    );
  }
}

/// Padded card content.
class CapsaCard extends StatelessWidget {
  const CapsaCard({super.key, required this.children, this.color});

  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    // Keep children as separate semantics nodes; by default a Card merges them into
    // one, so a text field's name became the whole card (prompt, verdict, solution).
    semanticContainer: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: CapsaColors.of(context).muted, fontSize: 14));
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(text, style: TextStyle(color: CapsaColors.of(context).bad)),
  );
}

/// A stacked bar of segments with relative widths (count > 0 only).
class SegmentBar extends StatelessWidget {
  const SegmentBar(this.segments, {super.key, this.height = 8});

  final List<(int, Color)> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final (count, color) in segments)
        if (count > 0) (count, color),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        // Stretch, or childless ColoredBoxes would be zero pixels high; the gap
        // separates segments as in the PWA.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            for (final (count, color) in parts)
              Expanded(
                flex: count,
                child: ColoredBox(color: color),
              ),
          ],
        ),
      ),
    );
  }
}

/// Leitner boxes and new cards of a unit, with counts (F9).
class UnitProgress extends StatelessWidget {
  const UnitProgress(this.progress, {super.key});

  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) return const SizedBox.shrink();
    final colors = CapsaColors.of(context);
    final text = [
      if (p.mistakes > 0) t('progress.mistakes', {'count': p.mistakes}),
      if (p.due > 0) t('progress.due', {'count': p.due}),
      t('progress.new', {'count': p.fresh}),
    ].join(' · ');
    return Tooltip(
      message: t('progress.boxes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          SegmentBar([
            for (var i = 0; i < p.boxes.length; i++)
              (p.boxes[i], colors.boxes[i % colors.boxes.length]),
            (p.fresh, colors.fresh),
          ]),
          const SizedBox(height: 2),
          Hint(text),
        ],
      ),
    );
  }
}

/// Sync status for the overview, with "sync now" and the app version.
class SyncStatus extends StatefulWidget {
  const SyncStatus({super.key, required this.app});

  final AppState app;

  @override
  State<SyncStatus> createState() => _SyncStatusState();
}

class _SyncStatusState extends State<SyncStatus> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    // Re-render the relative time every minute.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final status = app.syncing
        ? t('sync.running')
        : [
            if (app.unsynced == 1) t('sync.pendingOne'),
            if (app.unsynced > 1) t('sync.pending', {'count': app.unsynced}),
            app.lastSyncAt != null
                ? t('sync.last', {'when': relativeTime(app.lastSyncAt!, app.now())})
                : t('sync.never'),
          ].join(' · ');
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: CapsaColors.of(context).border)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [Hint(status), Hint('Capsa $appVersion')],
              ),
            ),
            if (!app.syncing)
              IconButton(
                onPressed: app.refresh,
                tooltip: t('sync.now'),
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
      ),
    );
  }
}
