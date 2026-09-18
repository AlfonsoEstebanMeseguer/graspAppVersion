import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/social/blocked_user.dart';
import '../../domain/social/moderation_repository.dart';
import 'social_edge_call.dart';
import 'social_error_mapper.dart';

/// [ModerationRepository] sobre Supabase.
///
/// Las dos operaciones pasan por Edge Function porque **bloquear no es insertar una fila**: tiene
/// efectos en otra tabla (`conversations.hidden` del lado del bloqueador) y el cliente no puede
/// dejarlos a medias. `blocks` no tiene policy de escritura.
///
/// **Desbloquear (`block-remove`) también pasa por Edge Function**: `blocks` no concede `delete` a
/// `authenticated`, solo a `service_role`. **Leer la lista, en cambio, va por PostgREST directo**:
/// su RLS y su `grant` de `select` ya existen, y el perfil se incrusta por la clave ajena
/// `blocks_blocked_id_fkey`.
class SupabaseModerationRepository implements ModerationRepository {
  SupabaseModerationRepository(this._client);

  final SupabaseClient _client;

  /// Las columnas del perfil incrustado.
  ///
  /// **Se enumeran una a una y no con `*`**, por lo mismo que en `SupabaseFollowRepository`:
  /// `grant select on public.profiles` es de TABLA, así que cualquier columna nueva entraría sola
  /// en la respuesta. Pedir solo lo que se pinta es lo que hace que añadir una columna al perfil no
  /// filtre nada por esta vía.
  static const String _profileColumns =
      'user_id, display_name, tag, preset_avatar, photo_path';

  @override
  Future<void> block(String userId) async {
    await invokeEdge(
      _client,
      'block-create',
      body: <String, dynamic>{'target_id': userId},
    );
  }

  @override
  Future<void> report(String userId, {String? conversationId}) async {
    await invokeEdge(
      _client,
      'report-create',
      body: <String, dynamic>{
        'reported_id': userId,
        // Si viaja, el backend comprueba que la conversación sea de quien reporta (404 si no).
        // Sin esa comprobación cualquiera podría colgar su reporte de la conversación de dos
        // desconocidos, y ese enlace es justo lo que un humano de la cola de moderación abriría.
        'conversation_id': ?conversationId,
      },
    );
  }

  @override
  Future<void> unblock(String userId) async {
    await invokeEdge(
      _client,
      'block-remove',
      body: <String, dynamic>{'target_id': userId},
    );
  }

  @override
  Future<List<BlockedUser>> blockedUsers() async {
    final String? me = _client.auth.currentUser?.id;
    if (me == null) return const <BlockedUser>[];

    try {
      // El nombre de la relación incrustada es el de la clave ajena. Aquí solo hay UNA hacia
      // `profiles` desde `blocks` en esta dirección, pero se nombra igualmente: hay dos claves
      // ajenas en la tabla y sin nombrarla PostgREST puede devolver `PGRST201` (ambigüedad).
      //
      // El `.eq('blocker_id', me)` es redundante con la RLS `blocks_read_own` y va a propósito: si
      // algún día esa policy se relajara, esta consulta seguiría trayendo solo lo tuyo.
      final List<Map<String, dynamic>> rows = await _client
          .from('blocks')
          .select(
            'created_at, '
            'blocked:profiles!blocks_blocked_id_fkey($_profileColumns)',
          )
          .eq('blocker_id', me)
          .order('created_at', ascending: false)
          .limit(100);

      return rows
          .map((Map<String, dynamic> row) {
            final Object? profile = row['blocked'];
            if (profile is! Map) return null;
            return BlockedUser.fromJson(row);
          })
          .whereType<BlockedUser>()
          .toList(growable: false);
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }
}
