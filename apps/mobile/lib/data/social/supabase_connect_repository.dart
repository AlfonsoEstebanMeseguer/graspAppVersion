import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/social/connect_candidate.dart';
import '../../domain/social/connect_repository.dart';
import '../../domain/social/social_failure.dart';
import '../../domain/social/tag_lookup_result.dart';
import 'social_edge_call.dart';

/// [ConnectRepository] sobre Supabase.
class SupabaseConnectRepository implements ConnectRepository {
  SupabaseConnectRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ConnectFeedPage> feed({
    Set<ConnectFilter> filters = const <ConnectFilter>{},
    bool refresh = false,
  }) async => ConnectFeedPage.fromJson(
    await invokeEdge(
      _client,
      // POST y no GET aunque parezca una lectura: cada llamada ESCRIBE
      // (`connect_impressions` siempre, `connect_feed_runs` en un refresco). Un GET que muta se
      // cachea en un proxy y devuelve la tanda de ayer.
      'connect-feed',
      body: <String, dynamic>{
        // `Todos` (RN-35) es **no mandar ninguno**, no mandar `["all"]`. El backend acepta el
        // literal y lo ignora, pero mandar la lista vacía es lo que dice el contrato.
        if (filters.isNotEmpty)
          'filters': filters
              .map((ConnectFilter f) => f.wireValue)
              .toList(growable: false),
        'refresh': refresh,
      },
    ),
  );

  @override
  Future<void> dismiss(String userId) async {
    await invokeEdge(
      _client,
      // El `user_id` NO viaja: lo pone el backend desde el JWT. Si se pudiera mandar, cualquiera
      // llenaría de descartes la lista de otra persona y le dejaría el feed vacío.
      'connect-dismiss',
      body: <String, dynamic>{'dismissed_user_id': userId},
    );
  }

  @override
  Future<TagLookupResult?> lookupTag(String tag) async {
    try {
      return TagLookupResult.fromJson(
        await invokeEdge(
          _client,
          // POST y no `GET ?tag=`: el tag lleva `#` dentro (`alfon#K7M2QX9F`), que en una URL es el
          // delimitador de fragmento. Un cliente que se olvidara de codificarlo mandaría solo
          // `alfon` y fallaría de una forma que **parece** «no existe».
          'connect-tag-lookup',
          body: <String, dynamic>{'tag': tag},
        ),
      );
    } on SocialFailure catch (failure) {
      // AQUÍ SE CUMPLE RN-23, Y ES UNA SOLA RAMA A PROPÓSITO.
      //
      // «No existe» y «hay un bloqueo en cualquier dirección» llegan como el MISMO 404, con el
      // mismo cuerpo. Devolver `null` en los dos deja a la pantalla sin nada por lo que ramificar:
      // pinta «No existe ningún usuario con ese tag» con el mismo widget, sin rama propia, porque
      // una rama distinta acaba divergiendo en un detalle visible.
      //
      // Un tag con formato imposible también es 404, no 400, así que tampoco hace falta validarlo
      // antes: el backend ya responde igual que a uno inexistente.
      if (failure.kind == SocialFailureKind.notFound) return null;
      rethrow;
    }
  }
}
