import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'models.dart';

/// Farbkonzept "Tartan & Graphit".
///
/// - Graphit trägt die App (Kopfleiste, Text, ausgewählte Zustände):
///   ruhig und geerdet wie Hantelstahl und Hallenboden.
/// - Tartan, das Rot-Orange der Laufbahn, ist die einzige Signalfarbe und
///   markiert ausschließlich Aktionen und Fortschritt.
/// - Papier, ein warmes Off-White, hält Flächen hell und gut lesbar.
/// - Je eine Farbe pro Trainingsart, damit ein Plan auf einen Blick
///   lesbar ist: Kraft = Stahlblau, Physio = Grün, Mobility = Ocker.
abstract final class AppPalette {
  static const graphite = Color(0xFF15191C);
  static const graphiteSoft = Color(0xFF242A2F);
  static const tartan = Color(0xFFC8401C);
  static const tartanBright = Color(0xFFFF7A50);
  static const paper = Color(0xFFF5F4F0);

  static const kraft = Color(0xFF2F5F9E);
  static const physio = Color(0xFF1E8A6E);
  static const mobility = Color(0xFFA9741A);
  static const success = Color(0xFF2E7D4F);

  static const kraftBright = Color(0xFF8DB4EA);
  static const physioBright = Color(0xFF6FD1B4);
  static const mobilityBright = Color(0xFFE5B55C);
  static const successBright = Color(0xFF7BD3A0);
}

const headingFont = 'BarlowCondensed';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.kraft,
    required this.physio,
    required this.mobility,
    required this.success,
    required this.hero,
    required this.onHero,
    required this.heroAccent,
  });

  final Color kraft;
  final Color physio;
  final Color mobility;

  /// Erledigt / abgehakt.
  final Color success;

  /// Dunkle Akzentfläche (Tageskarte, Video-Platzhalter).
  final Color hero;
  final Color onHero;
  final Color heroAccent;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  Color category(ExerciseCategory c) => switch (c) {
    ExerciseCategory.kraft => kraft,
    ExerciseCategory.physio => physio,
    ExerciseCategory.mobility => mobility,
  };

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      kraft: l(kraft, other.kraft),
      physio: l(physio, other.physio),
      mobility: l(mobility, other.mobility),
      success: l(success, other.success),
      hero: l(hero, other.hero),
      onHero: l(onHero, other.onHero),
      heroAccent: l(heroAccent, other.heroAccent),
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppPalette.tartan,
        brightness: brightness,
      ).copyWith(
        primary: dark ? AppPalette.tartanBright : AppPalette.tartan,
        onPrimary: dark ? const Color(0xFF2A0E05) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF5A1F0B)
            : const Color(0xFFFBE3DA),
        onPrimaryContainer: dark
            ? const Color(0xFFFFD9CC)
            : const Color(0xFF5A1A08),
        // Ausgewählte Chips/Segmente: Graphit statt bunt.
        secondary: dark ? const Color(0xFFC9CED2) : AppPalette.graphiteSoft,
        onSecondary: dark ? AppPalette.graphite : Colors.white,
        secondaryContainer: dark
            ? const Color(0xFFECEAE4)
            : AppPalette.graphite,
        onSecondaryContainer: dark ? AppPalette.graphite : Colors.white,
        tertiary: dark ? AppPalette.physioBright : AppPalette.physio,
        onTertiary: dark ? AppPalette.graphite : Colors.white,
        surface: dark ? const Color(0xFF0F1214) : AppPalette.paper,
        onSurface: dark ? const Color(0xFFECEAE4) : AppPalette.graphite,
        onSurfaceVariant: dark
            ? const Color(0xFFA5ABB0)
            : const Color(0xFF555B61),
        surfaceContainerLowest: dark ? const Color(0xFF0B0D0F) : Colors.white,
        surfaceContainerLow: dark ? const Color(0xFF171B1E) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF1B2024)
            : const Color(0xFFEFEDE7),
        surfaceContainerHigh: dark
            ? const Color(0xFF22282D)
            : const Color(0xFFE8E5DE),
        surfaceContainerHighest: dark
            ? const Color(0xFF2B3238)
            : const Color(0xFFE1DED6),
        outline: dark ? const Color(0xFF7A8187) : const Color(0xFF80858A),
        outlineVariant: dark
            ? const Color(0xFF30373D)
            : const Color(0xFFD8D4CA),
        surfaceTint: Colors.transparent,
      );

  final colors = AppColors(
    kraft: dark ? AppPalette.kraftBright : AppPalette.kraft,
    physio: dark ? AppPalette.physioBright : AppPalette.physio,
    mobility: dark ? AppPalette.mobilityBright : AppPalette.mobility,
    success: dark ? AppPalette.successBright : AppPalette.success,
    hero: dark ? const Color(0xFF1B2024) : AppPalette.graphite,
    onHero: Colors.white,
    heroAccent: AppPalette.tartanBright,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: brightness,
  );

  TextStyle? heading(TextStyle? s, {FontWeight weight = FontWeight.w600}) =>
      s?.copyWith(
        fontFamily: headingFont,
        fontWeight: weight,
        letterSpacing: 0.2,
        height: 1.1,
      );

  final text = base.textTheme.copyWith(
    displaySmall: heading(base.textTheme.displaySmall, weight: FontWeight.w700),
    headlineMedium: heading(
      base.textTheme.headlineMedium,
      weight: FontWeight.w700,
    ),
    headlineSmall: heading(base.textTheme.headlineSmall),
    titleLarge: heading(base.textTheme.titleLarge),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    ),
  );

  final barBackground = dark ? scheme.surface : AppPalette.graphite;
  final barForeground = dark ? scheme.onSurface : Colors.white;

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [colors],
    appBarTheme: AppBarTheme(
      backgroundColor: barBackground,
      foregroundColor: barForeground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        fontFamily: headingFont,
        fontWeight: FontWeight.w600,
        fontSize: 26,
        letterSpacing: 0.3,
        color: barForeground,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primary.withValues(alpha: dark ? 0.24 : 0.14),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: false,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
