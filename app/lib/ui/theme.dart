/// Colours of web/src/app.css, light and dark, as a Material 3 theme plus the colours
/// Material has no slot for (Leitner boxes, verdicts, chart series).
library;

import 'package:material_ui/material_ui.dart';

@immutable
class CapsaColors extends ThemeExtension<CapsaColors> {
  const CapsaColors({
    required this.muted,
    required this.border,
    required this.ok,
    required this.okBg,
    required this.almost,
    required this.almostBg,
    required this.bad,
    required this.badBg,
    required this.boxes,
    required this.fresh,
    required this.right,
    required this.wrong,
  });

  final Color muted, border, ok, okBg, almost, almostBg, bad, badBg, fresh, right, wrong;

  /// Leitner boxes 1 to 5: an ordinal one-hue ramp (validated for the PWA).
  final List<Color> boxes;

  static const light = CapsaColors(
    muted: Color(0xff5d6b70),
    border: Color(0xffd9d2c3),
    ok: Color(0xff2e7d4f),
    okBg: Color(0xffe3f3e8),
    almost: Color(0xff9a6a00),
    almostBg: Color(0xfffdf1d6),
    bad: Color(0xffb3261e),
    badBg: Color(0xfffbe4e2),
    boxes: [
      Color(0xff86b6ef),
      Color(0xff5598e7),
      Color(0xff2a78d6),
      Color(0xff1c5cab),
      Color(0xff104281),
    ],
    fresh: Color(0xffd9d2c3),
    right: Color(0xff2a78d6),
    wrong: Color(0xffeb6834),
  );

  static const dark = CapsaColors(
    muted: Color(0xff9aa7ab),
    border: Color(0xff3a4447),
    ok: Color(0xff7cc79a),
    okBg: Color(0xff1d3326),
    almost: Color(0xffe2b65a),
    almostBg: Color(0xff3a2f14),
    bad: Color(0xfff08a80),
    badBg: Color(0xff3d1f1c),
    boxes: [
      Color(0xff184f95),
      Color(0xff256abf),
      Color(0xff3987e5),
      Color(0xff6da7ec),
      Color(0xff9ec5f4),
    ],
    fresh: Color(0xff3a4447),
    right: Color(0xff3987e5),
    wrong: Color(0xffd95926),
  );

  static CapsaColors of(BuildContext context) => Theme.of(context).extension<CapsaColors>()!;

  @override
  CapsaColors copyWith() => this;

  @override
  CapsaColors lerp(CapsaColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

ThemeData capsaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final accent = dark ? const Color(0xff7fb7c9) : const Color(0xff1d4e5f);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    onPrimary: dark ? const Color(0xff10191c) : Colors.white,
    surface: dark ? const Color(0xff161b1d) : const Color(0xfff4f1ea),
    surfaceContainerLow: dark ? const Color(0xff202729) : const Color(0xfffffdf8),
    onSurface: dark ? const Color(0xffe9e6df) : const Color(0xff1f2a2e),
    outlineVariant: dark ? const Color(0xff3a4447) : const Color(0xffd9d2c3),
  );
  final colors = dark ? CapsaColors.dark : CapsaColors.light;
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [colors],
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
    ),
  );
}
