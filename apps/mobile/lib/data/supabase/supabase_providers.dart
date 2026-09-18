import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/account/account_repository.dart';
import '../../domain/auth/auth_repository.dart';
import '../../domain/onboarding/onboarding_catalogs_repository.dart';
import '../../domain/onboarding/onboarding_repository.dart';
import '../../domain/profile/avatar_repository.dart';
import '../../domain/profile/image_compressor.dart';
import '../../domain/profile/profile_repository.dart';
import '../../domain/rooms/rooms_repository.dart';
import '../../domain/social/activity_repository.dart';
import '../../domain/social/connect_repository.dart';
import '../../domain/social/follow_repository.dart';
import '../../domain/social/messaging_repository.dart';
import '../../domain/social/moderation_repository.dart';
import '../../domain/social/public_profile.dart';
import '../account/supabase_account_repository.dart';
import '../auth/supabase_auth_repository.dart';
import '../onboarding/supabase_onboarding_catalogs_repository.dart';
import '../onboarding/supabase_onboarding_repository.dart';
import '../profile/flutter_image_compressor.dart';
import '../profile/supabase_avatar_repository.dart';
import '../profile/supabase_profile_repository.dart';
import '../rooms/supabase_rooms_repository.dart';
import '../social/supabase_activity_repository.dart';
import '../social/supabase_connect_repository.dart';
import '../social/supabase_follow_repository.dart';
import '../social/supabase_messaging_repository.dart';
import '../social/supabase_moderation_repository.dart';
import '../social/supabase_public_profile_repository.dart';

/// Cliente de Supabase ya inicializado en `main()`.
///
/// Ninguna pantalla lo consume directamente: se inyecta en los repositorios.
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((Ref ref) => Supabase.instance.client);

/// Repositorio de autenticación. Se sobreescribe en tests con un doble.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
    );

/// `userId` del usuario autenticado, o `null`. Es la fuente de verdad que usa
/// el router para redirigir.
final StreamProvider<String?> authStateProvider = StreamProvider<String?>((
  Ref ref,
) {
  final AuthRepository repository = ref.watch(authRepositoryProvider);
  return repository
      .authStateChanges()
      .distinct(); //.distinct() avisa solo si cambió
});

/// Repositorio de onboarding. Habla con la Edge Function `onboarding-complete`.
final Provider<OnboardingRepository> onboardingRepositoryProvider =
    Provider<OnboardingRepository>(
      (Ref ref) =>
          SupabaseOnboardingRepository(ref.watch(supabaseClientProvider)),
    );

