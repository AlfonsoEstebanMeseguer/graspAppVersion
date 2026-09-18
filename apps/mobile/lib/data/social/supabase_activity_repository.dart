import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/social/activity_repository.dart';
import '../../domain/social/social_failure.dart';
import 'social_error_mapper.dart';

/// [ActivityRepository] sobre los dos RPC de `20260823120300_activity_rpcs.sql`.
///
/// ## Por qué RPC y no una tabla
///
/// `profiles_private.last_seen_at` **no sale nunca de la base**: los dos RPC existen para que el
/// cliente reciba un **booleano** y jamás la marca de tiempo, ni derivados suyos («hace N minutos»,
/// la marca redondeada). Los dos son `security definer` porque `authenticated` no tiene `update`
/// sobre esa columna — ni debe tenerlo.
///
/// ## Ojo con quién llama
///
/// Los dos leen `auth.uid()`, así que **hay que llamarlos con el cliente del usuario**. Con
/// `service_role` —un JWT sin `sub`— devolverían la respuesta del anónimo (`false` para todos) **y
/// no darían error**, que es el fallo del punto 11 de la skill `edge-functions`. Aquí no puede
/// pasar porque este repositorio recibe el cliente de la app, pero conviene que quede escrito.
class SupabaseActivityRepository implements ActivityRepository {
  SupabaseActivityRepository(this._client);

  final SupabaseClient _client;

  /// El tope que impone el propio RPC: por encima **lanza excepción** en vez de truncar en
  /// silencio, porque devolver menos filas de las pedidas haría pintar puntos grises sin saber por
  /// qué.
  static const int maxIdsPorLlamada = 500;

  @override
  Future<void> heartbeat() async {
    try {
      // Sin parámetros: es la garantía de que nadie puede latir por otro ni elegir el instante.
      await _client.rpc<void>('touch_last_seen');
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }

  @override
  Future<Map<String, bool>> activeStatus(List<String> userIds) async {
    if (userIds.isEmpty) return const <String, bool>{};

    // Se comprueba aquí además de en el RPC. No es duplicar la regla por gusto: el RPC lanza una
    // excepción de Postgres, que llegaría a la pantalla como un error genérico y sin pista de qué
    // hacer. Cortarlo antes deja un mensaje que dice qué pasó — y quien pagina no llega nunca.
    if (userIds.length > maxIdsPorLlamada) {
      throw SocialFailure(
        SocialFailureKind.invalidInput,
        'No se pudo cargar el estado de actividad.',
        rawCode:
            'activity_status admite $maxIdsPorLlamada ids y se pidieron ${userIds.length}',
      );
    }

    try {
      final List<dynamic> rows = await _client.rpc<List<dynamic>>(
        'activity_status',
        params: <String, dynamic>{'p_user_ids': userIds},
      );

      return <String, bool>{
        for (final dynamic raw in rows)
          if (raw is Map && raw['user_id'] is String)
            raw['user_id'] as String: raw['is_active'] == true,
      };
    } on Object catch (error) {
      throw mapSocialError(error);
    }
  }
}
