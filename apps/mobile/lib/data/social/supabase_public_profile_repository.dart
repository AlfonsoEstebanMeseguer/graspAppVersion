import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/profile/profile_badge.dart';
import '../../domain/social/follow_edge.dart';
import '../../domain/social/public_profile.dart';
import 'social_error_mapper.dart';

/// [PublicProfileRepository] sobre PostgREST directo. **No hay Edge Function detrás.**
///
/// Todo lo que el §6.2 pide es legible por `authenticated` —comprobado contra
/// `information_schema.column_privileges` y `pg_policies`, no deducido de las migraciones
/// (`rls-security`, punto 11)—:
///
/// | Qué | De dónde | Qué lo autoriza |
/// |---|---|---|
/// | nombre, tag, bio, nivel, contadores | `public_profiles` | la vista, con `grant select` |
/// | **edad** | `public_profiles.age` | la vista la deriva de `birth_date` (ADR 0025) |
/// | insignia destacada | `user_badges` + `badges` | dos policies con `qual = true` |
/// | mi relación con esa persona | `user_follows` | `user_follows_read_own_or_accepted` |
class SupabasePublicProfileRepository implements PublicProfileRepository {
  SupabasePublicProfileRepository(this._client);

  final SupabaseClient _client;

  /// **Se enumeran una a una y no con `*`.**
  ///
  /// Aquí es doblemente deliberado: la vista ya enumera lo que publica, así que un `*` no filtraría
  /// nada hoy —pero ataría esta pantalla a que la vista nunca crezca, y la vista es justo el sitio
  /// donde alguien añadiría una columna «solo para una cosa». Se pide lo que se pinta.
  static const String _columns =
      'user_id, display_name, tag, bio, age, preset_avatar, photo_path, '
      'level, streak_days, time_helping_seconds, followers_count, following_count';

  @override
  Future<PublicProfile?> fetch(String userId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('public_profiles')
          .select(_columns)
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;

      return PublicProfile.fromJson(row, featuredBadge: await _destacada(userId));
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }

  /// La insignia **destacada**: la última ganada.
  ///
  /// «Destacada» no es una columna que nadie elija —`user_badges` no tiene tal cosa— sino la más
  /// reciente por `earned_at`. Se resuelve aquí y no en la pantalla para no traerse el catálogo
  /// entero de insignias sólo para enseñar una, que es lo que hace `fetchOwn` porque el perfil
  /// propio sí las pinta todas.
  ///
  /// **Un fallo aquí no tumba la ficha**: se devuelve `null` y el perfil se pinta sin insignia. Es
  /// un adorno, y perderlo no puede costar la pantalla entera.
  Future<ProfileBadge?> _destacada(String userId) async {
    try {
      final Map<String, dynamic>? row = await _client
          .from('user_badges')
          .select('earned_at, badges(slug, name, description, icon)')
          .eq('user_id', userId)
          .order('earned_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final Object? badge = row?['badges'];
      if (badge is! Map) return null;
      final Object? slug = badge['slug'];
      final Object? name = badge['name'];
      if (slug is! String || name is! String) return null;

      return ProfileBadge(
        slug: slug,
        name: name,
        description: badge['description'] as String?,
        icon: badge['icon'] as String?,
        // Está en `user_badges`, así que por construcción está ganada.
        earned: true,
      );
    } on Object {
      return null;
    }
  }

  /// Mi relación con [userId], leída de `user_follows`.
  ///
  /// **Sólo la dirección yo → él**: `followee_id = userId` y `follower_id = yo`. La otra dirección
  /// es que esa persona me siga a mí, que es otra cosa y no cambia el botón — confundirlas haría
  /// que el perfil de un seguidor mío dijera `Siguiendo` sin que yo lo siga.
  ///
  /// `status` guarda `pending` o `accepted`; [FollowState.fromWire] traduce el segundo, que es el
  /// literal de la columna y no el de `connect-tag-lookup`.
  @override
  Future<FollowState> followState(String userId) async {
    final String? me = _client.auth.currentUser?.id;
    if (me == null) return FollowState.none;

    try {
      final Map<String, dynamic>? row = await _client
          .from('user_follows')
          .select('status')
          .eq('follower_id', me)
          .eq('followee_id', userId)
          .maybeSingle();

      // Sin fila no hay relación, que es exactamente [FollowState.none] — no un error.
      if (row == null) return FollowState.none;
      return FollowState.fromWire(row['status'] as String?);
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }
}
