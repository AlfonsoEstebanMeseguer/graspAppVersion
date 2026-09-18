import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Los tokens de color de Grasp **por rol**, resueltos según el brillo activo.
///
/// ## Por qué existe esto y no basta `AppColors`
///
/// `AppColors` es una escala de marca: `purple500` es un hexadecimal concreto y
/// no cambia nunca. Eso funciona mientras haya un solo tema. En cuanto hay dos,
/// una feature que escribe `AppColors.purple700` está diciendo «este texto es
/// morado oscuro» cuando lo que quiere decir es «este texto es la marca, con
/// énfasis» — y en modo oscuro la marca con énfasis es un lavanda **claro**.
///
/// Así que el nombre del token pasa a ser el **rol**, no el tono:
///
/// | Rol                | Claro (`AppColors`) | Oscuro (`AppColorsDark`) |
/// |--------------------|---------------------|--------------------------|
/// | `canvas`           | `purple50`          | `night900`               |
/// | `surface`          | blanco              | `night700`               |
/// | `containerSubtle`  | `purple100`         | `night600`               |
/// | `outline`          | `purple200`         | `night500`               |
/// | `chip`             | `purple300`         | `night400`               |
/// | `iconSoft`         | `purple400`         | `lavender300`            |
/// | `brand`            | `purple500`         | `lavender400`            |
/// | `brandStrong`      | `purple700`         | `lavender200`            |
/// | `onBrand`          | blanco              | `night950`               |
/// | `textPrimary`      | `purple900`         | `lavender100`            |
///
/// Fíjate en que **`onBrand` también se invierte**: en claro el relleno de marca
/// es oscuro y la etiqueta blanca; en oscuro el relleno es claro y la etiqueta
/// oscura. Es el idioma de Material 3 y es lo que mantiene el contraste sin
/// tener que inventar un tercer tono. Consecuencia práctica: `onBrand` **no es
/// «blanco»** — un icono blanco sobre una foto o sobre un velo negro (el visor
/// de avatar) usa `Colors.white` a pelo, porque ahí no depende del tema.
///
/// ## Cómo se consume
///
/// ```dart
/// Container(color: context.palette.containerSubtle)
/// ```
///
/// Nunca `Color(0xFF...)` suelto, y ya tampoco `AppColors.x` dentro de una
/// feature: `AppColors`/`AppColorsDark` son la *definición* de los dos temas y
/// solo los lee este fichero.
@immutable
class GraspPalette extends ThemeExtension<GraspPalette> {
  const GraspPalette({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.containerSubtle,
    required this.outline,
    required this.chip,
    required this.iconSoft,
    required this.brand,
    required this.brandStrong,
    required this.onBrand,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.error,
    required this.success,
    required this.shadow,
    required this.shadowSoft,
    required this.backgroundWash,
    required this.primaryCta,
  });

  /// El tema al que pertenece esta paleta. Lo usan los widgets que necesitan
  /// decidir algo que no es un color (el `SystemUiOverlayStyle`, el brillo de
  /// los iconos de la barra de estado, la opacidad de una ilustración).
  final Brightness brightness;

  /// Fondo general de la app.
  final Color canvas;

  /// Tarjetas, hojas y campos: la superficie que se levanta sobre [canvas].
  final Color surface;

  /// Rellenos suaves: chips, burbuja propia, placeholder de avatar.
  final Color containerSubtle;

  /// Bordes, dividers y pistas de control.
  final Color outline;

  /// Fondo de elementos secundarios con texto encima (avatar de iniciales).
  final Color chip;

  /// Iconografía decorativa y estados activos suaves.
  final Color iconSoft;

  /// Color primario de marca: rellenos de CTA, puntos de actividad, progreso.
  final Color brand;

  /// Marca con énfasis: texto de enlace, iconos de acción, botón primario.
  final Color brandStrong;

  /// Lo que se pinta **encima** de [brand] o [brandStrong].
  final Color onBrand;

  /// Texto de máximo énfasis y titulares.
  final Color textPrimary;

  final Color textSecondary;
  final Color textMuted;
  final Color error;
  final Color success;

  /// Sombra de marca: difusa y teñida, nunca gris.
  final Color shadow;

  /// La misma sombra, para elementos que apenas se levantan (campos, tarjetas
  /// de sección). Es un token propio y no un `withValues` porque en oscuro no
  /// es «la misma sombra más transparente»: es un negro, mientras que en claro
  /// es un morado.
  final Color shadowSoft;

  /// Lavado vertical del fondo de pantalla (3 paradas).
  final List<Color> backgroundWash;

  /// Degradado del CTA primario (2 paradas).
  final List<Color> primaryCta;

  bool get isDark => brightness == Brightness.dark;

