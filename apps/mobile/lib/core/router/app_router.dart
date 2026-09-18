import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/supabase/supabase_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/start_screen.dart';
import '../../features/connect/presentation/connect_screen.dart';
import '../../features/legal/presentation/terms_screen.dart';
import '../../features/messages/application/conversation_controller.dart';
import '../../features/messages/presentation/conversation_screen.dart';
import '../../features/messages/presentation/messages_screen.dart';
import '../../features/navigation/presentation/app_shell_screen.dart';
import '../../features/onboarding/presentation/onboarding_feed_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/rooms/presentation/rooms_screen.dart';

/// Rutas de la app. Constantes con nombre para que un cambio de path no obligue
/// a buscar strings sueltos por todo el proyecto.
abstract final class AppRoute {
  const AppRoute._();

  static const String start = '/';
  static const String login = '/login';
  static const String register = '/register';

  /// Términos de Uso. Pública a propósito: se lee **antes** de tener cuenta,
  /// desde el propio formulario de registro.
  static const String terms = '/terms';

  /// Primera pestaña de la barra inferior y **destino de aterrizaje tras
  /// iniciar sesión** (§5) — `06-messaging-inbox.jpeg`.
  ///
  /// Sustituye a la antigua `/home`, que era el placeholder de mensajería.
  static const String messages = '/messages';

  /// Segunda pestaña — §6. Ocupa el sitio de la antigua segunda pestaña, que
  /// estaba inerte desde el Bloque 2 (ni siquiera era una rama del shell).
  static const String connect = '/connect';

  /// Tercera pestaña — la lista de salas activas (Fase 5 §6.1, ADR 0032). Fue un placeholder
  /// «Próximamente» durante toda la Fase 4.
  static const String rooms = '/rooms';

  /// Las 5 preguntas de bienvenida — `02-onboarding-questions.jpeg`.
  static const String onboarding = '/onboarding';

  /// Cuarta pestaña de la barra inferior — `08-profile.jpeg`.
  static const String profile = '/profile';

  /// La conversación del §9.
  ///
  /// **Fuera del `StatefulShellRoute` a propósito.** Se apila por encima de la barra inferior, que
  /// desaparece: un chat abierto no es una de las cuatro pestañas, es un sitio del que se vuelve, y
  /// mantener la barra invitaría a cambiar de pestaña dejando el hilo a medias. Por eso también
  /// devuelve un valor al cerrarse (ver [ConversationScreen]).
  ///
  /// No lleva el id en el path porque hay **dos** formas de entrar y solo una tiene conversación:
  /// desde Conectar (`RN-39`) todavía no existe. Lo que viaja es un `ConversationArgs` por `extra`,
  /// que las cubre las dos. El precio es que este destino no es enlazable ni sobrevive a un
  /// reinicio en frío — y con `extra` nulo se manda a Mensajes en vez de pintar un hilo de nadie.
  static const String conversation = '/conversation';

  static const Set<String> _publicRoutes = <String>{
    start,
    login,
    register,
    terms,
  };

