import 'package:flutter/material.dart';

/// Tokens de color de Grasp **en tema claro** — Sección 5.1 del documento maestro.
///
/// Esta clase y [AppColorsDark] son la **definición** de los dos temas. Quien
/// las lee es `GraspPalette`, que las expone por rol; una feature nunca importa
/// este fichero: consume `context.palette.<rol>`. La razón está explicada en
/// `grasp_palette.dart` — `AppColors.purple700` nombra un tono, y en modo
/// oscuro el rol que ese tono cumplía lo cumple un lavanda claro.
///
/// ## Nota de contraste (WCAG AA)
///
/// Ratios medidos contra blanco (`#FFFFFF`):
///
/// | Token       | vs blanco | Apto para…                                   |
/// |-------------|-----------|----------------------------------------------|
/// | `purple500` | 4.23 : 1  | rellenos e iconografía (≥3:1), **no** texto pequeño |
/// | `purple700` | 7.11 : 1  | texto, enlaces, labels — AAA                  |
/// | `purple900` | 13.6 : 1  | texto de máximo énfasis — AAA                 |
///
/// Por eso `purple500` **nunca** se usa como color de texto sobre fondo claro, y
/// el CTA primario no es un relleno plano de `purple500` sino un degradado
/// `purple500 → purple700`: el texto blanco queda sobre la mitad oscura y el
/// conjunto conserva el púrpura de marca de los bocetos.
abstract final class AppColors {
  const AppColors._();

  // ── Escala de marca (Sección 5.1) ────────────────────────────────────────
  /// Fondo general de la app.
  static const Color purple50 = Color(0xFFF5F2FA);

  /// Superficies secundarias, cards, inputs.
  static const Color purple100 = Color(0xFFEDE7F6);

  /// Bordes, dividers, estados hover suaves.
  static const Color purple200 = Color(0xFFDCCCF5);

  /// Chips, badges, elementos secundarios.
  static const Color purple300 = Color(0xFFC4B5FD);

  /// Iconografía, estados activos suaves, gráficos.
  static const Color purple400 = Color(0xFFA78BFA);

  /// Color primario de marca (CTAs, botón principal).
  static const Color purple500 = Color(0xFF8B5CF6);

  /// Estado pressed/hover del primario, enlaces, texto sobre fondo claro.
  static const Color purple700 = Color(0xFF6D28D9);

  /// Texto de máximo énfasis, headers.
  static const Color purple900 = Color(0xFF4C1D95);

  // ── Neutros ──────────────────────────────────────────────────────────────
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Texto principal sobre fondo claro.
  static const Color textPrimary = purple900;

  /// Texto secundario.
  ///
  /// Está más oscuro de lo que pediría un fondo blanco a propósito: en las
  /// pantallas de autenticación el texto cae sobre la escena acuarelada, cuyo
  /// tono más claro (~`#D8CBF9`) es el peor caso real. Con este valor da 5.6:1
  /// ahí y sigue cumpliendo de sobra sobre blanco.
  static const Color textSecondary = Color(0xFF4F4A63);

  /// Texto terciario: notas al pie, placeholders. Mismo criterio de contraste
  /// que [textSecondary] — 5.1:1 sobre la escena.
  static const Color textMuted = Color(0xFF55506B);

  // ── Semánticos ───────────────────────────────────────────────────────────
  /// Error accesible sobre fondo claro (5.9:1 sobre blanco).
  static const Color error = Color(0xFFB3261E);

  /// Verde de confirmación.
  ///
  /// Era `#1B7F5A`, que daba **4.48:1** sobre `purple50` — 0,02 por debajo de
  /// AA. Pasaba desapercibido porque el token se estrenó como un punto de
  /// actividad (un gráfico, que solo pide 3:1), pero desde el §9 también pinta
  /// el texto «Activo ahora» de la cabecera de conversación. Corregido al
  /// escribir el test de contraste del ADR 0031: ahora 5.46:1.
  static const Color success = Color(0xFF177052);

  // ── Degradados ───────────────────────────────────────────────────────────
  /// Fondo de pantalla: el lavado púrpura muy claro de `01-Start_Menu.jpeg`.
  static const List<Color> backgroundWash = <Color>[
    Color(0xFFFBFAFE),
    purple50,
    Color(0xFFEDE6F8),
  ];

  /// CTA primario. Empieza en el púrpura de marca y termina en el pressed,
  /// de forma que el texto blanco siempre cumple AA (ver nota de contraste).
  static const List<Color> primaryCta = <Color>[purple500, purple700];

  /// Sombra de marca para tarjetas y botones: púrpura difuso, nunca gris.
  static const Color shadow = Color(0x1A4C1D95);

  /// La misma, para lo que apenas se levanta: campos y tarjetas de sección.
  static const Color shadowSoft = Color(0x0F4C1D95);
}

