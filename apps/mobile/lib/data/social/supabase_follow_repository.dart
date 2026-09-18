import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/social/follow_edge.dart';
import '../../domain/social/follow_repository.dart';
import 'social_edge_call.dart';
import 'social_error_mapper.dart';

/// [FollowRepository] sobre Supabase.
///
/// Las **escrituras** van por `follow-toggle` (`user_follows` no tiene ninguna policy de escritura,
/// y los contadores de `profiles` son territorio exclusivo del backend). Las **lecturas** van por
/// PostgREST directo con el perfil incrustado, que es para lo que las dos claves ajenas apuntan a
/// `profiles`.
class SupabaseFollowRepository implements FollowRepository {
  SupabaseFollowRepository(this._client);

  final SupabaseClient _client;

  /// Las columnas del perfil incrustado.
  ///
  /// **Se enumeran una a una y no con `*`**: `grant select on public.profiles` es de TABLA, así que
  /// cualquier columna nueva entraría sola en la respuesta. Pedir solo lo que se pinta es lo que
  /// hace que añadir una columna al perfil no filtre nada por esta vía.
  ///
  /// El nombre de la relación incrustada (`user_follows_follower_id_fkey`) es el de la clave ajena:
  /// hay **dos** hacia `profiles` desde esta tabla, así que sin nombrarla PostgREST no sabe cuál
  /// usar y devuelve `PGRST201` (ambigüedad).
  static const String _profileColumns =
      'user_id, display_name, tag, preset_avatar, photo_path';

  @override
  Future<List<FollowEdge>> followers(String userId) => _edges(
    embed: 'follower:profiles!user_follows_follower_id_fkey($_profileColumns)',
    filterColumn: 'followee_id',
    userId: userId,
    embedKey: 'follower',
  );

  @override
  Future<List<FollowEdge>> following(String userId) => _edges(
    embed: 'followee:profiles!user_follows_followee_id_fkey($_profileColumns)',
    filterColumn: 'follower_id',
    userId: userId,
    embedKey: 'followee',
  );

  Future<List<FollowEdge>> _edges({
    required String embed,
    required String filterColumn,
    required String userId,
    required String embedKey,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('user_follows')
          .select('status, created_at, $embed')
          .eq(filterColumn, userId)
          .eq('status', 'accepted')
          .order('created_at', ascending: false);

      return rows
          .map((Map<String, dynamic> row) {
            final Object? profile = row[embedKey];
            if (profile is! Map) return null;
            return FollowEdge(
              profile: SocialProfileRef.fromJson(
                Map<String, dynamic>.from(profile),
              ),
              status: FollowState.fromWire(row['status'] as String?),
              createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            );
          })
          .whereType<FollowEdge>()
          .toList(growable: false);
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }

  @override
  Future<List<FollowRequest>> pendingRequests() async {
    final String? me = _client.auth.currentUser?.id;
    if (me == null) return const <FollowRequest>[];

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('user_follows')
          .select(
            'created_at, '
            'follower:profiles!user_follows_follower_id_fkey($_profileColumns)',
          )
          .eq('followee_id', me)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return rows
          .map((Map<String, dynamic> row) {
            final Object? profile = row['follower'];
            if (profile is! Map) return null;
            return FollowRequest(
              profile: SocialProfileRef.fromJson(
                Map<String, dynamic>.from(profile),
              ),
              createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
            );
          })
          .whereType<FollowRequest>()
          .toList(growable: false);
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }

  @override
  Future<FollowToggleResult> toggle(
    FollowAction action,
    String targetId,
  ) async => FollowToggleResult.fromJson(
    await invokeEdge(
      _client,
      'follow-toggle',
      body: <String, dynamic>{
        'action': action.wireValue,
        'target_id': targetId,
      },
    ),
  );
}