  static bool isPublic(String location) => _publicRoutes.contains(location);
}

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final _AuthRefreshNotifier refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(
    refresh.dispose,
  ); //limpia recursos cuando el provider se elimina

  return GoRouter(
    initialLocation: AppRoute.start,
    refreshListenable: refresh,
    debugLogDiagnostics: kDebugMode,
    redirect: (BuildContext context, GoRouterState state) {
      // Mientras la sesión aún se está restaurando no redirigimos: hacerlo
      // provocaría un parpadeo de la pantalla de bienvenida en cada arranque.
      final AsyncValue<String?> auth = ref.read(authStateProvider);
      if (auth.isLoading && !auth.hasValue) return null;

      final bool isSignedIn = auth.valueOrNull != null;
      final String location = state.matchedLocation;

      if (isSignedIn && AppRoute.isPublic(location)) return AppRoute.messages;
      if (!isSignedIn && !AppRoute.isPublic(location)) return AppRoute.start;
      if (!isSignedIn) return null;

      // Onboarding obligatorio tras el alta: mientras
      // `hasCompletedOnboardingProvider` no tenga valor (todavía consultando
      // `onboarding_responses`) no se redirige — evita un salto a /onboarding
      // seguido de otro de vuelta si el usuario sí lo había completado.
      final AsyncValue<bool> onboarding = ref.read(
        hasCompletedOnboardingProvider,
      );
      if (onboarding.isLoading && !onboarding.hasValue) return null;

      // Fallo de red al comprobar el estado: se deja pasar (`true`) en vez de
      // atrapar al usuario en /onboarding por un fallo transitorio ajeno al
      // cuestionario en sí.
      final bool hasCompletedOnboarding = onboarding.valueOrNull ?? true;

      if (!hasCompletedOnboarding && location != AppRoute.onboarding) {
        return AppRoute.onboarding;
      }
      if (hasCompletedOnboarding && location == AppRoute.onboarding) {
        return AppRoute.messages;
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoute.start,
        name: 'start',
        builder: (BuildContext context, GoRouterState state) =>
            const StartScreen(),
      ),
      GoRoute(
        path: AppRoute.login,
        name: 'login',
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),
      GoRoute(
        path: AppRoute.register,
        name: 'register',
        builder: (BuildContext context, GoRouterState state) =>
            const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoute.terms,
        name: 'terms',
        builder: (BuildContext context, GoRouterState state) =>
            const TermsScreen(),
      ),
      GoRoute(
        path: AppRoute.onboarding,
        name: 'onboarding',
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingFeedScreen(),
      ),
      GoRoute(
        path: AppRoute.conversation,
        name: 'conversation',
        builder: (BuildContext context, GoRouterState state) {
          final Object? extra = state.extra;
          if (extra is ConversationArgs) {
            return ConversationScreen(args: extra);
          }
          // Sin `extra` no hay con quién hablar. Pasa al volver de un reinicio en frío con la ruta
          // restaurada: se manda a la bandeja en vez de pintar una conversación de nadie.
          return const MessagesScreen();
        },
      ),
      // Barra inferior: las CUATRO son ramas propias, cada una con su
      // `Navigator`, así que conservan scroll y estado al cambiar de pestaña.
      //
      // Hasta la Tarea 18 solo había dos ramas (Inicio y Perfil) y los otros
      // dos destinos se pintaban deshabilitados, sin ruta detrás. Eso obligaba
      // a mapear 2 ramas sobre 4 posiciones en `AppShellScreen`; con cuatro
      // ramas reales el índice de la barra **es** el índice del shell y ese
      // mapeo desaparece.
      //
      // El orden es el del §5 y no es cosmético: `Mensajes` va primero porque
      // es el destino de aterrizaje tras iniciar sesión.
      StatefulShellRoute.indexedStack(
        builder:
            (
              BuildContext context,
              GoRouterState state,
              StatefulNavigationShell navigationShell,
            ) => AppShellScreen(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.messages,
                name: 'messages',
                builder: (BuildContext context, GoRouterState state) =>
                    const MessagesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.connect,
                name: 'connect',
                builder: (BuildContext context, GoRouterState state) =>
                    const ConnectScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.rooms,
                name: 'rooms',
                builder: (BuildContext context, GoRouterState state) =>
                    const RoomsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoute.profile,
                name: 'profile',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Puente entre el `StreamProvider` de sesión y el `refreshListenable` de
/// go_router, que espera un `Listenable` clásico.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _authSubscription = ref.listen<AsyncValue<String?>>(
      authStateProvider,
      (AsyncValue<String?>? previous, AsyncValue<String?> next) =>
          notifyListeners(),
      fireImmediately: true,
    );
    // Sin esto, el redirect solo se reevalúa cuando cambia la sesión: la
    // primera vez que `hasCompletedOnboardingProvider` pasa de "cargando" a
    // "con valor" (justo después del login) no dispararía una nueva pasada
    // del redirect, y el usuario se quedaría en /home aunque le tocara
    // /onboarding.
    _onboardingSubscription = ref.listen<AsyncValue<bool>>(
      hasCompletedOnboardingProvider,
      (AsyncValue<bool>? previous, AsyncValue<bool> next) => notifyListeners(),
    );
  }

  late final ProviderSubscription<AsyncValue<String?>> _authSubscription;
  late final ProviderSubscription<AsyncValue<bool>> _onboardingSubscription;

  @override
  void dispose() {
    _authSubscription.close();
    _onboardingSubscription.close();
    super.dispose();
  }
}
