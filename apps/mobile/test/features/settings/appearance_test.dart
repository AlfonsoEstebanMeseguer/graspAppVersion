import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grasp_mobile/core/theming/app_theme.dart';
import 'package:grasp_mobile/core/theming/grasp_palette.dart';
import 'package:grasp_mobile/data/preferences/appearance_store.dart';
import 'package:grasp_mobile/domain/settings/appearance_mode.dart';
import 'package:grasp_mobile/features/settings/application/appearance_controller.dart';
import 'package:grasp_mobile/features/settings/presentation/settings_screen.dart';
import 'package:grasp_mobile/features/settings/presentation/widgets/appearance_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El modo oscuro y su puerta de entrada (ADR 0031).
///
/// El montaje replica el de producción: `MaterialApp` con **los dos** temas y
/// un `themeMode` gobernado por el controlador. Montar solo el claro haría
/// pasar cualquier implementación, incluida una que no cambie nada.
Future<GraspPalette> _pumpAjustes(
  WidgetTester tester, {
  Brightness sistema = Brightness.light,
}) async {
  late GraspPalette vista;

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appearanceStoreProvider.overrideWithValue(
          AppearanceStore(await SharedPreferences.getInstance()),
        ),
      ],
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? _) {
          // El brillo del sistema envuelve al `MaterialApp` y NO cuelga de su
          // `builder:`: ahí dentro el tema ya está resuelto, y un
          // `platformBrightness` puesto abajo no lo tocaría. El primer intento
          // de este arnés lo puso en el `builder` y el caso de «Automático»
          // pasó a ser vacuo.
          return MediaQuery(
            data: MediaQueryData(platformBrightness: sistema),
            child: MaterialApp(
            theme: AppTheme.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[
                const GraspMotion.still(),
                GraspPalette.light,
              ],
            ),
            darkTheme: AppTheme.dark().copyWith(
              extensions: <ThemeExtension<dynamic>>[
                const GraspMotion.still(),
                GraspPalette.dark,
              ],
            ),
            themeMode: ref.watch(appearanceControllerProvider).themeMode,
            home: Builder(
              builder: (BuildContext context) {
                vista = context.palette;
                return const SettingsScreen();
              },
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vista;
}

/// Relee la paleta que está pintando la pantalla ahora mismo.
GraspPalette _paletaViva(WidgetTester tester) {
  final BuildContext context = tester.element(
    find.byType(SettingsScreen).first,
  );
  return GraspPalette.of(context);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // ══════════════════════════════════════════════════════════════════════════
  // EL AJUSTE HACE ALGO
  // ══════════════════════════════════════════════════════════════════════════
  group('Ajustes › Apariencia', () {
    testWidgets('arranca en Automático y con las tres opciones', (
      WidgetTester tester,
    ) async {
      await _pumpAjustes(tester);

      expect(find.text('Apariencia'), findsOneWidget);
      for (final AppearanceMode m in AppearanceMode.values) {
        expect(find.byKey(AppearanceSection.optionKey(m)), findsOneWidget);
      }
      expect(find.text('Automático'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);
    });

    testWidgets('al elegir Oscuro la APP se oscurece de verdad', (
      WidgetTester tester,
    ) async {
      await _pumpAjustes(tester);

      // Control: antes de tocar nada, y con el sistema en claro, la app está
      // en claro. Sin esta línea el test no distingue «se puso oscuro» de
      // «siempre estuvo oscuro».
      expect(_paletaViva(tester).isDark, isFalse);

      await tester.tap(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.dark)),
      );
      await tester.pumpAndSettle();

      final GraspPalette despues = _paletaViva(tester);
      expect(despues.isDark, isTrue);
      // No basta con el booleano: se comprueba que lo que se pinta son los
      // tonos de la escala oscura y no los claros con otra etiqueta.
      expect(despues.canvas, GraspPalette.dark.canvas);
      expect(despues.textPrimary, GraspPalette.dark.textPrimary);
      expect(
        Theme.of(
          tester.element(find.byType(SettingsScreen).first),
        ).brightness,
        Brightness.dark,
      );
    });

    testWidgets('y al volver a Claro se deshace', (WidgetTester tester) async {
      await _pumpAjustes(tester);

      await tester.tap(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.dark)),
      );
      await tester.pumpAndSettle();
      expect(_paletaViva(tester).isDark, isTrue);

      await tester.tap(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.light)),
      );
      await tester.pumpAndSettle();
      expect(_paletaViva(tester).isDark, isFalse);
    });

    testWidgets('Automático obedece al sistema, no a la última elección', (
      WidgetTester tester,
    ) async {
      // El sistema dice «oscuro»; el ajuste está en Automático de fábrica.
      await _pumpAjustes(tester, sistema: Brightness.dark);
      expect(_paletaViva(tester).isDark, isTrue);

      // Fijar «Claro» tiene que ganarle al sistema: eso es lo que distingue
      // una elección explícita de la ausencia de elección.
      await tester.tap(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.light)),
      );
      await tester.pumpAndSettle();
      expect(_paletaViva(tester).isDark, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // SE ESCRIBE **Y SE LEE** — precedente 8 de `flutter-ui`
  // ══════════════════════════════════════════════════════════════════════════
  group('la preferencia persiste', () {
    testWidgets('elegir Oscuro lo deja escrito en el dispositivo', (
      WidgetTester tester,
    ) async {
      await _pumpAjustes(tester);
      await tester.tap(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.dark)),
      );
      await tester.pumpAndSettle();

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(AppearanceStore(prefs).read(), AppearanceMode.dark);
    });

    testWidgets('y el siguiente arranque LO LEE: abre ya en oscuro', (
      WidgetTester tester,
    ) async {
      // Un toggle que se escribe y no lo lee nadie es un botón que miente
      // (`flutter-ui`, precedente 8). Este caso es la mitad que suele faltar:
      // se parte de disco con el valor puesto y NADIE toca la pantalla.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_mode': 'dark',
      });

      await _pumpAjustes(tester);

      expect(_paletaViva(tester).isDark, isTrue);
      expect(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.dark)),
        findsOneWidget,
      );
    });

    testWidgets('un valor corrupto no rompe la app: cae en Automático', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appearance_mode': 'sepia',
      });

      await _pumpAjustes(tester, sistema: Brightness.dark);

      // «Automático» con el sistema en oscuro ⇒ oscuro. Si `fromStorage`
      // cayera en `light` en vez de en `system`, esto lo delata.
      expect(_paletaViva(tester).isDark, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // LA PUERTA DE ENTRADA Y LOS AFFORDANCES — precedente 7 de `flutter-ui`
  // ══════════════════════════════════════════════════════════════════════════
  group('la forma del ajuste', () {
    testWidgets('solo UNA opción se anuncia seleccionada, y son excluyentes', (
      WidgetTester tester,
    ) async {
      await _pumpAjustes(tester);

      final SemanticsHandle handle = tester.ensureSemantics();

      // Se afirma sobre cada fila con `isSemantics`, que es la API pública
      // para esto: leer los flags a mano obliga a pasar por
      // `SemanticsData.hasFlag`, que está deprecado, y su sustituto expone un
      // tri-estado cuyo tipo no está exportado.
      for (final AppearanceMode m in AppearanceMode.values) {
        expect(
          tester.getSemantics(find.byKey(AppearanceSection.optionKey(m))),
          isSemantics(
            isButton: true,
            isInMutuallyExclusiveGroup: true,
            // Solo «Automático» está activo de fábrica. Que las otras dos se
            // anuncien explícitamente NO seleccionadas es la mitad que importa:
            // sin ella, tres filas «seleccionadas» pasarían el test.
            isSelected: m == AppearanceMode.system,
          ),
          reason: 'la fila de ${m.label}',
        );
      }

      // `dispose` aquí y no en un `addTearDown`: el arnés comprueba que no
      // queden handles vivos ANTES de correr los teardowns.
      handle.dispose();
    });

    testWidgets('la selección no se distingue SOLO por color (WCAG 1.4.1)', (
      WidgetTester tester,
    ) async {
      await _pumpAjustes(tester);

      // Exactamente una marca de verificación, la de la opción activa.
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      await tester.tap(
        find.byKey(AppearanceSection.optionKey(AppearanceMode.dark)),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(AppearanceSection.optionKey(AppearanceMode.dark)),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // LA PALETA CUMPLE AA — los números de la tabla de `AppColorsDark`
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Sin esto la tabla de contraste de `app_colors.dart` es prosa: alguien
  // ajusta un tono «un poco» y nadie se entera hasta que un usuario no puede
  // leer la app. Aquí los ratios se recalculan.
  group('contraste WCAG', () {
    for (final GraspPalette p in <GraspPalette>[
      GraspPalette.light,
      GraspPalette.dark,
    ]) {
      final String tema = p.isDark ? 'oscuro' : 'claro';

      test('$tema — el texto cumple AA (4.5:1) sobre fondo y sobre tarjeta', () {
        for (final Color fondo in <Color>[p.canvas, p.surface]) {
          expect(
            _ratio(p.textPrimary, fondo),
            greaterThanOrEqualTo(4.5),
            reason: 'textPrimary sobre $fondo en tema $tema',
          );
          expect(
            _ratio(p.textSecondary, fondo),
            greaterThanOrEqualTo(4.5),
            reason: 'textSecondary sobre $fondo en tema $tema',
          );
          expect(
            _ratio(p.textMuted, fondo),
            greaterThanOrEqualTo(4.5),
            reason: 'textMuted sobre $fondo en tema $tema',
          );
        }
      });

      test('$tema — la etiqueta cumple AA sobre el relleno de marca', () {
        // El par que se invierte entre temas: relleno oscuro + etiqueta clara
        // en claro, relleno claro + etiqueta oscura en oscuro. Es el que lleva
        // TEXTO (los CTAs), así que va a 4.5.
        expect(_ratio(p.onBrand, p.brandStrong), greaterThanOrEqualTo(4.5));
        // Sobre `brand` solo se pintan ICONOS —el botón de chat de Conectar,
        // la cámara del avatar, el pulgar del interruptor—, nunca una etiqueta.
        // Ese es el 3:1 de WCAG 1.4.11, y es el motivo documentado en
        // `AppColors` de que el CTA sea un degradado y no un relleno plano de
        // `purple500`: en claro esto da 4.23 y no llegaría a 4.5.
        expect(_ratio(p.onBrand, p.brand), greaterThanOrEqualTo(3.0));
        // Y sobre el error, que es donde vive la insignia de no leídos: eso sí
        // es texto.
        expect(_ratio(p.onBrand, p.error), greaterThanOrEqualTo(4.5));
      });

      test('$tema — enlaces y estados semánticos cumplen AA', () {
        for (final Color fondo in <Color>[p.canvas, p.surface]) {
          expect(_ratio(p.brandStrong, fondo), greaterThanOrEqualTo(4.5));
          expect(_ratio(p.error, fondo), greaterThanOrEqualTo(4.5));
          expect(_ratio(p.success, fondo), greaterThanOrEqualTo(4.5));
        }
      });

      test('$tema — la iconografía cumple el 3:1 de componentes', () {
        // `brand` sí: es el borde de foco de un campo y la barra de progreso,
        // que son componentes de interfaz. `iconSoft` NO se comprueba a
        // propósito — en claro da 2.46 y solo pinta adorno (las hojas de la
        // escena, el icono de un campo ya etiquetado, un filete de 3 px junto
        // a un texto que ya se lee). WCAG 1.4.11 exime lo decorativo, y bajar
        // el listón para que «pase» sería mentir en la otra dirección.
        expect(_ratio(p.brand, p.canvas), greaterThanOrEqualTo(3.0));
        // El avatar de iniciales: `chip` es un RELLENO y no tiene que cumplir
        // nada contra el fondo, pero lo que se pinta encima sí contra él.
        expect(_ratio(p.textPrimary, p.chip), greaterThanOrEqualTo(4.5));
        // Lo mismo con `containerSubtle`, que es el otro relleno con TEXTO
        // encima: los chips no interactivos de una tarjeta, el marcador de
        // avatar sin foto y la burbuja `+N` de la cadena de la sala. Faltaba, y
        // se añadió al estrenarla (Fase 5, Tarea 7).
        expect(
          _ratio(p.textPrimary, p.containerSubtle),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}

/// Ratio de contraste WCAG 2.1 entre dos colores opacos.
double _ratio(Color a, Color b) {
  final double la = _luminancia(a);
  final double lb = _luminancia(b);
  final double alto = la > lb ? la : lb;
  final double bajo = la > lb ? lb : la;
  return (alto + 0.05) / (bajo + 0.05);
}

double _luminancia(Color c) {
  double canal(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
}