/// Repositorio de perfil propio (`profiles`/`profiles_private`).
final Provider<ProfileRepository> profileRepositoryProvider =
    Provider<ProfileRepository>(
      (Ref ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
    );

/// Repositorio del avatar. Habla con las tres Edge Functions de foto de perfil.
///
/// Va aparte de [profileRepositoryProvider] porque el avatar no se escribe con `profile-update`
/// sino con `profile-avatar-set`, la única dueña del invariante "una foto o un dibujo".
final Provider<AvatarRepository> avatarRepositoryProvider =
    Provider<AvatarRepository>(
      (Ref ref) => SupabaseAvatarRepository(ref.watch(supabaseClientProvider)),
    );

/// Repositorio de borrado de cuenta. Habla con la Edge Function `account-delete`.
///
/// Va aparte de [profileRepositoryProvider] y [authRepositoryProvider] por la misma razón que
/// [avatarRepositoryProvider]: es la única dueña de un invariante propio (reautenticación por
/// contraseña + frase de confirmación antes de disparar la cascada RGPD, ver
/// `domain/account/account_repository.dart`).
final Provider<AccountRepository> accountRepositoryProvider =
    Provider<AccountRepository>(
      (Ref ref) => SupabaseAccountRepository(ref.watch(supabaseClientProvider)),
    );

// =================================================================================================
// CAPA SOCIAL (Fase 4) — contactos, mensajería y Conectar
//
// Los cinco van por separado y no en un `SocialRepository` único por la misma razón que
// [avatarRepositoryProvider] va aparte de [profileRepositoryProvider]: cada uno es dueño de un
// invariante propio, y juntarlos invitaría a escribir por el camino equivocado. El caso más claro
// es [moderationRepositoryProvider], que expone `block`, `report`, `unblock` y `blockedUsers`: las
// tres primeras pasan por Edge Function, y la cuarta va por PostgREST directo (ADR 0027).
// =================================================================================================

/// Mensajería directa (§8 y §9). Habla con las seis Edge Functions de `messaging-*`.
///
/// Casi todo pasa por función y no por PostgREST porque `conversations` **no tiene ni un `grant`**
/// para `authenticated`: es lo que hace estructural la invisibilidad de `status = 'ignored'`
/// (`RN-06`) y del `initiator_id`.
final Provider<MessagingRepository> messagingRepositoryProvider =
    Provider<MessagingRepository>(
      (Ref ref) =>
          SupabaseMessagingRepository(ref.watch(supabaseClientProvider)),
    );

/// Seguimientos (§6.2). Escrituras por `follow-toggle`, lecturas por PostgREST sobre
/// `user_follows` con el perfil incrustado.
final Provider<FollowRepository> followRepositoryProvider =
    Provider<FollowRepository>(
      (Ref ref) => SupabaseFollowRepository(ref.watch(supabaseClientProvider)),
    );

/// El perfil ajeno (`RN-38`, §6.2).
///
/// Va aparte de [profileRepositoryProvider], que es el del perfil **propio**: son dos superficies
/// de datos distintas y con permisos distintos. El propio lee `profiles_private` y las respuestas
/// del onboarding; el ajeno lee la vista `public_profiles`, que enumera lo que publica y no deja
/// pasar nada del Art. 9 (ADR 0020) ni la fecha de nacimiento (ADR 0025). Un único repositorio con
/// un booleano «¿es mío?» dentro haría representable pedir el privado de otra persona.
final Provider<PublicProfileRepository> publicProfileRepositoryProvider =
    Provider<PublicProfileRepository>(
      (Ref ref) =>
          SupabasePublicProfileRepository(ref.watch(supabaseClientProvider)),
    );

/// Pantalla Conectar (§6): el feed puntuado y la búsqueda por tag exacto.
///
/// El scoring lee datos del Art. 9 RGPD **dentro** de `connect-feed` y devuelve un número; ni un
/// slug de categoría cruza hacia el cliente (ADR 0020).
final Provider<ConnectRepository> connectRepositoryProvider =
    Provider<ConnectRepository>(
      (Ref ref) => SupabaseConnectRepository(ref.watch(supabaseClientProvider)),
    );

/// Bloqueo y reporte (`RN-22` a `RN-25`), y desde el ADR 0027 también desbloqueo.
///
/// `block` y `report` pasan por Edge Function porque `blocks` no tiene policy de escritura;
/// `unblock` también, porque tampoco concede `delete`. `blockedUsers` va por PostgREST directo:
/// su RLS y su `grant` de `select` ya existían.
final Provider<ModerationRepository> moderationRepositoryProvider =
    Provider<ModerationRepository>(
      (Ref ref) =>
          SupabaseModerationRepository(ref.watch(supabaseClientProvider)),
    );

/// Punto de actividad (`RN-30`, `RN-32`), sobre los RPC `touch_last_seen` y `activity_status`.
///
/// Devuelve booleanos y **nunca** una marca de tiempo: `last_seen_at` vive en `profiles_private`
/// justo para que no salga de la base.
final Provider<ActivityRepository> activityRepositoryProvider =
    Provider<ActivityRepository>(
      (Ref ref) => SupabaseActivityRepository(ref.watch(supabaseClientProvider)),
    );

/// Lista de salas activas y catálogo de temas (Fase 5, §6.1).
///
/// Solo lectura, y va aparte por eso: escribir el estado de una sala es `room-actions`, dueña del
/// aforo y del tope de hablantes. Juntarlos invitaría a decidir en el cliente quién cabe, que es
/// justo lo que la Sección 5 del documento maestro prohíbe.
final Provider<RoomsRepository> roomsRepositoryProvider =
    Provider<RoomsRepository>(
      (Ref ref) => SupabaseRoomsRepository(ref.watch(supabaseClientProvider)),
    );

/// Compresor de imágenes de la plataforma.
///
/// Es el único punto del árbol que toca un códec del sistema, y por eso se inyecta: los tests lo
/// sustituyen por un doble (ver `test/data/profile/avatar_upload_test.dart`).
final Provider<ImageCompressor> imageCompressorProvider =
    Provider<ImageCompressor>((Ref ref) => const FlutterImageCompressor());

/// Repositorio de catálogos de onboarding (`GET onboarding-catalogs`).
final Provider<OnboardingCatalogsRepository>
onboardingCatalogsRepositoryProvider = Provider<OnboardingCatalogsRepository>(
  (Ref ref) =>
      SupabaseOnboardingCatalogsRepository(ref.watch(supabaseClientProvider)),
);

/// `true` si el usuario autenticado ya completó el cuestionario de alta
/// (`onboarding_responses` tiene fila para su `user_id`).
///
/// Fuente de verdad del redirect `/onboarding` en `app_router.dart` — la
/// alternativa de guardar un `onboarding_completed` en `profiles` (Sección
/// "post-signup" del encargo) se descartó: hubiera exigido una migración y una
/// columna más que sincronizar, cuando `onboarding_responses` ya es esa
/// fuente de verdad (una fila por usuario, ver su migración). Se recalcula
/// solo cuando cambia `authStateProvider` (nuevo login/logout), no en cada
/// navegación.
final FutureProvider<bool> hasCompletedOnboardingProvider =
    FutureProvider<bool>((Ref ref) async {
      final String? userId = ref.watch(authStateProvider).valueOrNull;
      if (userId == null) return false;

      final SupabaseClient client = ref.watch(supabaseClientProvider);
      final Map<String, dynamic>? row = await client
          .from('onboarding_responses')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();
      return row != null;
    });