/// Tokens de color de Grasp **en tema oscuro** (ADR 0031).
///
/// ## No es una inversión de [AppColors]
///
/// Invertir la luminancia de una escala morada da grises violáceos sucios y
/// pierde la marca. Lo que se conserva es el **rol**, no el tono: donde el tema
/// claro pone «el morado de marca con énfasis» el oscuro pone «el lavanda de
/// marca con énfasis». Por eso la escala tiene dos mitades con nombres
/// distintos, y ninguna se llama `purpleNNN`:
///
/// - `nightNNN` — la columna de **superficies**, de la más honda a la más alta.
///   Son moradas, no negras (`#14101F` conserva el tinte de marca): un negro
///   puro sobre OLED produce *smearing* al hacer scroll y, en una app de apoyo
///   entre iguales, lee como frío. Se pierde algo de batería frente al negro
///   puro y se acepta a cambio del tono.
/// - `lavenderNNN` — la columna de **contenido**: texto, iconos y marca. La
///   numeración crece hacia el tono más apagado, igual que en la escala clara.
///
/// ## Nota de contraste (WCAG AA), medida — no estimada
///
/// Ratios sobre `night900` (fondo) y sobre `night700` (tarjeta):
///
/// | Token          | vs `night900` | vs `night700` | Apto para…                     |
/// |----------------|---------------|---------------|--------------------------------|
/// | `lavender100`  | 15.45 : 1     | 13.64 : 1     | titulares y cuerpo — AAA       |
/// | `textSecondary`| 10.03 : 1     |  8.86 : 1     | cuerpo secundario — AAA        |
/// | `textMuted`    |  7.26 : 1     |  6.41 : 1     | notas, placeholders — AAA      |
/// | `lavender200`  | 10.12 : 1     |  8.94 : 1     | enlaces e iconos de acción     |
/// | `lavender300`  |  8.75 : 1     |  7.73 : 1     | iconografía                    |
/// | `lavender400`  |  6.87 : 1     |  6.06 : 1     | marca sobre fondo              |
/// | `error`        | 11.01 : 1     |  9.72 : 1     | texto de error                 |
/// | `success`      | 11.85 : 1     | 10.47 : 1     | confirmaciones                 |
///
/// Y **el sentido del par marca/etiqueta se invierte**: en claro el relleno es
/// `purple700` con texto blanco (7.11:1); en oscuro el relleno es `lavender200`
/// con texto `night950` (**9.67:1**). Un relleno oscuro sobre fondo oscuro no
/// se ve, y blanco sobre `lavender400` daría 2.4:1. Por eso `GraspPalette`
/// tiene un token `onBrand` en vez de dar por hecho que es blanco.
///
/// `night400` es la única excepción declarada: 2.02:1 contra el fondo. Es un
/// **relleno** (avatar de iniciales, píldora), nunca texto ni borde
/// informativo; lo que se pinta encima es `lavender100`, que da 7.66:1.
abstract final class AppColorsDark {
  const AppColorsDark._();

  // ── Superficies ──────────────────────────────────────────────────────────
  /// Lo que va **encima** de la marca: etiqueta de un CTA, icono de un FAB.
  /// Aesthetic++: negro casi puro, mínimo gris (era #1B1230).
  static const Color night950 = Color(0xFF0D0D0D);

  /// Fondo general de la app.
  /// Aesthetic++: negro casi puro, cero smearing en OLED (era #14101F).
  static const Color night900 = Color(0xFF0F0F0F);

  /// Tarjetas, hojas y campos.
  /// Aesthetic++: gris muy oscuro para separación sutil (era #221B33).
  static const Color night700 = Color(0xFF1A1A1A);

  /// Rellenos suaves: chips, burbuja propia, placeholder de avatar.
  /// Aesthetic++: gris oscuro manteniendo legibilidad (era #2C2440).
  static const Color night600 = Color(0xFF252525);

  /// Bordes, dividers y pistas de control.
  /// Aesthetic++: gris medio oscuro (era #3A3050).
  static const Color night500 = Color(0xFF333333);

  /// Relleno de elementos secundarios con texto encima.
  /// Aesthetic++: gris más prominente para contraste (era #4C3F73).
  static const Color night400 = Color(0xFF404040);

  // ── Contenido ────────────────────────────────────────────────────────────
  /// Texto de máximo énfasis y titulares.
  /// Aesthetic++: blanco puro para máximo contraste (era #EDE7F6).
  static const Color lavender100 = Color(0xFFFFFFFF);

  /// Marca con énfasis: enlaces, iconos de acción, relleno del botón primario.
  /// Aesthetic++: púrpura vibrante (era #C4B5FD).
  static const Color lavender200 = Color(0xFFD580FF);

  /// Iconografía decorativa y estados activos suaves.
  /// Aesthetic++: púrpura brillante para emoticonos (era #B9A6F5).
  static const Color lavender300 = Color(0xFFBB63FF);

  /// Color primario de marca.
  /// Aesthetic++: púrpura morado vibrante (era #A78BFA).
  static const Color lavender400 = Color(0xFFA952FF);

  /// Texto secundario: gris claro.
  static const Color textSecondary = Color(0xFFE0E0E0);
  /// Texto muted/placeholder: gris medio.
  static const Color textMuted = Color(0xFFB0B0B0);

  // ── Semánticos ───────────────────────────────────────────────────────────
  static const Color error = Color(0xFFFFB4AB);
  static const Color success = Color(0xFF6FE3B4);

  // ── Degradados y sombra ──────────────────────────────────────────────────
  /// Lavado del fondo. Va **de arriba claro a abajo hondo**, al revés que en el
  /// tema claro: en oscuro la luz viene de la parte alta de la pantalla y el
  /// pie se hunde, que es donde se apoya la escena de `CalmScene`.
  /// Aesthetic++: degradado negro con un poco de gris oscuro.
  static const List<Color> backgroundWash = <Color>[
    Color(0xFF131313),
    night900,
    Color(0xFF0B0B0B),
  ];

  /// CTA primario: relleno claro con etiqueta oscura (ver nota de contraste).
  static const List<Color> primaryCta = <Color>[lavender200, lavender400];

  /// En oscuro una sombra teñida no se ve: lo que separa una tarjeta del fondo
  /// es su propio tono (`night700` sobre `night900`) y este velo negro muy
  /// difuso bajo el borde.
  static const Color shadow = Color(0x8C000000);

  /// Ver [AppColors.shadowSoft].
  static const Color shadowSoft = Color(0x59000000);
}
