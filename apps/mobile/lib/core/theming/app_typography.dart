import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'grasp_palette.dart';

/// Tipografía de marca — tomada de `pictures/icons/icon-sketches.jpeg`:
/// **Poppins** para display/títulos, **Inter** para cuerpo y UI.
///
/// Las features consumen `Theme.of(context).textTheme`; nunca `GoogleFonts.*`
/// directamente, para que un cambio de fuente sea un cambio en un solo sitio.
///
/// Nota operativa: `google_fonts` descarga las tipografías en la primera
/// ejecución y las cachea. Antes de publicar hay que empaquetar los `.ttf` en
/// `assets/fonts/` para que la primera apertura sin red no caiga al fallback.
/// Registrado en `docs/decisions/`.
abstract final class AppTypography {
  const AppTypography._();

  /// Los colores de texto salen de [palette], no de una constante: `bodyMedium`
  /// es "texto secundario", y ese rol es `#4F4A63` en claro y `#C3B9DA` en
  /// oscuro. Si el `TextTheme` se construyera una sola vez, la mitad de la app
  /// —todo lo que consume `Theme.of(context).textTheme` sin `copyWith`— se
  /// quedaría en el tema claro sin que ningún analizador lo dijera.
  static TextTheme build(GraspPalette palette) {
    final TextTheme base = palette.isDark
        ? ThemeData.dark().textTheme
        : ThemeData.light().textTheme;

    // Poppins para lo que "habla" con voz de marca.
    final TextTheme display = GoogleFonts.poppinsTextTheme(base);
    // Inter para lo que se lee de corrido.
    final TextTheme body = GoogleFonts.interTextTheme(base);

    return TextTheme(
      displayLarge: display.displayLarge?.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: palette.textPrimary,
      ),
      displayMedium: display.displayMedium?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: palette.textPrimary,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: palette.textPrimary,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      titleLarge: display.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      titleMedium: body.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.5,
        color: palette.textPrimary,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontSize: 15,
        height: 1.5,
        color: palette.textSecondary,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontSize: 13,
        height: 1.45,
        color: palette.textSecondary,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: palette.textPrimary,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: palette.textSecondary,
      ),
    );
  }

  /// Logotipo "Grasp". Vive aparte del `TextTheme` porque no es un rol de texto
  /// sino un elemento de marca con tracking propio.
  static TextStyle wordmark({
    required double fontSize,
    required GraspPalette palette,
  }) => GoogleFonts.poppins(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    letterSpacing: fontSize * 0.06,
    color: palette.textPrimary,
    height: 1.0,
  );
}
