import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/profile/profile.dart';
import '../../domain/profile/profile_badge.dart';
import '../../domain/profile/profile_repository.dart';
import '../../domain/social/social_failure.dart';
import '../social/social_edge_call.dart';
import '../social/social_error_mapper.dart';
import 'profile_mapper.dart';

/// Implementación de [ProfileRepository] sobre `profiles` / `profiles_private`
/// / `onboarding_responses` / `badges` / `user_badges`.
///
/// Todas las lecturas son directas contra Postgres (RLS ya las autoriza, ver
/// las migraciones de Bloque 1 y 2): no hace falta una Edge Function para
/// leer el propio perfil. La escritura sí pasa por `profile-update`
/// (columnas editables limitadas por `grant update (...)`, ver la migración
/// `20260809120000_...`), nunca por un `update()` directo del cliente.
class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('No hay sesión activa: no se puede leer el perfil.');
    }
    return id;
  }

  @override
  Future<Profile> fetchOwn() async {
    final String userId = _userId;

    final Map<String, dynamic> publicRow = await _client
        .from('profiles')
        .select(profilePublicColumns)
        .eq('user_id', userId)
        .single();

    // `profiles_private` puede no tener fila si el trigger de alta aún no
    // corrió (no debería pasar tras login, pero se evita un 500 con `maybe`).
    final Map<String, dynamic>? privateRow = await _client
        .from('profiles_private')
        .select('birth_date, gender, country, hide_activity_status')
        .eq('user_id', userId)
        .maybeSingle();

    // `onboarding_responses` es opcional a propósito: un usuario que aún no
    // ha completado el cuestionario (no debería llegar aquí, el router lo
    // redirige a /onboarding, pero el repositorio no depende de eso) no tiene
    // fila.
    final Map<String, dynamic>? onboardingRow = await _client
        .from('onboarding_responses')
        .select('responses')
        .eq('user_id', userId)
        .maybeSingle();

    return mapProfileRows(
      userId: userId,
      publicRow: publicRow,
      privateRow: privateRow,
      onboardingRow: onboardingRow,
      badges: await _fetchBadges(userId),
    );
  }

  Future<List<ProfileBadge>> _fetchBadges(String userId) async {
    final List<Map<String, dynamic>> catalog = List<Map<String, dynamic>>.from(
      await _client
          .from('badges')
          .select('slug, name, description, icon')
          .order('sort_order'),
    );

    final List<Map<String, dynamic>> earnedRows =
        List<Map<String, dynamic>>.from(
          await _client
              .from('user_badges')
              .select('badges(slug)')
              .eq('user_id', userId),
        );
    final Set<String> earnedSlugs = <String>{
      for (final Map<String, dynamic> row in earnedRows)
        if (row['badges'] is Map && (row['badges'] as Map)['slug'] is String)
          (row['badges'] as Map)['slug'] as String,
    };

    return <ProfileBadge>[
      for (final Map<String, dynamic> row in catalog)
        ProfileBadge(
          slug: row['slug'] as String,
          name: row['name'] as String,
          description: row['description'] as String?,
          icon: row['icon'] as String?,
          earned: earnedSlugs.contains(row['slug'] as String),
        ),
    ];
  }

  @override
  Future<void> updateProfile({
    String? displayName,
    DateTime? birthDate,
    String? gender,
    String? country,
  }) async {
    final String? birthDateIso = birthDate == null ? null : _isoDate(birthDate);
    final Map<String, dynamic> body = <String, dynamic>{
      'display_name': ?displayName,
      'birth_date': ?birthDateIso,
      'gender': ?gender,
      'country': ?country,
    };
    if (body.isEmpty) return;

    final FunctionResponse response = await _client.functions.invoke(
      'profile-update',
      method: HttpMethod.patch,
      body: body,
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError('No se pudo actualizar el perfil (${response.status}).');
    }
  }

  /// La bio va **directa** por PostgREST, no por `profile-update`.
  ///
  /// `profile-update` no acepta `bio`: mandársela es un 400 por campo desconocido. Y no le hace
  /// falta — `authenticated` tiene `grant update (bio)` sobre `profiles`, la policy acota la fila a
  /// la propia, y el tope de 160 lo impone `profiles_bio_length_chk` **en la base**. Se recorta
  /// aquí y se manda `null` si queda vacía, porque la constraint exige 1-160 **o nulo**: mandar la
  /// cadena vacía sería un 400 de la base, no un borrado.
  @override
  Future<void> updateBio(String? bio) async {
    final String recortada = (bio ?? '').trim();
    try {
      await _client
          .from('profiles')
          .update(<String, dynamic>{'bio': recortada.isEmpty ? null : recortada})
          .eq('user_id', _userId);
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }

  @override
  Future<void> setHideActivityStatus(bool hidden) async {
    try {
      await _client
          .from('profiles_private')
          .update(<String, dynamic>{'hide_activity_status': hidden})
          .eq('user_id', _userId);
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }

  /// `profile-tag-rotate` (§6.2, decisión 5), con su 422 **retraducido**.
  ///
  /// ## Por qué se retraduce, y no es un capricho
  ///
  /// El código `rate_limited` lo emiten **dos** funciones —ésta y `follow-toggle`, vía
  /// `_shared/follow.ts`— con la misma forma de `details` (`limit`, `window_hours`, `retry_at`), así
  /// que `SocialFailure.fromResponse` **no puede distinguirlas por el cuerpo** y resuelve a favor de
  /// la de follows: *«Has enviado N solicitudes de seguimiento…»*. Dejarlo pasar diría, al topar el
  /// cupo del tag, que se enviaron solicitudes que nadie envió — un límite mal nombrado es un fallo
  /// mudo con otra ropa, y `RN-21` obliga a decir **cuál** es el límite y **cuándo** se recupera.
  ///
  /// Quien sabe a qué función se llamó es este método, así que aquí se arregla. Se conservan `limit`
  /// y `retryAt` tal cual venían: lo único que cambia es el texto que lee una persona.
  @override
  Future<TagRotation> rotateTag() async {
    try {
      final Map<String, dynamic> data = await invokeEdge(
        _client,
        'profile-tag-rotate',
      );
      final String? tag = data['tag'] as String?;
      if (tag == null || tag.isEmpty) {
        throw const SocialFailure(
          SocialFailureKind.unknown,
          'El tag se pudo haber cambiado, pero no se recibió confirmación.',
          rawCode: 'tag_rotate_sin_tag',
        );
      }
      final Object? next = data['next_rotation_at'];
      return TagRotation(
        tag: tag,
        nextRotationAt: next is String
            ? DateTime.tryParse(next)?.toLocal()
            : null,
      );
    } on SocialFailure catch (failure) {
      if (failure.kind != SocialFailureKind.limitReached) rethrow;
      throw SocialFailure(
        SocialFailureKind.limitReached,
        'Solo puedes cambiar tu tag una vez cada 24 horas. '
        '${_cuandoSePodra(failure.retryAt)}',
        rawCode: failure.rawCode,
        limit: failure.limit,
        retryAt: failure.retryAt,
      );
    }
  }

  /// Sin `retry_at` **no se inventa una hora**: se dice que hay que esperar, que es lo único que se
  /// sabe. Una hora inventada es peor que ninguna.
  static String _cuandoSePodra(DateTime? retryAt) {
    if (retryAt == null) return 'Inténtalo de nuevo más tarde.';
    final DateTime local = retryAt.toLocal();
    final String dos = local.hour.toString().padLeft(2, '0');
    final String min = local.minute.toString().padLeft(2, '0');
    return 'Podrás volver a cambiarlo a partir de las $dos:$min.';
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