  /// Tema claro — el de los bocetos de `pictures/screens/`.
  static const GraspPalette light = GraspPalette(
    brightness: Brightness.light,
    canvas: AppColors.purple50,
    surface: AppColors.surface,
    containerSubtle: AppColors.purple100,
    outline: AppColors.purple200,
    chip: AppColors.purple300,
    iconSoft: AppColors.purple400,
    brand: AppColors.purple500,
    brandStrong: AppColors.purple700,
    onBrand: AppColors.onPrimary,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    error: AppColors.error,
    success: AppColors.success,
    shadow: AppColors.shadow,
    shadowSoft: AppColors.shadowSoft,
    backgroundWash: AppColors.backgroundWash,
    primaryCta: AppColors.primaryCta,
  );

  /// Tema oscuro — ver la nota de contraste de [AppColorsDark].
  static const GraspPalette dark = GraspPalette(
    brightness: Brightness.dark,
    canvas: AppColorsDark.night900,
    surface: AppColorsDark.night700,
    containerSubtle: AppColorsDark.night600,
    outline: AppColorsDark.night500,
    chip: AppColorsDark.night400,
    iconSoft: AppColorsDark.lavender300,
    brand: AppColorsDark.lavender400,
    brandStrong: AppColorsDark.lavender200,
    onBrand: AppColorsDark.night950,
    textPrimary: AppColorsDark.lavender100,
    textSecondary: AppColorsDark.textSecondary,
    textMuted: AppColorsDark.textMuted,
    error: AppColorsDark.error,
    success: AppColorsDark.success,
    shadow: AppColorsDark.shadow,
    shadowSoft: AppColorsDark.shadowSoft,
    backgroundWash: AppColorsDark.backgroundWash,
    primaryCta: AppColorsDark.primaryCta,
  );

  /// La paleta del tema activo.
  ///
  /// Cae a [light] si no hay extensión —solo puede pasar en un test que monte
  /// un `MaterialApp` con un `ThemeData` ajeno— para que un widget nunca
  /// reviente por un tema mal construido.
  static GraspPalette of(BuildContext context) => ofTheme(Theme.of(context));

  /// Igual que [of], para los helpers que ya reciben el `ThemeData` y no el
  /// `BuildContext` (`Widget _cuerpo(ThemeData theme)` y compañía). Evita tener
  /// que arrastrar un segundo parámetro por toda la cadena de llamadas.
  static GraspPalette ofTheme(ThemeData theme) =>
      theme.extension<GraspPalette>() ?? light;

  @override
  GraspPalette copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? surface,
    Color? containerSubtle,
    Color? outline,
    Color? chip,
    Color? iconSoft,
    Color? brand,
    Color? brandStrong,
    Color? onBrand,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? error,
    Color? success,
    Color? shadow,
    Color? shadowSoft,
    List<Color>? backgroundWash,
    List<Color>? primaryCta,
  }) => GraspPalette(
    brightness: brightness ?? this.brightness,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    containerSubtle: containerSubtle ?? this.containerSubtle,
    outline: outline ?? this.outline,
    chip: chip ?? this.chip,
    iconSoft: iconSoft ?? this.iconSoft,
    brand: brand ?? this.brand,
    brandStrong: brandStrong ?? this.brandStrong,
    onBrand: onBrand ?? this.onBrand,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    error: error ?? this.error,
    success: success ?? this.success,
    shadow: shadow ?? this.shadow,
    shadowSoft: shadowSoft ?? this.shadowSoft,
    backgroundWash: backgroundWash ?? this.backgroundWash,
    primaryCta: primaryCta ?? this.primaryCta,
  );

  /// Interpola tono a tono para que el cambio de tema no sea un corte seco.
  ///
  /// `brightness` **no** se interpola: salta en la mitad. Un brillo intermedio
  /// no existe, y los widgets que lo consultan (overlay de la barra de estado)
  /// necesitan un booleano, no una mezcla.
  @override
  GraspPalette lerp(ThemeExtension<GraspPalette>? other, double t) {
    if (other is! GraspPalette) return this;
    return GraspPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      containerSubtle: Color.lerp(containerSubtle, other.containerSubtle, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      iconSoft: Color.lerp(iconSoft, other.iconSoft, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      shadowSoft: Color.lerp(shadowSoft, other.shadowSoft, t)!,
      backgroundWash: _lerpAll(backgroundWash, other.backgroundWash, t),
      primaryCta: _lerpAll(primaryCta, other.primaryCta, t),
    );
  }

  static List<Color> _lerpAll(List<Color> a, List<Color> b, double t) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return <Color>[
      for (int i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!,
    ];
  }
}

/// Azúcar para no repetir `GraspPalette.of(context)` en cada línea.
extension GraspPaletteContext on BuildContext {
  GraspPalette get palette => GraspPalette.of(this);
}

/// La misma azúcar donde lo que hay a mano es el tema y no el contexto.
extension GraspPaletteTheme on ThemeData {
  GraspPalette get palette => GraspPalette.ofTheme(this);
}
