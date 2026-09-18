import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/domain/onboarding/onboarding_question.dart';
import 'package:grasp_mobile/features/onboarding/presentation/widgets/onboarding_option_card.dart';

/// La tarjeta de opción del onboarding — `02-onboarding-questions.jpeg`.
///
/// ## Por qué este fichero existe
///
/// Hallazgo **H-2** de la auditoría del 2026-08-28: en el emulador, las tarjetas cuya etiqueta ocupa
/// **dos líneas** pintaban `BOTTOM OVERFLOWED BY 0.896 PIXELS` y el texto salía cortado —«Ansiedad y
/// estrés cotidi…»—. Tres de las nueve opciones de la primera pregunta.
///
/// **No lo veía ningún test**, y no por descuido: los tests de widget corren por defecto en una
/// superficie de 800×600, que es más ancha que un móvil, así que la celda de la rejilla salía lo
/// bastante grande y el texto cabía en una línea. El fallo solo aparece con el ancho real. Por eso
/// aquí se fija el tamaño del dispositivo antes de montar nada.
void main() {
  /// Pixel 5: 1080×2340 px con densidad 2.75 → 392.7 × 851 en puntos lógicos. Es el emulador donde
  /// se vio el fallo, y el ancho es lo que decide si la etiqueta parte en dos líneas.
  const Size pixel5 = Size(392.7, 851.0);

  /// La celda que le toca a cada tarjeta dentro del `GridView.count` de la pantalla, calculada con
  /// los mismos números: 3 columnas, `crossAxisSpacing: 8`, el `gutter` de la pantalla a cada lado y
  /// `OnboardingOptionCard.gridAspectRatio`.
  ///
  /// Se replica aquí en vez de montar la pantalla entera **a propósito**: montarla exigiría los
  /// dobles del onboarding y el fallo quedaría enterrado entre otras diez cosas. Lo que se prueba es
  /// la tarjeta con el espacio que de verdad recibe.
  Widget enCelda(
    OnboardingOption option, {
    // La MISMA constante que usa la pantalla. Copiar el número aquí dejaría el test comprobando
    // una celda que ya no existe en cuanto alguien lo cambiara allí.
    double aspectRatio = OnboardingOptionCard.gridAspectRatio,
  }) {
    const double gutter = AppSpacing.gutter;
    const double spacing = AppSpacing.sm;
    final double ancho = (pixel5.width - gutter * 2 - spacing * 2) / 3;

    return MaterialApp(
      theme: AppTheme.light().copyWith(
        extensions: const <ThemeExtension<dynamic>>[GraspMotion.still()],
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: ancho,
            height: ancho / aspectRatio,
            child: OnboardingOptionCard(
              option: option,
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
  }

  /// Las tres etiquetas que desbordaban en el emulador, más la más larga del catálogo.
  ///
  /// Son las reales de `categories`, no inventadas: el fallo depende de cuántas líneas ocupa el
  /// texto con el ancho real, así que una etiqueta de prueba corta no probaría nada.
  const List<String> etiquetasLargas = <String>[
    'Ansiedad y estrés cotidiano',
    'Cambios de ciudad',
    'Crecimiento personal',
  ];

  for (final String etiqueta in etiquetasLargas) {
    testWidgets('«$etiqueta» no desborda la tarjeta (H-2)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = pixel5 * 2.75;
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        enCelda(
          OnboardingOption(
            slug: 'x',
            label: etiqueta,
            icon: Icons.self_improvement,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Un overflow de layout NO tumba el test por sí solo: Flutter lo registra como excepción y la
      // guarda. Si no se recoge con `takeException`, el test pasa en verde con la barra amarilla y
      // negra pintada — que es exactamente cómo este fallo llegó al emulador sin que nadie lo viera.
      expect(
        tester.takeException(),
        isNull,
        reason:
            'La tarjeta de «$etiqueta» desborda su celda. En el emulador se ve como '
            '«BOTTOM OVERFLOWED BY 0.896 PIXELS» y el texto sale cortado.',
      );
    });
  }

  testWidgets('la etiqueta admite TRES líneas, no dos', (
    WidgetTester tester,
  ) async {
    // ## Lo que este test NO puede comprobar, y por qué
    //
    // Lo natural sería afirmar `didExceedMaxLines == false`: que la etiqueta se lee entera. **Aquí
    // no se puede**, y no por una limitación del enfoque sino de la herramienta: `google_fonts` no
    // descarga nada en los tests, así que el texto se mide con una fuente de **fallback más ancha**
    // que la real. Se nota en que hasta «Autoestima» ocupa dos líneas aquí, cuando en el emulador
    // ocupa una. Un `didExceedMaxLines` medido con otra fuente no dice nada sobre la de verdad.
    //
    // Eso deja los tests de arriba como una **cota conservadora** —si el layout aguanta con una
    // fuente más ancha, aguanta con la real— y manda la comprobación del truncado al emulador,
    // que es donde la fuente es la de producción. Hecha el 2026-08-28.
    //
    // Lo que sí se puede fijar aquí es la DECISIÓN: tres líneas. Dos era el número del boceto,
    // pensado para «Autoestima» o «Duelo»; la etiqueta más larga del catálogo tiene 27 caracteres y
    // en los ~110 px de la celda no entra en dos por mucho alto que se le dé.
    tester.view.physicalSize = pixel5 * 2.75;
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      enCelda(
        const OnboardingOption(
          slug: 'x',
          label: 'Ansiedad y estrés cotidiano',
          icon: Icons.self_improvement,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Text texto = tester.widget<Text>(
      find.text('Ansiedad y estrés cotidiano'),
    );
    expect(texto.maxLines, 3);
    expect(
      texto.overflow,
      TextOverflow.ellipsis,
      reason:
          'El ellipsis se queda como red: el escalado de fuente del sistema lo controla el '
          'usuario, y sin él una etiqueta futura más larga volvería a desbordar.',
    );
  });
}
