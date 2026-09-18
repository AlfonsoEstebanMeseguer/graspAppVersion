import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/router/app_router.dart';
import 'core/theming/app_theme.dart';
import 'core/theming/grasp_palette.dart';
import 'data/preferences/appearance_store.dart';
import 'domain/settings/appearance_mode.dart';
import 'features/settings/application/appearance_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();
  Env.assertConfigured();

  await Supabase.initialize(
    //singleton
    url: Env.supabaseUrl,
    // Clave publicable (`sb_publishable_…`), acotada por RLS. Sustituye a la
    // antigua `anonKey`, ya deprecada en supabase_flutter.
    publishableKey: Env.supabaseAnonKey,
  );

  // El tema se lee **antes** del primer frame. Hacerlo con un `FutureProvider`
  // pintaría una pantalla clara durante un instante en cada arranque de quien
  // tiene el modo oscuro puesto, que es exactamente el momento en que un
  // fogonazo blanco molesta.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: <Override>[
        appearanceStoreProvider.overrideWithValue(AppearanceStore(prefs)),
      ],
      child: const GraspApp(),
    ),
  );
}

class GraspApp extends ConsumerWidget {
  const GraspApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);
    final AppearanceMode appearance = ref.watch(appearanceControllerProvider);

    return MaterialApp.router(
      title: 'Grasp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: appearance.themeMode,
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        // Acotamos el escalado de texto: por debajo de 1.0 se pierde
        // legibilidad y por encima de 1.4 los CTAs empiezan a romperse. Dentro
        // de ese rango la app respeta el ajuste del sistema.
        final MediaQueryData media = MediaQuery.of(context);
        return _SystemChrome(
          child: MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 1,
                maxScaleFactor: 1.4,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

/// Pinta las barras del sistema (estado y navegación) con el tema activo.
///
/// Va **dentro** del `MaterialApp` y no en `main()`, que es donde estaba: allí
/// era una llamada única con los colores del tema claro cableados, así que al
/// cambiar a oscuro la barra de navegación de Android se habría quedado en
/// `#F5F2FA` — una franja blanca bajo una app negra. Aquí se recalcula con cada
/// cambio de tema, incluido el que viene del sistema sin tocar la app.
///
/// `AnnotatedRegion` y no `SystemChrome.setSystemUIOverlayStyle` porque el
/// `AppBar` de cada pantalla publica su propio `systemOverlayStyle`: compiten,
/// y gana el último que se aplica. La región es lo que respeta esa jerarquía.
class _SystemChrome extends StatelessWidget {
  const _SystemChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GraspPalette palette = context.palette;
    final Brightness iconos = palette.isDark
        ? Brightness.light
        : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconos,
        // En iOS la propiedad significa el brillo del FONDO, no el de los
        // iconos: va invertida respecto a la de Android a propósito.
        statusBarBrightness: palette.brightness,
        systemNavigationBarColor: palette.canvas,
        systemNavigationBarIconBrightness: iconos,
      ),
      child: child,
    );
  }
}
