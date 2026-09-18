import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_motion.dart';
import 'app_typography.dart';
import 'grasp_palette.dart';

/// Radios de esquina observados en los bocetos.
abstract final class AppRadius {
  const AppRadius._();

  static const double field = 16;
  static const double card = 20;
  static const double sheet = 28;

  /// Píldoras: CTAs y chips (`09-Searching-rooms.jpeg`).
  static const double pill = 999;
}

/// Escala de espaciado (base 4).
abstract final class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Margen horizontal de pantalla en los bocetos.
  static const double gutter = 24;
}

/// Mapeo de los tokens de la Sección 5.1 a `ThemeData`.
///
/// Hay **un solo constructor** ([_build]) y dos paletas. Mantener dos métodos
/// paralelos sería garantizar que dentro de tres commits uno tenga un
/// `snackBarTheme` que el otro no: la diferencia entre claro y oscuro tiene que
/// vivir entera en `GraspPalette`, no repartida por el `ThemeData`. Lo único
/// que este fichero decide aparte del color es el `SystemUiOverlayStyle`, que
/// no es un color sino un brillo.
abstract final class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(GraspPalette.light);

  static ThemeData dark() => _build(GraspPalette.dark);

  static ThemeData _build(GraspPalette palette) {
    final bool isDark = palette.isDark;

    final ColorScheme scheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.brand,
      onPrimary: palette.onBrand,
      primaryContainer: palette.containerSubtle,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.iconSoft,
      onSecondary: palette.onBrand,
      secondaryContainer: palette.containerSubtle,
      onSecondaryContainer: palette.textPrimary,
      tertiary: palette.brandStrong,
      onTertiary: palette.onBrand,
      error: palette.error,
      onError: isDark ? const Color(0xFF601410) : AppColors.onPrimary,
      errorContainer: isDark ? const Color(0xFF3B1F1C) : const Color(0xFFF9DEDC),
      onErrorContainer: isDark ? palette.error : const Color(0xFF410E0B),
      surface: palette.canvas,
      onSurface: palette.textPrimary,
      surfaceContainerLowest: palette.surface,
      surfaceContainerLow: palette.canvas,
      surfaceContainer: palette.containerSubtle,
      surfaceContainerHigh: palette.outline,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.outline,
      outlineVariant: palette.containerSubtle,
      shadow: palette.shadow,
      // Más opaco en oscuro: un velo al 40% sobre un fondo ya oscuro no separa
      // el modal del contenido de detrás.
      scrim: isDark ? const Color(0xB3000000) : const Color(0x66000000),
      inverseSurface: palette.textPrimary,
      onInverseSurface: palette.canvas,
      inversePrimary: palette.chip,
    );

    final TextTheme textTheme = AppTypography.build(palette);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: palette.canvas,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: palette.textPrimary,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      // Los bocetos usan tarjetas blancas con sombra difusa, nunca borde duro.
      // En oscuro la sombra no separa nada, así que lo que levanta la tarjeta
      // es su propio tono: `surface` está un escalón por encima de `canvas`.
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + AppSpacing.xs,
          vertical: AppSpacing.md + AppSpacing.xs,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: palette.textMuted),
        labelStyle: textTheme.labelMedium,
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: palette.brandStrong,
        ),
        prefixIconColor: palette.iconSoft,
        suffixIconColor: palette.iconSoft,
        border: _fieldBorder(palette.outline),
        enabledBorder: _fieldBorder(palette.outline),
        focusedBorder: _fieldBorder(palette.brand, width: 1.6),
        errorBorder: _fieldBorder(palette.error),
        focusedErrorBorder: _fieldBorder(palette.error, width: 1.6),
        errorStyle: textTheme.bodySmall?.copyWith(color: palette.error),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.brandStrong,
          foregroundColor: palette.onBrand,
          minimumSize: const Size.fromHeight(56),
          textStyle: textTheme.labelLarge?.copyWith(color: palette.onBrand),
          shape: const StadiumBorder(),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.brandStrong,
          textStyle: textTheme.labelLarge?.copyWith(color: palette.brandStrong),
          shape: const StadiumBorder(),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.textPrimary,
          backgroundColor: palette.surface,
          minimumSize: const Size.fromHeight(56),
          side: BorderSide(color: palette.outline),
          textStyle: textTheme.labelLarge,
          shape: const StadiumBorder(),
        ),
      ),

      // El snackbar se pinta siempre **al revés** que la app: es un aviso
      // pasajero, y en oscuro un rectángulo claro es lo que lo despega del
      // fondo igual que uno oscuro lo despega en claro.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.canvas),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: palette.outline,
        thickness: 1,
        space: 1,
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return states.contains(WidgetState.selected)
              ? palette.brandStrong
              : Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(palette.onBrand),
        side: BorderSide(color: palette.chip, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.brand,
        linearTrackColor: palette.containerSubtle,
        circularTrackColor: palette.containerSubtle,
      ),

      // Sin `pageTransitionsTheme` propio: los valores por defecto de Material 3
      // ya dan el deslizamiento nativo en iOS y el fundido en Android, que es
      // exactamente lo que queremos. Fijarlo aquí solo serviría para quedarnos
      // atrás cuando el framework mejore la transición.
      extensions: <ThemeExtension<dynamic>>[const GraspMotion(), palette],
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1.2}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

/// Expone las duraciones de `AppMotion` a través del tema, para que un widget
/// pueda respetarlas sin importar `app_motion.dart` y para poder anularlas en
/// tests (poniéndolas a cero) sin tocar el código de las pantallas.
@immutable
class GraspMotion extends ThemeExtension<GraspMotion> {
  const GraspMotion({
    this.fast = AppMotion.fast,
    this.medium = AppMotion.medium,
    this.slow = AppMotion.slow,
    this.ambient = AppMotion.ambient,
  });

  /// Movimiento desactivado, para tests de widget: las animaciones en bucle
  /// (`ambient`) se paran del todo, porque si no `pumpAndSettle` no termina
  /// nunca.
  ///
  /// Las transiciones finitas quedan en 1 ms, **no** en cero: `AnimatedSize`
  /// con duración cero completa su animación de forma síncrona dentro de su
  /// propio `performLayout` y dispara «RenderAnimatedSize was mutated in its
  /// own performLayout». 1 ms se resuelve en el primer `pump` igual de rápido,
  /// pero por el camino asíncrono.
  const GraspMotion.still()
    : fast = const Duration(milliseconds: 1),
      medium = const Duration(milliseconds: 1),
      slow = const Duration(milliseconds: 1),
      ambient = Duration.zero;

  final Duration fast;
  final Duration medium;
  final Duration slow;
  final Duration ambient;

  /// `true` cuando el movimiento está desactivado (tests o accesibilidad).
  bool get isStill => ambient == Duration.zero;

  static GraspMotion of(BuildContext context) =>
      Theme.of(context).extension<GraspMotion>() ?? const GraspMotion();

  @override
  GraspMotion copyWith({
    Duration? fast,
    Duration? medium,
    Duration? slow,
    Duration? ambient,
  }) => GraspMotion(
    fast: fast ?? this.fast,
    medium: medium ?? this.medium,
    slow: slow ?? this.slow,
    ambient: ambient ?? this.ambient,
  );

  @override
  GraspMotion lerp(ThemeExtension<GraspMotion>? other, double t) =>
      other is GraspMotion && t >= 0.5 ? other : this;
}
